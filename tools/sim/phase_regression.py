#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Shared regression runner for phase-local RISC-V simulations."""

from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from sim_backend import build_verilator, default_vsim, run_verilator, select_backend

BEGIN_SIGNATURE_RE = re.compile(r"^\s*([0-9a-fA-F]+)\s+<begin_signature>:")
TOHOST_RE = re.compile(r"^\s*([0-9a-fA-F]+)\s+<tohost>:")
PT_LOAD = 1
PF_W = 2
DEFAULT_FAIL_MARKERS = ("TB ERROR:", "** Error:", "** Fatal:", "Fatal:")


@dataclass(frozen=True)
class PhaseRegressionConfig:
    script_file: str
    phase_label: str
    pass_marker: str
    inherited_tests: dict[str, dict[str, Any]]
    compliance_smoke: tuple[str, ...] = ()
    compliance_exclude: tuple[str, ...] = ()
    act_smoke: tuple[str, ...] = ()
    fail_markers: tuple[str, ...] = DEFAULT_FAIL_MARKERS
    top_module: str = "riscv_tb"
    compliance_phase: str = "phase6"
    act_phase: str | None = None
    allow_act: bool = True
    compliance_boot_addr: int = 0x80
    compliance_max_cycles: int = 3000
    act_max_cycles: int = 3000
    default_boot_addr: int = 0
    default_imem_read_latency: int = 1
    default_dmem_read_latency: int = 1
    supports_latency_parameters: bool = False
    supports_addr_width_parameters: bool = False
    imem_word_addr_width: int = 13
    dmem_word_addr_width: int = 13
    act_imem_word_addr_width: int = 13
    act_dmem_word_addr_width: int = 13
    verilator_warning_suppresses: tuple[str, ...] = ()
    verilator_warnings_fatal: bool = True
    surfer_command: str = "surfer_default.sucl"
    # Product root (for example "eriscv-m0") when product_dv_layout is
    # selected; otherwise the conventional testcase root.
    testcase_root_override: str | None = None
    product_dv_layout: bool = False


def sim_dir(config: PhaseRegressionConfig) -> Path:
    return Path(config.script_file).resolve().parent


def repo_root(config: PhaseRegressionConfig) -> Path:
    for candidate in (sim_dir(config), *sim_dir(config).parents):
        if (candidate / ".git").exists():
            return candidate
    raise FileNotFoundError(f"repository root not found above {sim_dir(config)}")


def phase_testcases_dir(config: PhaseRegressionConfig) -> Path:
    if config.testcase_root_override:
        return repo_root(config) / config.testcase_root_override
    return repo_root(config) / "edu-rv32i-5s" / "testcases"


def inherited_testcase_dir(config: PhaseRegressionConfig, test_config: dict[str, Any]) -> Path:
    testcase_root = test_config.get("testcase_root")
    if testcase_root:
        return repo_root(config) / str(testcase_root) / str(test_config["phase"])

    phase = str(test_config["phase"])
    root = phase_testcases_dir(config)
    if config.product_dv_layout:
        if phase == "soc":
            return root / "dv/soc/tests"
        if phase.startswith("core/"):
            return root / "dv/core/tests" / phase.removeprefix("core/")
    return root / phase


def compliance_testcases_dir(config: PhaseRegressionConfig) -> Path:
    return phase_testcases_dir(config) / config.compliance_phase


def act_testcases_dir(config: PhaseRegressionConfig) -> Path | None:
    if config.act_phase is None:
        return None
    return phase_testcases_dir(config) / config.act_phase


def path_for_vsim(config: PhaseRegressionConfig, path: Path) -> str:
    return Path(os.path.relpath(path.resolve(), sim_dir(config))).as_posix()


def discover_compliance_tests(testcases_dir: Path) -> list[str]:
    tests: list[str] = []
    for mem in sorted(testcases_dir.glob("*.mem")):
        ref = testcases_dir / f"{mem.stem}.reference_output"
        if ref.exists():
            tests.append(mem.stem)
    return tests


def configured_compliance_tests(config: PhaseRegressionConfig) -> list[str]:
    excluded = set(config.compliance_exclude)
    return [test for test in discover_compliance_tests(compliance_testcases_dir(config)) if test not in excluded]


def discover_act_tests(testcases_dir: Path | None) -> list[str]:
    if testcases_dir is None or not testcases_dir.exists():
        return []
    tests: list[str] = []
    for manifest in sorted(testcases_dir.glob("*.act.json")):
        stem = manifest.name.removesuffix(".act.json")
        mem = testcases_dir / f"{stem}.mem"
        if mem.exists():
            tests.append(stem)
    return tests


def load_act_manifest(testcases_dir: Path, test_name: str) -> dict[str, Any]:
    manifest_path = testcases_dir / f"{test_name}.act.json"
    if not manifest_path.exists():
        raise ValueError(f"missing ACT manifest for {test_name}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(manifest, dict):
        raise ValueError(f"invalid ACT manifest for {test_name}")
    return manifest


def objdump_symbol_word_index(
    testcases_dir: Path,
    tc: str,
    pattern: re.Pattern[str],
    default: int,
    addr_width: int = 13,
) -> int:
    objdump = testcases_dir / f"{tc}.elf.objdump"
    if not objdump.exists():
        return default
    for line in objdump.read_text(encoding="utf-8", errors="replace").splitlines():
        match = pattern.match(line)
        if match:
            byte_addr = int(match.group(1), 16)
            return (byte_addr >> 2) & ((1 << addr_width) - 1)
    return default


def generate_data_mem_init(
    testcases_dir: Path,
    out_dir: Path,
    tc: str,
    addr_width: int = 13,
) -> Path | None:
    elf = testcases_dir / f"{tc}.elf"
    if not elf.exists():
        return None
    data = elf.read_bytes()
    if data[:4] != b"\x7fELF" or data[4] != 1 or data[5] != 1:
        return None
    e_phoff = struct.unpack_from("<I", data, 28)[0]
    e_phentsize = struct.unpack_from("<H", data, 42)[0]
    e_phnum = struct.unpack_from("<H", data, 44)[0]
    words: dict[int, int] = {}
    for idx in range(e_phnum):
        off = e_phoff + idx * e_phentsize
        p_type, p_offset, p_vaddr, _p_paddr, p_filesz, _p_memsz, p_flags, _p_align = (
            struct.unpack_from("<IIIIIIII", data, off)
        )
        if p_type != PT_LOAD or not (p_flags & PF_W):
            continue
        segment = data[p_offset : p_offset + p_filesz]
        for byte_off in range(0, len(segment), 4):
            chunk = segment[byte_off : byte_off + 4]
            if len(chunk) < 4:
                chunk = chunk + bytes(4 - len(chunk))
            byte_addr = p_vaddr + byte_off
            mem_index = (byte_addr >> 2) & ((1 << addr_width) - 1)
            words[mem_index] = int.from_bytes(chunk, "little")
    if not words:
        return None
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "data.mem"
    with out_path.open("w", encoding="ascii") as f:
        for mem_index in sorted(words):
            f.write(f"@{mem_index:x}\n{words[mem_index]:08x}\n")
    return out_path


def parse_args(config: PhaseRegressionConfig) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=f"Run the {config.phase_label} regression suite.")
    parser.add_argument("tests", nargs="*", help="Specific test names to run.")
    parser.add_argument(
        "--backend",
        choices=("auto", "modelsim", "verilator"),
        default="auto",
        help="Simulation backend. auto prefers Verilator when available, otherwise ModelSim.",
    )
    parser.add_argument("--vsim", default=default_vsim(), help="ModelSim executable; set VSIM or put vsim on PATH.")
    parser.add_argument("--verilator", default=os.environ.get("VERILATOR", "verilator"), help="Verilator executable.")
    parser.add_argument("--log-dir", default="regression_logs", help="Directory for per-test logs.")
    parser.add_argument("--stop-on-fail", action="store_true", help="Stop after the first failing testcase.")
    parser.add_argument("--no-wave", action="store_true", help="Compatibility flag; batch runs do not use simulator GUI waves.")
    parser.add_argument("--directed-only", action="store_true", help="Run product-directed tests.")
    parser.add_argument("--compliance-smoke", action="store_true", help="Run only the configured compliance smoke list.")
    parser.add_argument("--compliance-full", action="store_true", help="Run all compliance tests with .mem and .reference_output.")
    parser.add_argument("--act-smoke", action="store_true", help="Run only the ACT self-checking smoke list.")
    parser.add_argument("--act-full", action="store_true", help="Run all ACT tests with .act.json manifests.")
    parser.add_argument("--wave", action="store_true", help="Enable Verilator waveform dumping for selected tests.")
    parser.add_argument("--wave-test", help="Run one testcase with Verilator waveform dumping enabled.")
    parser.add_argument("--wave-dir", default="waves", help="Directory for generated waveform files.")
    parser.add_argument("--dump-format", choices=("fst", "vcd"), default="fst", help="Waveform dump format.")
    parser.add_argument("--perf-profile", action="store_true",
                        help="enable optional testbench-only performance diagnostics")
    parser.add_argument("--modelsim-gui-test", help="Launch one testcase in the ModelSim GUI with wave.do loaded.")
    parser.add_argument("--list-tests", action="store_true", help="List runnable testcase names and exit.")
    return parser.parse_args()


def run_vsim(config: PhaseRegressionConfig, vsim: str, command_body: str, log_path: Path) -> tuple[bool, str, float]:
    start = _dt.datetime.now()
    result = subprocess.run(
        [vsim, "-c", "-do", command_body],
        cwd=sim_dir(config),
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    elapsed = (_dt.datetime.now() - start).total_seconds()
    log_path.write_text(result.stdout, encoding="utf-8", errors="replace")
    if result.returncode != 0:
        return False, f"vsim exited with {result.returncode}", elapsed
    for marker in config.fail_markers:
        if marker in result.stdout:
            return False, f"found marker: {marker}", elapsed
    if config.pass_marker not in result.stdout:
        return False, "PASS marker not found", elapsed
    return True, "PASS marker found", elapsed


def prepare_modelsim_work(config: PhaseRegressionConfig, enable_acc: bool) -> None:
    """Reuse the incremental library unless its elaboration inputs changed."""
    directory = sim_dir(config)
    cache_path = directory / ".modelsim_work_cache.json"
    work_path = directory / "work"
    filelist_path = directory / "file.list"
    cache = {
        "access_mode": "acc" if enable_acc else "fast",
        "filelist_sha256": hashlib.sha256(filelist_path.read_bytes()).hexdigest(),
        "schema": 1,
        "top_module": config.top_module,
    }
    try:
        cached = json.loads(cache_path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        cached = None
    if cached != cache:
        shutil.rmtree(work_path, ignore_errors=True)
        cache_path.write_text(json.dumps(cache, sort_keys=True) + "\n", encoding="utf-8")


def write_test_result(
    log_dir: Path,
    kind: str,
    test_name: str,
    backend: str,
    passed: bool,
    reason: str,
    elapsed: float,
) -> None:
    payload = {
        "backend": backend,
        "elapsed_seconds": elapsed,
        "generated_at": _dt.datetime.now().isoformat(timespec="seconds"),
        "kind": kind,
        "passed": passed,
        "reason": reason,
        "test": test_name,
    }
    (log_dir / "result.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def write_regression_summary(
    log_root: Path, backend: str, results: list[tuple[str, str, bool, str, float]]
) -> None:
    passed = sum(result[2] for result in results)
    payload = {
        "backend": backend,
        "failed": len(results) - passed,
        "generated_at": _dt.datetime.now().isoformat(timespec="seconds"),
        "passed": passed,
        "results": [
            {
                "elapsed_seconds": elapsed,
                "kind": kind,
                "passed": test_passed,
                "reason": reason,
                "test": test_name,
            }
            for kind, test_name, test_passed, reason, elapsed in results
        ],
        "total": len(results),
    }
    (log_root / "summary.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def launch_vsim_gui(config: PhaseRegressionConfig, vsim: str, command_body: str) -> int:
    subprocess.Popen([vsim, "-gui", "-do", command_body], cwd=sim_dir(config))
    print("Started ModelSim GUI.")
    return 0


def prepare_jtag_boot_trace(
    config: PhaseRegressionConfig,
    log_dir: Path,
    test_name: str,
    test_config: dict[str, Any],
) -> tuple[Path | None, str | None]:
    """Generate a private-DMI boot trace when a directed test selects ELF boot."""
    elf_name = test_config.get("jtag_boot_elf")
    if elf_name is None:
        return None, None
    testcase_dir = inherited_testcase_dir(config, test_config)
    elf_file = testcase_dir / f"{elf_name}.elf"
    trace_file = log_dir / f"{test_name}.dmi"
    command = [
        sys.executable,
        str(repo_root(config) / "tools/sim/elf_to_dmi_boot.py"),
        str(elf_file),
        "--out",
        str(trace_file),
        "--imem-size",
        hex(int(test_config.get("jtag_boot_imem_size", 0x10000))),
    ]
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (log_dir / "jtag_boot_trace.log").write_text(result.stdout, encoding="utf-8")
    if result.returncode:
        return None, f"JTAG boot trace generation failed: {result.stdout.strip()}"
    return trace_file, None


def inherited_vsim_command(
    config: PhaseRegressionConfig,
    vsim: str,
    test_name: str,
    test_config: dict[str, Any],
    batch_mode: int,
    jtag_boot_trace_file: Path | None = None,
    perf_profile: bool = False,
) -> str:
    testcase_dir = inherited_testcase_dir(config, test_config)
    image_name = str(test_config.get("image", test_name))
    instr_mem_file = testcase_dir / f"{image_name}.mem"
    expected_regs_file = testcase_dir / f"{image_name}.expected_regs"
    trace_file = testcase_dir / f"{image_name}.trace"
    testcase_dir_vsim = path_for_vsim(config, testcase_dir)
    instr_mem_file_vsim = path_for_vsim(config, instr_mem_file)
    expected_regs_file_vsim = path_for_vsim(config, expected_regs_file)
    trace_file_vsim = path_for_vsim(config, trace_file)
    if jtag_boot_trace_file is not None:
        jtag_boot_trace_file_vsim = path_for_vsim(config, jtag_boot_trace_file)
        jtag_boot_trace_part = f"set jtag_boot_trace_file {{{jtag_boot_trace_file_vsim}}}; "
    else:
        jtag_boot_trace_part = ""
    return (
        f"set tc {test_name}; "
        f"set oracle_mode regs; "
        f"set testcase_dir {{{testcase_dir_vsim}}}; "
        f"set instr_mem_file {{{instr_mem_file_vsim}}}; "
        f"set expected_regs_file {{{expected_regs_file_vsim}}}; "
        f"set trace_file {{{trace_file_vsim}}}; "
        f"set boot_mode {test_config.get('boot_mode', 'bypass')}; "
        f"set boot_addr {test_config.get('boot_addr', config.default_boot_addr):x}; "
        f"set max_cycles {test_config['max_cycles']}; "
        f"set irq_start_cycle {test_config.get('irq_start_cycle', 0)}; "
        f"set irq_duration {test_config.get('irq_duration', 0)}; "
        f"set irq_on_muldiv_busy {test_config.get('irq_on_muldiv_busy', 0)}; "
        f"set irq_on_pmp_fault {test_config.get('irq_on_pmp_fault', 0)}; "
        f"set imem_read_latency {test_config.get('imem_read_latency', config.default_imem_read_latency)}; "
        f"set dmem_read_latency {test_config.get('dmem_read_latency', config.default_dmem_read_latency)}; "
        f"set debug_halt_cycle {test_config.get('debug_halt_cycle', -1)}; "
        f"set debug_resume_cycle {test_config.get('debug_resume_cycle', -1)}; "
        f"set debug_on_pmp_fault {test_config.get('debug_on_pmp_fault', 0)}; "
        f"set expected_debug_cause {test_config.get('expected_debug_cause', -1)}; "
        f"set reset_on_muldiv_busy {test_config.get('reset_on_muldiv_busy', 0)}; "
        f"set plic_src_cycle {test_config.get('plic_src_cycle', 0)}; "
        f"set plic_src_id {test_config.get('plic_src_id', 0)}; "
        f"set plic_src_duration {test_config.get('plic_src_duration', 0)}; "
        f"set completion_reg {test_config.get('completion_reg', -1)}; "
        f"set completion_value {test_config.get('completion_value', 0):x}; "
        f"set expected_uart_tx {{{test_config.get('expected_uart_tx', '')}}}; "
        f"set expected_uart_tx_bytes {{{test_config.get('expected_uart_tx_bytes', '')}}}; "
        f"set uart_rx_byte {{{test_config.get('uart_rx_byte', '')}}}; "
        f"set spi_miso_byte {{{test_config.get('spi_miso_byte', '')}}}; "
        f"set expected_spi_tx {{{test_config.get('expected_spi_tx', '')}}}; "
        f"set uart_baud_div {test_config.get('uart_baud_div', 8)}; "
        f"set uart_rx_start_cycle {test_config.get('uart_rx_start_cycle', 80)}; "
        f"set expected_bus_errors {{{test_config.get('expected_bus_errors', '')}}}; "
        f"set gpio_in {{{test_config.get('gpio_in', 0)}}}; "
        f"set expected_gpio_out {{{test_config.get('expected_gpio_out', '')}}}; "
        f"set expected_gpio_oe {{{test_config.get('expected_gpio_oe', '')}}}; "
        f"{jtag_boot_trace_part}"
        f"set perf_profile {int(perf_profile)}; "
        f"set batch_mode {batch_mode}; set enable_acc {0 if batch_mode else 1}; do run_sim.do"
    )


def run_inherited_modelsim(
    config: PhaseRegressionConfig,
    vsim: str,
    log_dir: Path,
    test_name: str,
    test_config: dict[str, Any],
    perf_profile: bool = False,
) -> tuple[bool, str, float]:
    testcase_dir = inherited_testcase_dir(config, test_config)
    image_name = str(test_config.get("image", test_name))
    if not (testcase_dir / f"{image_name}.mem").exists() or not (testcase_dir / f"{image_name}.expected_regs").exists():
        return False, "missing testcase image or expected-register file", 0.0
    jtag_boot_trace_file, reason = prepare_jtag_boot_trace(config, log_dir, test_name, test_config)
    if reason is not None:
        return False, reason, 0.0
    command = inherited_vsim_command(
        config, vsim, test_name, test_config, batch_mode=1,
        jtag_boot_trace_file=jtag_boot_trace_file, perf_profile=perf_profile
    )
    return run_vsim(config, vsim, command, log_dir / "run.log")


def build_verilator_for_latency(
    config: PhaseRegressionConfig,
    log_dir: Path,
    verilator: str,
    cache: dict[tuple[int, int, int, int, str | None], Path],
    imem_read_latency: int,
    dmem_read_latency: int,
    trace_format: str | None = None,
    imem_word_addr_width: int | None = None,
    dmem_word_addr_width: int | None = None,
) -> tuple[bool, str, Path]:
    if imem_word_addr_width is None:
        imem_word_addr_width = config.imem_word_addr_width
    if dmem_word_addr_width is None:
        dmem_word_addr_width = config.dmem_word_addr_width
    effective_imem_addr_width = imem_word_addr_width if config.supports_addr_width_parameters else -1
    effective_dmem_addr_width = dmem_word_addr_width if config.supports_addr_width_parameters else -1
    key = (
        imem_read_latency if config.supports_latency_parameters else -1,
        dmem_read_latency if config.supports_latency_parameters else -1,
        effective_imem_addr_width,
        effective_dmem_addr_width,
        trace_format,
    )
    if key in cache:
        return True, "cached verilator build", cache[key]
    trace_suffix = f"_{trace_format}" if trace_format else ""
    latency_suffix = (
        f"_i{imem_read_latency}_d{dmem_read_latency}" if config.supports_latency_parameters else ""
    )
    addr_suffix = (
        f"_aw_i{imem_word_addr_width}_d{dmem_word_addr_width}" if config.supports_addr_width_parameters else ""
    )
    binary_name = f"V{config.top_module}{latency_suffix}{addr_suffix}{trace_suffix}"
    build_detail = (
        f" i={imem_read_latency} d={dmem_read_latency}" if config.supports_latency_parameters else ""
    )
    if config.supports_addr_width_parameters:
        build_detail += f" imem={imem_word_addr_width} dmem={dmem_word_addr_width}"
    print(
        f"Updating Verilator simulation binary{build_detail}"
        f"{' trace=' + trace_format if trace_format else ''} ... ",
        end="",
        flush=True,
    )
    parameter_overrides: dict[str, int] = {}
    if config.supports_latency_parameters:
        parameter_overrides["IMEM_READ_LATENCY"] = imem_read_latency
        parameter_overrides["DMEM_READ_LATENCY"] = dmem_read_latency
    if config.supports_addr_width_parameters:
        parameter_overrides["IMEM_WORD_ADDR_WIDTH"] = imem_word_addr_width
        parameter_overrides["DMEM_WORD_ADDR_WIDTH"] = dmem_word_addr_width
    if not parameter_overrides:
        parameter_overrides = None
    # Suppress SELRANGE for compliance tests with smaller memory; suppress
    # WIDTHTRUNC/WIDTHEXPAND for 8-bit HPM event indices in the RTL.
    warning_suppresses = ["WIDTHTRUNC", "WIDTHEXPAND", *config.verilator_warning_suppresses]
    if dmem_word_addr_width < 17:
        warning_suppresses.append("SELRANGE")
    warning_suppresses = tuple(warning_suppresses)
    built, reason, binary = build_verilator(
        sim_dir(config),
        log_dir,
        verilator,
        config.top_module,
        binary_name=binary_name,
        parameter_overrides=parameter_overrides,
        trace_format=trace_format,
        trace_structs=trace_format is not None,
        warning_suppresses=warning_suppresses,
        warnings_fatal=config.verilator_warnings_fatal,
    )
    print("PASS" if built else "FAIL")
    if built:
        cache[key] = binary
    return built, reason, binary


def run_inherited_verilator(
    config: PhaseRegressionConfig,
    binary: Path,
    log_dir: Path,
    test_name: str,
    test_config: dict[str, Any],
    dump_file: Path | None = None,
    perf_profile: bool = False,
) -> tuple[bool, str, float]:
    testcase_dir = inherited_testcase_dir(config, test_config)
    image_name = str(test_config.get("image", test_name))
    instr_mem_file = testcase_dir / f"{image_name}.mem"
    expected_regs_file = testcase_dir / f"{image_name}.expected_regs"
    trace_file = testcase_dir / f"{image_name}.trace"
    if not instr_mem_file.exists() or not expected_regs_file.exists():
        return False, "missing testcase image or expected-register file", 0.0
    jtag_boot_trace_file, reason = prepare_jtag_boot_trace(config, log_dir, test_name, test_config)
    if reason is not None:
        return False, reason, 0.0
    plusargs = [
        f"+tc={test_name}",
        "+oracle_mode=regs",
        f"+testcase_dir={testcase_dir.resolve().as_posix()}",
        f"+instr_mem_file={instr_mem_file.resolve().as_posix()}",
        f"+expected_regs_file={expected_regs_file.resolve().as_posix()}",
        f"+boot_addr={test_config.get('boot_addr', config.default_boot_addr):x}",
        f"+max_cycles={test_config['max_cycles']}",
        f"+irq_start_cycle={test_config.get('irq_start_cycle', 0)}",
        f"+irq_duration={test_config.get('irq_duration', 0)}",
        f"+irq_on_muldiv_busy={test_config.get('irq_on_muldiv_busy', 0)}",
        f"+irq_on_pmp_fault={test_config.get('irq_on_pmp_fault', 0)}",
        f"+debug_halt_cycle={test_config.get('debug_halt_cycle', -1)}",
        f"+debug_resume_cycle={test_config.get('debug_resume_cycle', -1)}",
        f"+debug_on_pmp_fault={test_config.get('debug_on_pmp_fault', 0)}",
        f"+expected_debug_cause={test_config.get('expected_debug_cause', -1)}",
        f"+reset_on_muldiv_busy={test_config.get('reset_on_muldiv_busy', 0)}",
        f"+plic_src_cycle={test_config.get('plic_src_cycle', 0)}",
        f"+plic_src_id={test_config.get('plic_src_id', 0)}",
        f"+plic_src_duration={test_config.get('plic_src_duration', 0)}",
    ]
    if trace_file.exists():
        plusargs.append(f"+trace_file={trace_file.resolve().as_posix()}")
    if jtag_boot_trace_file is not None:
        plusargs.append(f"+jtag_boot_trace_file={jtag_boot_trace_file.resolve().as_posix()}")
    if perf_profile:
        plusargs.append("+perf_profile=1")
    optional_plusargs = (
        "boot_mode",
        "uart_baud_div",
        "uart_rx_start_cycle",
        "expected_uart_tx",
        "expected_uart_tx_bytes",
        "uart_rx_byte",
        "spi_miso_byte",
        "expected_spi_tx",
        "expected_bus_errors",
        "gpio_in",
        "completion_reg",
        "completion_value",
    )
    for key in optional_plusargs:
        if key in test_config:
            plusargs.append(f"+{key}={test_config[key]}")
    if dump_file is not None:
        dump_file.parent.mkdir(parents=True, exist_ok=True)
        plusargs.extend(["+dump_wave", f"+dump_file={dump_file.resolve().as_posix()}"])
    return run_verilator(binary, plusargs, log_dir / "run.log", config.pass_marker, config.fail_markers)


def run_compliance_modelsim(
    config: PhaseRegressionConfig,
    vsim: str,
    log_dir: Path,
    data_dir: Path,
    test_name: str,
    perf_profile: bool = False,
) -> tuple[bool, str, float]:
    try:
        command = compliance_vsim_command(
            config, vsim, data_dir, test_name, batch_mode=1, perf_profile=perf_profile
        )
    except ValueError as exc:
        return False, str(exc), 0.0
    return run_vsim(config, vsim, command, log_dir / "run.log")


def compliance_vsim_command(
    config: PhaseRegressionConfig,
    vsim: str,
    data_dir: Path,
    test_name: str,
    batch_mode: int,
    perf_profile: bool = False,
) -> str:
    testcase_dir = compliance_testcases_dir(config)
    instr_mem_file = testcase_dir / f"{test_name}.mem"
    reference_output_file = testcase_dir / f"{test_name}.reference_output"
    if not instr_mem_file.exists() or not reference_output_file.exists():
        raise ValueError(f"missing compliance .mem or .reference_output file for {test_name}")
    sig_base = objdump_symbol_word_index(testcase_dir, test_name, BEGIN_SIGNATURE_RE, default=0x80, addr_width=config.dmem_word_addr_width)
    tohost_addr = objdump_symbol_word_index(testcase_dir, test_name, TOHOST_RE, default=0x0, addr_width=config.dmem_word_addr_width)
    data_mem_file = generate_data_mem_init(testcase_dir, data_dir, test_name, addr_width=config.dmem_word_addr_width)
    testcase_dir_vsim = path_for_vsim(config, testcase_dir)
    instr_mem_file_vsim = path_for_vsim(config, instr_mem_file)
    reference_output_file_vsim = path_for_vsim(config, reference_output_file)
    if data_mem_file:
        data_mem_part = f"set data_mem_file {{{path_for_vsim(config, data_mem_file)}}}; "
    else:
        data_mem_part = "set data_mem_file {}; "
    command = (
        f"set tc {test_name}; "
        f"set oracle_mode signature; "
        f"set testcase_dir {{{testcase_dir_vsim}}}; "
        f"set instr_mem_file {{{instr_mem_file_vsim}}}; "
        f"set reference_output_file {{{reference_output_file_vsim}}}; "
        f"set sig_base {sig_base:x}; "
        f"set tohost_addr {tohost_addr:x}; "
        f"set boot_addr {config.compliance_boot_addr:x}; "
        f"{data_mem_part}"
        f"set perf_profile {int(perf_profile)}; "
        f"set max_cycles {config.compliance_max_cycles}; set batch_mode {batch_mode}; "
        f"set enable_acc {0 if batch_mode else 1}; do run_sim.do"
    )
    return command


def run_compliance_verilator(
    config: PhaseRegressionConfig,
    binary: Path,
    log_dir: Path,
    data_dir: Path,
    test_name: str,
    dump_file: Path | None = None,
    perf_profile: bool = False,
) -> tuple[bool, str, float]:
    testcase_dir = compliance_testcases_dir(config)
    instr_mem_file = testcase_dir / f"{test_name}.mem"
    reference_output_file = testcase_dir / f"{test_name}.reference_output"
    if not instr_mem_file.exists() or not reference_output_file.exists():
        return False, "missing compliance .mem or .reference_output file", 0.0
    sig_base = objdump_symbol_word_index(testcase_dir, test_name, BEGIN_SIGNATURE_RE, default=0x80, addr_width=config.dmem_word_addr_width)
    tohost_addr = objdump_symbol_word_index(testcase_dir, test_name, TOHOST_RE, default=0x0, addr_width=config.dmem_word_addr_width)
    data_mem_file = generate_data_mem_init(testcase_dir, data_dir, test_name, addr_width=config.dmem_word_addr_width)
    plusargs = [
        f"+tc={test_name}",
        "+oracle_mode=signature",
        f"+testcase_dir={testcase_dir.resolve().as_posix()}",
        f"+instr_mem_file={instr_mem_file.resolve().as_posix()}",
        f"+reference_output_file={reference_output_file.resolve().as_posix()}",
        f"+sig_base={sig_base:x}",
        f"+tohost_addr={tohost_addr:x}",
        f"+boot_addr={config.compliance_boot_addr:x}",
        f"+max_cycles={config.compliance_max_cycles}",
        "+irq_start_cycle=0",
        "+irq_duration=0",
    ]
    if data_mem_file:
        plusargs.append(f"+data_mem_file={data_mem_file.resolve().as_posix()}")
    if perf_profile:
        plusargs.append("+perf_profile=1")
    if dump_file is not None:
        dump_file.parent.mkdir(parents=True, exist_ok=True)
        plusargs.extend(["+dump_wave", f"+dump_file={dump_file.resolve().as_posix()}"])
    return run_verilator(binary, plusargs, log_dir / "run.log", config.pass_marker, config.fail_markers)


def act_vsim_command(
    config: PhaseRegressionConfig,
    vsim: str,
    test_name: str,
    batch_mode: int,
    perf_profile: bool = False,
) -> str:
    testcase_dir = act_testcases_dir(config)
    if testcase_dir is None:
        raise ValueError("ACT tests are not configured for this phase")
    instr_mem_file = testcase_dir / f"{test_name}.mem"
    if not instr_mem_file.exists():
        raise ValueError(f"missing ACT .mem file for {test_name}")
    manifest = load_act_manifest(testcase_dir, test_name)
    data_mem_file = testcase_dir / f"{test_name}.data.mem"
    testcase_dir_vsim = path_for_vsim(config, testcase_dir)
    instr_mem_file_vsim = path_for_vsim(config, instr_mem_file)
    if data_mem_file.exists():
        data_mem_part = f"set data_mem_file {{{path_for_vsim(config, data_mem_file)}}}; "
    else:
        data_mem_part = "set data_mem_file {}; "
    command = (
        f"set tc {test_name}; "
        f"set oracle_mode act; "
        f"set testcase_dir {{{testcase_dir_vsim}}}; "
        f"set instr_mem_file {{{instr_mem_file_vsim}}}; "
        f"set sig_base {int(manifest.get('sig_base', 0x80)):x}; "
        f"set tohost_addr {int(manifest.get('tohost_addr', 0)):x}; "
        f"set tohost_pass_value {int(manifest.get('tohost_pass_value', 1)):x}; "
        f"set tohost_fail_value {int(manifest.get('tohost_fail_value', 3)):x}; "
        f"set boot_addr {int(manifest.get('boot_addr', config.compliance_boot_addr)):x}; "
        f"set act_exec_data_mirror {1 if manifest.get('exec_data_mirror', False) else 0}; "
        f"{data_mem_part}"
        f"set perf_profile {int(perf_profile)}; "
        f"set max_cycles {int(manifest.get('max_cycles', config.act_max_cycles))}; set batch_mode {batch_mode}; "
        f"set enable_acc {0 if batch_mode else 1}; do run_sim.do"
    )
    return command


def run_act_modelsim(
    config: PhaseRegressionConfig,
    vsim: str,
    log_dir: Path,
    test_name: str,
    perf_profile: bool = False,
) -> tuple[bool, str, float]:
    try:
        command = act_vsim_command(config, vsim, test_name, batch_mode=1, perf_profile=perf_profile)
    except ValueError as exc:
        return False, str(exc), 0.0
    return run_vsim(config, vsim, command, log_dir / "run.log")


def run_act_verilator(
    config: PhaseRegressionConfig,
    binary: Path,
    log_dir: Path,
    test_name: str,
    dump_file: Path | None = None,
    perf_profile: bool = False,
) -> tuple[bool, str, float]:
    testcase_dir = act_testcases_dir(config)
    if testcase_dir is None:
        return False, "ACT tests are not configured for this phase", 0.0
    instr_mem_file = testcase_dir / f"{test_name}.mem"
    if not instr_mem_file.exists():
        return False, "missing ACT .mem file", 0.0
    manifest = load_act_manifest(testcase_dir, test_name)
    data_mem_file = testcase_dir / f"{test_name}.data.mem"
    plusargs = [
        f"+tc={test_name}",
        "+oracle_mode=act",
        f"+testcase_dir={testcase_dir.resolve().as_posix()}",
        f"+instr_mem_file={instr_mem_file.resolve().as_posix()}",
        f"+sig_base={int(manifest.get('sig_base', 0x80)):x}",
        f"+tohost_addr={int(manifest.get('tohost_addr', 0)):x}",
        f"+tohost_pass_value={int(manifest.get('tohost_pass_value', 1)):x}",
        f"+tohost_fail_value={int(manifest.get('tohost_fail_value', 3)):x}",
        f"+boot_addr={int(manifest.get('boot_addr', config.compliance_boot_addr)):x}",
        f"+max_cycles={int(manifest.get('max_cycles', config.act_max_cycles))}",
        "+irq_start_cycle=0",
        "+irq_duration=0",
    ]
    if data_mem_file.exists():
        plusargs.append(f"+data_mem_file={data_mem_file.resolve().as_posix()}")
    if manifest.get("exec_data_mirror", False):
        plusargs.append("+act_exec_data_mirror")
    if perf_profile:
        plusargs.append("+perf_profile=1")
    if dump_file is not None:
        dump_file.parent.mkdir(parents=True, exist_ok=True)
        plusargs.extend(["+dump_wave", f"+dump_file={dump_file.resolve().as_posix()}"])
    return run_verilator(binary, plusargs, log_dir / "run.log", config.pass_marker, config.fail_markers)


def selected_tests(config: PhaseRegressionConfig, args: argparse.Namespace) -> list[tuple[str, str]]:
    if args.modelsim_gui_test:
        args.tests = [args.modelsim_gui_test]
    if args.wave_test:
        args.wave = True
        args.tests = [args.wave_test]
    if not config.allow_act and (args.act_smoke or args.act_full):
        raise ValueError(
            f"ACT4 is restricted to the core regression entry point; {config.phase_label} does not run ACT4"
        )
    compliance_tests = configured_compliance_tests(config)
    act_tests = discover_act_tests(act_testcases_dir(config))
    if args.act_smoke or args.act_full:
        product_root = Path(config.testcase_root_override or "this product")
        product = product_root.name.removeprefix("eriscv-")
        generate_hint = (
            f"generate it with `make act-generate-{product}` (native) or "
            f"`make act-generate-{product}-container` (Docker)"
        )
        if not act_tests:
            raise ValueError(f"ACT4 cache is missing or empty; {generate_hint} first")
        if args.act_smoke:
            missing_smoke = [test for test in config.act_smoke if test not in act_tests]
            if missing_smoke:
                raise ValueError(
                    f"ACT4 cache is incomplete ({', '.join(missing_smoke)}); {generate_hint} first"
                )
    if args.tests:
        known = set(config.inherited_tests) | set(compliance_tests) | set(act_tests)
        unknown = [test for test in args.tests if test not in known]
        if unknown:
            raise ValueError("Unknown testcase(s): " + ", ".join(unknown))
        selected: list[tuple[str, str]] = []
        for test in args.tests:
            if test in config.inherited_tests:
                selected.append(("directed", test))
            elif test in compliance_tests:
                selected.append(("compliance", test))
            else:
                selected.append(("act", test))
        return selected
    # Keep foundational pipeline phases first in normal regressions. The
    # remaining product-directed tests retain their declaration order, which
    # preserves product-specific grouping. Explicit TESTS= order is untouched.
    default_directed_with_index = [
        (index, test)
        for index, (test, test_config) in enumerate(config.inherited_tests.items())
        if not test_config.get("dedicated_latency", False)
    ]

    def directed_order(item: tuple[int, str]) -> tuple[int, int, int]:
        index, test = item
        phase_match = re.match(r"^P(\d+)-", test)
        if phase_match:
            return (0, int(phase_match.group(1)), index)
        return (1, 0, index)

    default_directed = [test for _, test in sorted(default_directed_with_index, key=directed_order)]
    if args.directed_only or args.compliance_smoke or args.compliance_full or args.act_smoke or args.act_full:
        selected: list[tuple[str, str]] = []
        if args.directed_only:
            selected += [("directed", test) for test in default_directed]
        if args.compliance_smoke:
            selected += [("compliance", test) for test in config.compliance_smoke]
        if args.compliance_full:
            selected += [("compliance", test) for test in compliance_tests]
        if args.act_smoke:
            selected += [("act", test) for test in config.act_smoke]
        if args.act_full:
            selected += [("act", test) for test in act_tests]
        return selected
    default_tests = (
        [("directed", test) for test in default_directed]
        + [("compliance", test) for test in config.compliance_smoke]
    )
    missing_smoke = [test for test in config.act_smoke if test not in act_tests]
    if missing_smoke:
        product_root = Path(config.testcase_root_override or "this product")
        product = product_root.name.removeprefix("eriscv-")
        print(
            "*** ACT4 SMOKE SKIPPED: cache is missing or incomplete "
            f"({', '.join(missing_smoke)}). Generate it with "
            f"`make act-generate-{product}` (native) or "
            f"`make act-generate-{product}-container` (Docker). ***",
            file=sys.stderr,
        )
        return default_tests
    return default_tests + [("act", test) for test in config.act_smoke]


def list_tests(config: PhaseRegressionConfig) -> None:
    print("Directed tests:")
    for name in config.inherited_tests:
        print(f"  {name}")
    print()
    print("Compliance smoke tests:")
    for name in config.compliance_smoke:
        print(f"  {name}")
    print()
    print("Compliance full tests with .reference_output:")
    for name in configured_compliance_tests(config):
        print(f"  {name}")
    print()
    if config.allow_act:
        print("ACT smoke tests:")
        for name in config.act_smoke:
            print(f"  {name}")
        print()
        print("ACT full tests with .act.json manifests:")
        for name in discover_act_tests(act_testcases_dir(config)):
            print(f"  {name}")
    else:
        print("ACT4: unavailable from this SoC regression entry point")


def run_phase_regression(config: PhaseRegressionConfig) -> int:
    args = parse_args(config)
    if args.list_tests:
        list_tests(config)
        return 0
    log_root = sim_dir(config) / args.log_dir
    data_root = sim_dir(config) / "regression_data"
    build_log_dir = log_root / "build"
    build_log_dir.mkdir(parents=True, exist_ok=True)
    try:
        backend = select_backend(args.backend, args.vsim, args.verilator)
        tests = selected_tests(config, args)
    except (RuntimeError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 2
    if args.modelsim_gui_test:
        if len(tests) != 1:
            print("--modelsim-gui-test requires exactly one testcase", file=sys.stderr)
            return 2
        kind, test_name = tests[0]
        if kind == "directed":
            gui_log_dir = log_root / kind / test_name
            gui_log_dir.mkdir(parents=True, exist_ok=True)
            jtag_boot_trace_file, reason = prepare_jtag_boot_trace(
                config, gui_log_dir, test_name, config.inherited_tests[test_name]
            )
            if reason is not None:
                print(reason, file=sys.stderr)
                return 2
            command = inherited_vsim_command(
                config,
                args.vsim,
                test_name,
                config.inherited_tests[test_name],
                batch_mode=0,
                jtag_boot_trace_file=jtag_boot_trace_file,
                perf_profile=args.perf_profile,
            )
        elif kind == "compliance":
            try:
                command = compliance_vsim_command(
                    config, args.vsim, data_root / kind / test_name, test_name, batch_mode=0,
                    perf_profile=args.perf_profile
                )
            except ValueError as exc:
                print(str(exc), file=sys.stderr)
                return 2
        elif kind == "act":
            try:
                command = act_vsim_command(
                    config, args.vsim, test_name, batch_mode=0, perf_profile=args.perf_profile
                )
            except ValueError as exc:
                print(str(exc), file=sys.stderr)
                return 2
        else:
            print(f"--modelsim-gui-test does not support testcase kind {kind}", file=sys.stderr)
            return 2
        prepare_modelsim_work(config, enable_acc=True)
        return launch_vsim_gui(config, args.vsim, command)
    if backend == "modelsim":
        prepare_modelsim_work(config, enable_acc=False)
        verilator_binaries: dict[tuple[int, int, str | None], Path] = {}
    else:
        # Keep obj_dir across invocations so Verilator/Make can reuse generated
        # C++ objects when the file list and elaborated design are unchanged.
        # The simulation Makefile's clean target remains the explicit rebuild.
        verilator_binaries = {}
    if args.wave and backend != "verilator":
        print("--wave requires --backend verilator", file=sys.stderr)
        return 2
    wave_dir = sim_dir(config) / args.wave_dir
    failures = 0
    results: list[tuple[str, str, bool, str, float]] = []
    for kind, test_name in tests:
        print(f"{test_name} ({kind}) ... ", end="", flush=True)
        test_log_dir = log_root / kind / test_name
        test_log_dir.mkdir(parents=True, exist_ok=True)
        if kind == "directed":
            test_config = config.inherited_tests[test_name]
            if backend == "modelsim":
                passed, reason, elapsed = run_inherited_modelsim(
                    config, args.vsim, test_log_dir, test_name, test_config,
                    perf_profile=args.perf_profile
                )
            else:
                built, reason, binary = build_verilator_for_latency(
                    config,
                    build_log_dir,
                    args.verilator,
                    verilator_binaries,
                    test_config.get("imem_read_latency", config.default_imem_read_latency),
                    test_config.get("dmem_read_latency", config.default_dmem_read_latency),
                    args.dump_format if args.wave else None,
                )
                if not built:
                    passed, elapsed = False, 0.0
                else:
                    passed, reason, elapsed = run_inherited_verilator(
                        config,
                        binary,
                        test_log_dir,
                        test_name,
                        test_config,
                        wave_dir / f"{test_name}.{args.dump_format}" if args.wave else None,
                        perf_profile=args.perf_profile,
                    )
        elif kind == "compliance":
            if backend == "modelsim":
                passed, reason, elapsed = run_compliance_modelsim(
                    config, args.vsim, test_log_dir, data_root / kind / test_name, test_name,
                    perf_profile=args.perf_profile
                )
            else:
                built, reason, binary = build_verilator_for_latency(
                    config,
                    build_log_dir,
                    args.verilator,
                    verilator_binaries,
                    config.default_imem_read_latency,
                    config.default_dmem_read_latency,
                    args.dump_format if args.wave else None,
                )
                if not built:
                    passed, elapsed = False, 0.0
                else:
                    passed, reason, elapsed = run_compliance_verilator(
                        config,
                        binary,
                        test_log_dir,
                        data_root / kind / test_name,
                        test_name,
                        wave_dir / f"{test_name}.{args.dump_format}" if args.wave else None,
                        perf_profile=args.perf_profile,
                    )
        else:
            if backend == "modelsim":
                passed, reason, elapsed = run_act_modelsim(
                    config, args.vsim, test_log_dir, test_name, perf_profile=args.perf_profile
                )
            else:
                built, reason, binary = build_verilator_for_latency(
                    config,
                    build_log_dir,
                    args.verilator,
                    verilator_binaries,
                    config.default_imem_read_latency,
                    config.default_dmem_read_latency,
                    args.dump_format if args.wave else None,
                    config.act_imem_word_addr_width,
                    config.act_dmem_word_addr_width,
                )
                if not built:
                    passed, elapsed = False, 0.0
                else:
                    passed, reason, elapsed = run_act_verilator(
                        config,
                        binary,
                        test_log_dir,
                        test_name,
                        wave_dir / f"{test_name}.{args.dump_format}" if args.wave else None,
                        perf_profile=args.perf_profile,
                    )
        print("PASS" if passed else "FAIL")
        results.append((kind, test_name, passed, reason, elapsed))
        write_test_result(test_log_dir, kind, test_name, backend, passed, reason, elapsed)
        if not passed:
            failures += 1
            if args.stop_on_fail:
                break
    print()
    print(f"Regression summary ({backend})")
    print("==================")
    for kind, test_name, passed, reason, elapsed in results:
        status = "PASS" if passed else "FAIL"
        print(f"{status:4} {kind:10} {test_name:18} {elapsed:6.1f}s  {reason}")
    print("------------------")
    print(f"Total: {len(results)}, Passed: {len(results) - failures}, Failed: {failures}")
    write_regression_summary(log_root, backend, results)
    if args.wave and failures == 0:
        print(f"Waveforms: {wave_dir.resolve().as_posix()}")
        surfer_command = sim_dir(config) / config.surfer_command
        if surfer_command.exists():
            print(f"Open with: surfer --command-file {config.surfer_command} <waveform>")
        else:
            print("Open with: surfer <waveform>")
    return 0 if failures == 0 else 1
