#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Shared ModelSim and Verilator regression helpers."""

from __future__ import annotations

import datetime as _dt
import os
import shutil
import subprocess
import sys
from pathlib import Path
import argparse


def executable_available(executable: str) -> bool:
    if sys.platform.startswith("linux") and executable.lower().endswith(".exe"):
        if not Path("/proc/sys/fs/binfmt_misc/WSLInterop").exists():
            return False
    if os.sep in executable or (os.altsep and os.altsep in executable):
        return Path(executable).exists()
    return shutil.which(executable) is not None


def default_vsim() -> str:
    return os.environ.get("VSIM") or shutil.which("vsim.exe") or shutil.which("vsim") or "vsim"


def select_backend(requested: str, vsim: str, verilator: str) -> str:
    if requested != "auto":
        return requested
    if executable_available(verilator):
        return "verilator"
    if executable_available(vsim):
        return "modelsim"
    raise RuntimeError("No simulator found: install ModelSim/vsim or Verilator, or pass --backend explicitly.")


def build_verilator(
    sim_dir: Path,
    log_dir: Path,
    verilator: str,
    top_module: str,
    file_list: str = "file.list",
    binary_name: str | None = None,
    parameter_overrides: dict[str, int] | None = None,
    warning_suppresses: tuple[str, ...] = (),
    warnings_fatal: bool = True,
    trace_format: str | None = None,
    trace_structs: bool = False,
) -> tuple[bool, str, Path]:
    binary_stem = binary_name or f"V{top_module}"
    binary_path = sim_dir / "obj_dir" / binary_stem
    command = [
        verilator,
        "--binary",
        "--build-jobs",
        "16",
        "--output-split",
        "5000",
        "--output-split-cfuncs",
        "2000",
        "-CFLAGS",
        "-O0",
        "--sv",
        "--timing",
        "-Wno-TIMESCALEMOD",
        "-Wno-CASEINCOMPLETE",
        "-f",
        file_list,
        "--top-module",
        top_module,
    ]
    if not warnings_fatal:
        command.append("-Wno-fatal")
    if trace_format == "fst":
        command.append("--trace-fst")
    elif trace_format == "vcd":
        command.append("--trace")
    elif trace_format is not None:
        return False, f"unsupported Verilator trace format: {trace_format}", binary_path
    if trace_structs:
        command.append("--trace-structs")
    for warning in warning_suppresses:
        command.append(f"-Wno-{warning}")
    for name, value in sorted((parameter_overrides or {}).items()):
        command.append(f"-G{name}={value}")
    if binary_name:
        command.extend(["-o", binary_stem])

    result = subprocess.run(
        command,
        cwd=sim_dir,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    suffix = f"_{binary_stem}" if binary_name else ""
    (log_dir / f"verilator_build{suffix}.log").write_text(result.stdout, encoding="utf-8", errors="replace")
    if result.returncode != 0:
        return False, f"verilator build exited with {result.returncode}", binary_path
    return True, "verilator build passed", binary_path


def run_verilator(
    binary: Path,
    plusargs: list[str],
    log_path: Path,
    pass_marker: str,
    fail_markers: tuple[str, ...],
    allow_stop_after_pass: bool = False,
) -> tuple[bool, str, float]:
    start = _dt.datetime.now()
    result = subprocess.run(
        [str(binary), *plusargs],
        cwd=binary.parents[1],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    elapsed = (_dt.datetime.now() - start).total_seconds()
    log_path.write_text(result.stdout, encoding="utf-8", errors="replace")

    for marker in fail_markers:
        if marker in result.stdout:
            return False, f"found marker: {marker}", elapsed
    if result.returncode != 0 and allow_stop_after_pass and pass_marker in result.stdout and "Verilog $stop" in result.stdout:
        return True, "PASS marker found before Verilog $stop", elapsed
    if result.returncode != 0:
        return False, f"verilator simulation exited with {result.returncode}", elapsed
    if pass_marker not in result.stdout:
        return False, "PASS marker not found", elapsed
    return True, "PASS marker found", elapsed


def run_modelsim(
    sim_dir: Path,
    vsim: str,
    command_body: str,
    log_path: Path,
    pass_marker: str,
    fail_markers: tuple[str, ...],
) -> tuple[bool, str, float]:
    start = _dt.datetime.now()
    result = subprocess.run(
        [vsim, "-c", "-do", command_body],
        cwd=sim_dir,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    elapsed = (_dt.datetime.now() - start).total_seconds()
    log_path.write_text(result.stdout, encoding="utf-8", errors="replace")

    if result.returncode != 0:
        return False, f"vsim exited with {result.returncode}", elapsed
    for marker in fail_markers:
        if marker in result.stdout:
            return False, f"found marker: {marker}", elapsed
    if pass_marker not in result.stdout:
        return False, "PASS marker not found", elapsed
    return True, "PASS marker found", elapsed


def path_for_vsim(vsim: str, path: Path) -> str:
    resolved = path.resolve()
    if sys.platform.startswith("linux") and vsim.lower().endswith(".exe"):
        result = subprocess.run(
            ["wslpath", "-w", str(resolved)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
        return result.stdout.strip().replace("\\", "/")
    return resolved.as_posix()


def launch_modelsim_gui(sim_dir: Path, vsim: str, command_body: str) -> int:
    subprocess.Popen([vsim, "-gui", "-do", command_body], cwd=sim_dir)
    print("Started ModelSim GUI.")
    return 0


def add_backend_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--backend",
        choices=("auto", "modelsim", "verilator"),
        default="auto",
        help="Simulation backend. auto prefers Verilator when available, otherwise ModelSim.",
    )
    parser.add_argument("--vsim", default=default_vsim(), help="ModelSim executable; set VSIM or put vsim on PATH.")
    parser.add_argument("--verilator", default=os.environ.get("VERILATOR", "verilator"), help="Verilator executable.")


def directed_plusargs(
    test_name: str,
    testcase_dir: Path,
    instr_mem_file: Path,
    expected_regs_file: Path,
    max_cycles: int,
    boot_addr: int = 0,
    trace_file: Path | None = None,
) -> list[str]:
    plusargs = [
        f"+tc={test_name}",
        f"+testcase_dir={testcase_dir.resolve().as_posix()}",
        f"+instr_mem_file={instr_mem_file.resolve().as_posix()}",
        f"+expected_regs_file={expected_regs_file.resolve().as_posix()}",
        f"+boot_addr={boot_addr:x}",
        f"+max_cycles={max_cycles}",
    ]
    if trace_file and trace_file.exists():
        plusargs.append(f"+trace_file={trace_file.resolve().as_posix()}")
    return plusargs


def run_directed_phase_regression(
    script_file: str,
    phase_label: str,
    tests_config: dict[str, dict[str, int | str]],
    pass_marker: str,
    fail_markers: tuple[str, ...],
) -> int:
    parser = argparse.ArgumentParser(description=f"Run the {phase_label} regression suite.")
    parser.add_argument("tests", nargs="*", help=f"Testcase names; defaults to the full {phase_label} suite.")
    add_backend_args(parser)
    parser.add_argument("--log-dir", default="regression_logs", help="Directory for per-test logs.")
    parser.add_argument("--stop-on-fail", action="store_true", help="Stop after the first failing testcase.")
    parser.add_argument("--no-wave", action="store_true", help="Compatibility flag; batch runs do not use simulator GUI waves.")
    parser.add_argument("--wave", action="store_true", help="Enable Verilator waveform dumping for selected tests.")
    parser.add_argument("--wave-test", help="Run one testcase with Verilator waveform dumping enabled.")
    parser.add_argument("--wave-dir", default="waves", help="Directory for generated waveform files.")
    parser.add_argument("--dump-format", choices=("fst", "vcd"), default="fst", help="Waveform dump format.")
    parser.add_argument("--modelsim-gui-test", help="Launch one testcase in the ModelSim GUI with wave.do loaded.")
    parser.add_argument("--list-tests", action="store_true", help="List runnable testcase names and exit.")
    args = parser.parse_args()

    if args.list_tests:
        print("Directed tests:")
        for test_name in tests_config:
            print(f"  {test_name}")
        return 0

    if args.modelsim_gui_test:
        args.tests = [args.modelsim_gui_test]
    if args.wave_test:
        args.wave = True
        args.tests = [args.wave_test]

    selected_tests = args.tests or list(tests_config)
    unknown = [test for test in selected_tests if test not in tests_config]
    if unknown:
        print(f"Unknown {phase_label} testcase(s): " + ", ".join(unknown), file=sys.stderr)
        return 2

    sim_dir = Path(script_file).resolve().parent
    log_dir = sim_dir / args.log_dir
    log_dir.mkdir(exist_ok=True)

    if args.modelsim_gui_test:
        test_name = selected_tests[0]
        config = tests_config[test_name]
        testcase_dir = (sim_dir / ".." / ".." / ".." / "testcases" / str(config["phase"])).resolve()
        instr_mem_file = testcase_dir / f"{test_name}.mem"
        expected_regs_file = testcase_dir / f"{test_name}.expected_regs"
        trace_file = testcase_dir / f"{test_name}.trace"
        command_body = (
            f"set tc {test_name}; "
            f"set testcase_dir {{{path_for_vsim(args.vsim, testcase_dir)}}}; "
            f"set instr_mem_file {{{path_for_vsim(args.vsim, instr_mem_file)}}}; "
            f"set expected_regs_file {{{path_for_vsim(args.vsim, expected_regs_file)}}}; "
            f"set trace_file {{{path_for_vsim(args.vsim, trace_file)}}}; "
            f"set boot_addr 0; set max_cycles {int(config['max_cycles'])}; set batch_mode 0; do run_sim.do"
        )
        return launch_modelsim_gui(sim_dir, args.vsim, command_body)

    try:
        backend = select_backend(args.backend, args.vsim, args.verilator)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    if args.wave and backend != "verilator":
        print("--wave requires --backend verilator", file=sys.stderr)
        return 2

    if backend == "modelsim":
        shutil.rmtree(sim_dir / "work", ignore_errors=True)
        verilator_binary = None
    else:
        # Preserve obj_dir for incremental Verilator/Make rebuilds. Use the
        # simulation Makefile's clean target to force a full rebuild.
        print("Updating Verilator simulation binary ... ", end="", flush=True)
        built, reason, verilator_binary = build_verilator(
            sim_dir,
            log_dir,
            args.verilator,
            "riscv_tb",
            trace_format=args.dump_format if args.wave else None,
            trace_structs=args.wave,
        )
        print("PASS" if built else "FAIL")
        if not built:
            print(reason, file=sys.stderr)
            return 1

    wave_dir = sim_dir / args.wave_dir
    failures = 0
    for test_name in selected_tests:
        config = tests_config[test_name]
        testcase_dir = (sim_dir / ".." / ".." / ".." / "testcases" / str(config["phase"])).resolve()
        instr_mem_file = testcase_dir / f"{test_name}.mem"
        expected_regs_file = testcase_dir / f"{test_name}.expected_regs"
        trace_file = testcase_dir / f"{test_name}.trace"
        if not instr_mem_file.exists() or not expected_regs_file.exists():
            print(f"{test_name} ... FAIL")
            (log_dir / f"{test_name}.log").write_text(
                "missing testcase image or expected-register file",
                encoding="utf-8",
            )
            failures += 1
            if args.stop_on_fail:
                break
            continue

        print(f"{test_name} ... ", end="", flush=True)
        max_cycles = int(config["max_cycles"])
        if backend == "modelsim":
            command_body = (
                f"set tc {test_name}; "
                f"set testcase_dir {{{path_for_vsim(args.vsim, testcase_dir)}}}; "
                f"set instr_mem_file {{{path_for_vsim(args.vsim, instr_mem_file)}}}; "
                f"set expected_regs_file {{{path_for_vsim(args.vsim, expected_regs_file)}}}; "
                f"set trace_file {{{path_for_vsim(args.vsim, trace_file)}}}; "
                f"set boot_addr 0; set max_cycles {max_cycles}; set batch_mode 1; do run_sim.do"
            )
            passed, reason, _elapsed = run_modelsim(
                sim_dir, args.vsim, command_body, log_dir / f"{test_name}.log", pass_marker, fail_markers
            )
        else:
            assert verilator_binary is not None
            plusargs = directed_plusargs(
                test_name,
                testcase_dir,
                instr_mem_file,
                expected_regs_file,
                max_cycles,
                trace_file=trace_file,
            )
            if args.wave:
                wave_dir.mkdir(parents=True, exist_ok=True)
                dump_file = wave_dir / f"{test_name}.{args.dump_format}"
                plusargs.extend(["+dump_wave", f"+dump_file={dump_file.resolve().as_posix()}"])
            passed, reason, _elapsed = run_verilator(
                verilator_binary, plusargs, log_dir / f"{test_name}.log", pass_marker, fail_markers
            )

        print("PASS" if passed else "FAIL")
        if not passed:
            failures += 1
            if args.stop_on_fail:
                break

    print(f"Regression summary ({backend}): {len(selected_tests) - failures} passed, {failures} failed")
    if args.wave and failures == 0:
        print(f"Waveforms: {wave_dir.resolve().as_posix()}")
    return 0 if failures == 0 else 1
