#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Run logic-only Yosys/OpenSTA PPA evaluation for one eRISCV MCU SoC."""

from __future__ import annotations

import argparse
import json
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "project"))
from resolve_filelist import FileListEntry, resolve_filelist  # noqa: E402


BLACKBOX = Path(__file__).with_name("sram_1rw_blackbox.sv")
CONSTRAINTS = Path(__file__).with_name("constraints.sdc")
PATH_GROUPS = ("sys_clk", "core_clk", "peri_clk_0", "peri_clk_1", "peri_clk_2", "peri_clk_3", "peri_clk_4")
REQUIRED_CLOCKS = (*PATH_GROUPS, "jtag_clk")


class PpaError(RuntimeError):
    """A synthesis or timing step could not complete."""


def quote(value: Path | str) -> str:
    return shlex.quote(str(value))


def source_arguments(
    entries: list[FileListEntry],
    *,
    clock_gate_model: str,
    clock_gate_blackbox: Path | None,
) -> list[str]:
    arguments = ["--top", "soc", "-D", "SYNTHESIS"]
    if clock_gate_model == "generic":
        arguments.extend(["-D", "ERISCV_PPA_GENERIC"])
    else:
        arguments.extend(["-D", "ERISCV_ASIC"])
    for entry in entries:
        if entry.kind == "incdir":
            arguments.extend(["-I", str(entry.value)])
        elif entry.kind == "source":
            source = Path(entry.value)
            if source.name != "sram_1rw.sv":
                arguments.append(str(source))
        elif str(entry.value).startswith("+define+"):
            for define in str(entry.value).removeprefix("+define+").split("+"):
                if define:
                    arguments.extend(["-D", define])
        else:
            raise PpaError(f"unsupported filelist option for Yosys: {entry.value}")
    arguments.append(str(BLACKBOX))
    if clock_gate_blackbox is not None:
        arguments.append(str(clock_gate_blackbox))
    return arguments


def run(command: list[str], log: Path, *, stream_output: bool = False) -> str:
    print("+", " ".join(quote(item) for item in command), flush=True)
    if stream_output:
        with log.open("w", encoding="utf-8") as log_file:
            completed = subprocess.run(command, text=True, stdout=log_file, stderr=subprocess.STDOUT)
        output = log.read_text(encoding="utf-8")
    else:
        completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        output = completed.stdout
        log.write_text(output, encoding="utf-8")
    if completed.returncode:
        raise PpaError(f"command failed ({completed.returncode}); see {log}")
    if re.search(r"^Error:", output, flags=re.MULTILINE):
        raise PpaError(f"tool reported an error; see {log}")
    return output


def find_number(pattern: str, text: str) -> float | None:
    match = re.search(pattern, text, flags=re.IGNORECASE | re.MULTILINE)
    return float(match.group(1)) if match else None


def marked_number(marker: str, text: str, group: str = "sys_clk") -> float | None:
    block = re.search(
        rf"{re.escape(marker)}_BEGIN(?P<body>[\s\S]*?){re.escape(marker)}_END",
        text,
        flags=re.IGNORECASE,
    )
    return find_number(rf"^{re.escape(group)}\s+(-?[0-9.eE+-]+)", block.group("body")) if block else None


def marked_clock_names(marker: str, text: str) -> set[str]:
    block = re.search(
        rf"{re.escape(marker)}_BEGIN(?P<body>[\s\S]*?){re.escape(marker)}_END",
        text,
        flags=re.IGNORECASE,
    )
    if not block:
        return set()
    return set(re.findall(r"^\s*(\S+)\s+[0-9]+(?:\.[0-9]+)?\s", block.group("body"), flags=re.MULTILINE))


def tcl_brace(value: Path | str) -> str:
    """Quote a simple Tcl word without treating spaces as separators."""

    return "{" + str(value).replace("}", "\\}") + "}"


def render_constraints(args: argparse.Namespace, output_dir: Path) -> Path:
    """Materialize the checked-in SDC with run-specific assumptions."""

    if not CONSTRAINTS.is_file():
        raise PpaError(f"missing PPA constraints file: {CONSTRAINTS}")
    assignments = [
        f"set ERISCV_PPA_SYS_CLK_PERIOD_NS {args.period_ns:g}",
        f"set ERISCV_PPA_JTAG_CLK_PERIOD_NS {args.jtag_period_ns:g}",
        f"set ERISCV_PPA_CLOCK_GATE_MODEL {tcl_brace(args.clock_gate_model)}",
    ]
    optional_values = {
        "ERISCV_PPA_IO_DELAY_NS": args.io_delay_ns,
        "ERISCV_PPA_CLOCK_UNCERTAINTY_NS": args.clock_uncertainty_ns,
        "ERISCV_PPA_INPUT_TRANSITION_NS": args.input_transition_ns,
        "ERISCV_PPA_OUTPUT_LOAD_PF": args.output_load_pf,
        "ERISCV_PPA_MAX_FANOUT": args.max_fanout,
        "ERISCV_PPA_MAX_TRANSITION_NS": args.max_transition_ns,
    }
    for name, value in optional_values.items():
        if value is not None:
            assignments.append(f"set {name} {value:g}")
    assignments.extend(
        [
            f"set ERISCV_PPA_INPUT_DRIVER_CELL {tcl_brace(args.input_driver_cell)}",
            f"set ERISCV_PPA_INPUT_DRIVER_PIN {tcl_brace(args.input_driver_pin)}",
        ]
    )
    constraints_path = output_dir / "constraints.sdc"
    constraints_path.write_text(
        "# Generated by tools/ppa/run_ppa.py; source template: tools/ppa/constraints.sdc\n"
        + "\n".join(assignments)
        + "\n\n"
        + CONSTRAINTS.read_text(encoding="utf-8"),
        encoding="utf-8",
    )
    return constraints_path


def sta_preamble(args: argparse.Namespace, netlist: Path, constraints: Path) -> list[str]:
    return [
        f"read_liberty {tcl_brace(args.liberty.resolve())}",
        f"read_verilog {tcl_brace(netlist)}",
        "link_design soc",
        f"source {tcl_brace(constraints)}",
    ]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--product", choices=("m0", "m1", "m2"), required=True)
    parser.add_argument("--liberty", type=Path, required=True, help="standard-cell Liberty timing/area model")
    parser.add_argument("--period-ns", type=float, default=10.0, help="clock period in ns (default: 10.0)")
    parser.add_argument("--jtag-period-ns", type=float, default=100.0, help="JTAG clock period in ns (default: 100.0)")
    parser.add_argument("--io-delay-ns", type=float, help="external input/output delay in ns (default: 20%% of sys clock)")
    parser.add_argument("--clock-uncertainty-ns", type=float, help="clock uncertainty in ns (default: 5%% of sys clock)")
    parser.add_argument("--input-transition-ns", type=float, help="external input transition in ns (default: 0.15)")
    parser.add_argument("--output-load-pf", type=float, help="external output load in pF (default: 0.02)")
    parser.add_argument("--max-fanout", type=float, help="maximum fanout constraint (default: 16)")
    parser.add_argument("--max-transition-ns", type=float, help="maximum transition in ns (default: 1.0)")
    parser.add_argument("--input-driver-cell", default="BUF_X1", help="Liberty input driver cell (default: BUF_X1)")
    parser.add_argument("--input-driver-pin", default="Z", help="Liberty input driver output pin (default: Z)")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument(
        "--clock-gate-model",
        choices=("generic", "sky130"),
        default="generic",
        help="clock-gate implementation (default: generic)",
    )
    parser.add_argument(
        "--clock-gate-blackbox",
        type=Path,
        help="cell declarations required by --clock-gate-model sky130",
    )
    parser.add_argument("--yosys", default="yosys")
    parser.add_argument("--sta", default="sta")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.period_ns <= 0 or args.jtag_period_ns <= 0:
        raise SystemExit("--period-ns and --jtag-period-ns must be positive")
    for name in (
        "io_delay_ns",
        "clock_uncertainty_ns",
        "input_transition_ns",
        "output_load_pf",
        "max_fanout",
        "max_transition_ns",
    ):
        value = getattr(args, name)
        if value is not None and value < 0:
            raise SystemExit(f"--{name.replace('_', '-')} must not be negative")
    if not args.liberty.is_file():
        raise SystemExit(f"Liberty file not found: {args.liberty}")
    if args.clock_gate_model == "sky130":
        if args.clock_gate_blackbox is None or not args.clock_gate_blackbox.is_file():
            raise SystemExit("--clock-gate-model sky130 requires --clock-gate-blackbox <file>")
    for executable in (args.yosys, args.sta):
        if shutil.which(executable) is None:
            raise SystemExit(f"required executable not found in PATH: {executable}")

    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    constraints = render_constraints(args, output_dir)
    entries = resolve_filelist(REPO_ROOT / f"eriscv-{args.product}" / "rtl/soc/filelist.f")
    netlist = output_dir / "soc_mapped.v"
    synthesis_report = output_dir / "synthesis.rpt"
    yosys_script = output_dir / "run.ys"
    yosys_script.write_text(
        "\n".join(
            [
                "read_slang "
                + " ".join(
                    quote(item)
                    for item in source_arguments(
                        entries,
                        clock_gate_model=args.clock_gate_model,
                        clock_gate_blackbox=args.clock_gate_blackbox,
                    )
                ),
                "hierarchy -check -top soc",
                "proc",
                "flatten",
                "opt",
                "fsm",
                "opt",
                "memory",
                "opt",
                "delete t:sram_1rw",
                "techmap",
                "opt",
                f"dfflibmap -liberty {quote(args.liberty.resolve())}",
                f"abc -liberty {quote(args.liberty.resolve())}",
                "clean",
                f"tee -o {quote(synthesis_report)} stat -liberty {quote(args.liberty.resolve())}",
                f"write_verilog -noattr -noexpr -nodec {quote(netlist)}",
                "",
            ]
        ),
        encoding="utf-8",
    )
    try:
        yosys_log = run([args.yosys, "-m", "slang", "-s", str(yosys_script)], output_dir / "yosys.log")
        sta_base = sta_preamble(args, netlist, constraints)
        raw_sta_script = output_dir / "run_sta_timing.tcl"
        raw_commands = [*sta_base, "puts CLOCK_PROPERTIES_BEGIN", "report_clock_properties [all_clocks]", "puts CLOCK_PROPERTIES_END", "puts TIMING_GROUPS_BEGIN"]
        for group in PATH_GROUPS:
            raw_commands.extend(
                [
                    f"puts TIMING_GROUP_{group}_BEGIN",
                    f"report_checks -path_group {group} -path_delay max -group_path_count 1 -digits 4",
                    f"puts TIMING_GROUP_{group}_END",
                ]
            )
        raw_commands.extend(["puts TIMING_GROUPS_END", "report_worst_slack -max", "report_tns -max", ""])
        raw_sta_script.write_text(
            "\n".join(raw_commands),
            encoding="utf-8",
        )
        raw_sta_log = run(
            [args.sta, "-no_splash", "-exit", "-threads", "max", str(raw_sta_script)],
            output_dir / "opensta_timing.log",
            stream_output=True,
        )
        data_sta_script = output_dir / "run_sta_data_paths.tcl"
        data_commands = [*sta_base, "puts DATA_PATH_WNS_BEGIN"]
        for group in PATH_GROUPS:
            marker = re.sub(r"[^A-Za-z0-9_]", "_", group)
            data_commands.extend(
                [
                    f"puts DATA_PATH_WNS_{marker}_BEGIN",
                    f"report_checks -path_group {group} -path_delay max -group_path_count 1 -format slack_only",
                    f"puts DATA_PATH_WNS_{marker}_END",
                ]
            )
        data_commands.extend(
            [
                "puts DATA_PATH_WNS_END",
                "report_checks -path_delay max -group_path_count 1 -digits 4",
                "",
            ]
        )
        data_sta_script.write_text(
            "\n".join(data_commands),
            encoding="utf-8",
        )
        data_sta_log = run(
            [args.sta, "-no_splash", "-exit", "-threads", "max", str(data_sta_script)],
            output_dir / "opensta_data_paths.log",
            stream_output=True,
        )
        reset_sta_script = output_dir / "run_sta_reset_paths.tcl"
        reset_sta_script.write_text(
            "\n".join(
                [
                    *sta_base,
                    "puts RESET_RECOVERY_WNS_BEGIN",
                    "report_checks -to [all_registers -async_pins] -path_delay max -group_path_count 1 -format slack_only",
                    "puts RESET_RECOVERY_WNS_END",
                    "puts RESET_REMOVAL_WNS_BEGIN",
                    "report_checks -to [all_registers -async_pins] -path_delay min -group_path_count 1 -format slack_only",
                    "puts RESET_REMOVAL_WNS_END",
                    "report_checks -to [all_registers -async_pins] -path_delay max -group_path_count 1 -digits 4",
                    "report_checks -to [all_registers -async_pins] -path_delay min -group_path_count 1 -digits 4",
                    "",
                ]
            ),
            encoding="utf-8",
        )
        reset_sta_log = run(
            [args.sta, "-no_splash", "-exit", "-threads", "max", str(reset_sta_script)],
            output_dir / "opensta_reset_paths.log",
            stream_output=True,
        )
    except PpaError as exc:
        print(f"PPA FAIL: {exc}", file=sys.stderr)
        return 1

    clock_names = marked_clock_names("CLOCK_PROPERTIES", raw_sta_log)
    missing_clocks = sorted(set(REQUIRED_CLOCKS) - clock_names)
    if missing_clocks:
        print(f"PPA FAIL: missing required clock constraints: {', '.join(missing_clocks)}", file=sys.stderr)
        return 1

    path_group_wns_ns: dict[str, float] = {}
    for group in PATH_GROUPS:
        marker = re.sub(r"[^A-Za-z0-9_]", "_", group)
        value = marked_number(f"DATA_PATH_WNS_{marker}", data_sta_log, group)
        if value is not None:
            path_group_wns_ns[group] = value
    missing_path_groups = [group for group in PATH_GROUPS if group not in path_group_wns_ns]
    if missing_path_groups:
        print(
            "PPA FAIL: missing synchronous timing report for " + ", ".join(missing_path_groups),
            file=sys.stderr,
        )
        return 1
    synchronous_path_wns_ns = min(path_group_wns_ns.values()) if path_group_wns_ns else None
    reset_recovery_wns_ns = marked_number("RESET_RECOVERY_WNS", reset_sta_log, "asynchronous")
    reset_removal_wns_ns = marked_number("RESET_REMOVAL_WNS", reset_sta_log, "asynchronous")
    critical_path_ns = (
        args.period_ns - synchronous_path_wns_ns
        if synchronous_path_wns_ns is not None
        else None
    )
    summary = {
        "product": args.product,
        "top": "soc",
        "clock_period_ns": args.period_ns,
        "liberty": str(args.liberty.resolve()),
        "constraints": str(constraints),
        "clock_names": sorted(clock_names),
        "area_um2": find_number(r"Chip area for module '\\?soc':\s*([0-9.eE+-]+)", yosys_log),
        "path_group_wns_ns": path_group_wns_ns,
        "synchronous_path_wns_ns": synchronous_path_wns_ns,
        "reset_recovery_wns_ns": reset_recovery_wns_ns,
        "reset_removal_wns_ns": reset_removal_wns_ns,
        "critical_path_ns": critical_path_ns,
        "fmax_mhz": 1000.0 / critical_path_ns if critical_path_ns and critical_path_ns > 0 else None,
        "all_path_wns_ns": find_number(r"^worst slack max\s+(-?[0-9.eE+-]+)", raw_sta_log),
        "all_path_tns_ns": find_number(r"^tns max\s+(-?[0-9.eE+-]+)", raw_sta_log),
        "memory_model": "sram_1rw blackbox; SRAM macro area and timing excluded",
        "clock_gate_model": args.clock_gate_model,
        "implementation_scope": "logic-only Yosys mapping plus ideal-clock STA; no PDK LEF/RC, placement, reset/data fanout repair, CTS, routing, or SPEF",
        "timing_scope": "fmax uses synchronous_path_wns across sys_clk, core_clk, and peripheral gated-clock groups; all_path_wns also includes async reset checks; reset recovery/removal are reported separately",
    }
    (output_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
