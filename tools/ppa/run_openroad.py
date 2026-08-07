#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Run a local Sky130/OpenROAD place-and-route timing estimate."""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
RUN_PPA = Path(__file__).with_name("run_ppa.py")
OPENRAM_WRAPPER = Path(__file__).with_name("sram_1rw_openram_16k.sv")
OPENRAM_MACRO_NAME = "eriscv_sram_16kbyte_1rw_32x4096_8"
OPENRAM_MACRO_COUNT = 8
PREBUILT_4K_WRAPPER = Path(__file__).with_name("sram_1rw_prebuilt_4k.sv")
PREBUILT_4K_MACRO_NAME = "sky130_sram_4kbyte_1rw1r_32x1024_8"
PREBUILT_4K_MACRO_COUNT = 32


class OpenRoadError(RuntimeError):
    """The local physical-estimation flow could not complete."""


def quote(value: Path | str) -> str:
    return shlex.quote(str(value))


def tcl_brace(value: Path | str) -> str:
    return "{" + str(value).replace("}", "\\}") + "}"


def run(command: list[str], log: Path) -> str:
    print("+", " ".join(quote(item) for item in command), flush=True)
    completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    log.write_text(completed.stdout, encoding="utf-8")
    if completed.returncode:
        raise OpenRoadError(f"command failed ({completed.returncode}); see {log}")
    if re.search(r"^Error:", completed.stdout, flags=re.MULTILINE):
        raise OpenRoadError(f"tool reported an error; see {log}")
    return completed.stdout


def find_pdk_root(explicit_root: Path | None) -> Path:
    if explicit_root is not None:
        candidates = [explicit_root]
    elif os.environ.get("PPA_SKY130_ROOT"):
        candidates = [Path(os.environ["PPA_SKY130_ROOT"])]
    else:
        ppa_home = Path(os.environ.get("PPA_HOME", REPO_ROOT / ".cache" / "ppa"))
        candidates = sorted((ppa_home / "pdks" / "volare" / "sky130" / "versions").glob("*/sky130A"))
    if len(candidates) != 1 or not candidates[0].is_dir():
        raise OpenRoadError(
            "Sky130 PDK root is ambiguous or missing; set PPA_SKY130_ROOT to the sky130A directory"
        )
    return candidates[0].resolve()


def link_viewer_lefs(output_dir: Path, *lefs: Path) -> None:
    """Expose the PDK LEFs beside the DEF for KLayout's DEF reader."""
    for source in lefs:
        destination = output_dir / source.name
        if destination.is_symlink() and destination.resolve() == source.resolve():
            continue
        if destination.exists() or destination.is_symlink():
            raise OpenRoadError(f"refusing to replace non-PDK viewer file: {destination}")
        destination.symlink_to(source)


def lef_size(lef: Path, macro_name: str) -> tuple[float, float]:
    match = re.search(
        rf"^MACRO\s+{re.escape(macro_name)}\s.*?^\s*SIZE\s+([0-9.eE+-]+)\s+BY\s+([0-9.eE+-]+)\s*;",
        lef.read_text(encoding="utf-8"),
        flags=re.MULTILINE | re.DOTALL,
    )
    if not match:
        raise OpenRoadError(f"macro size not found in LEF: {lef}")
    return float(match.group(1)), float(match.group(2))


def sram_profile(profile: str) -> tuple[str, Path, int, int]:
    if profile == "openram16k":
        return OPENRAM_MACRO_NAME, OPENRAM_WRAPPER, OPENRAM_MACRO_COUNT, 4
    if profile == "prebuilt4k":
        return PREBUILT_4K_MACRO_NAME, PREBUILT_4K_WRAPPER, PREBUILT_4K_MACRO_COUNT, 8
    raise OpenRoadError(f"unsupported SRAM profile: {profile}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--product", choices=("m0", "m1", "m2"), default="m0")
    parser.add_argument("--period-ns", type=float, default=20.0)
    parser.add_argument("--utilization", type=float, default=30.0)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--pdk-root", type=Path, help="Sky130A PDK root (or set PPA_SKY130_ROOT)")
    parser.add_argument("--openroad", default="openroad")
    parser.add_argument(
        "--threads",
        default="max",
        help="OpenROAD thread count (default: max)",
    )
    parser.add_argument("--yosys", default="yosys")
    parser.add_argument("--sta", default="sta")
    parser.add_argument(
        "--route-mode",
        choices=("full", "post-cts"),
        default="full",
        help="full global-route repair, or faster post-CTS placement-RC estimate",
    )
    parser.add_argument(
        "--global-route-iterations",
        type=int,
        default=100,
        help="global-route congestion iterations per pass (default: 100)",
    )
    parser.add_argument(
        "--route-repair",
        choices=("none", "full"),
        default="full",
        help="post-global-route setup/hold repair policy (default: full)",
    )
    parser.add_argument("--sram-macro-dir", type=Path, help="SRAM macro directory for M0 physical PPA")
    parser.add_argument(
        "--macro-channel-um",
        type=float,
        default=20.0,
        help="hard-macro channel and edge clearance in microns (default: 20)",
    )
    parser.add_argument(
        "--sram-profile",
        choices=("openram16k", "prebuilt4k"),
        default="openram16k",
        help="hard-SRAM organization (default: openram16k)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if (
        args.period_ns <= 0
        or not 0 < args.utilization < 100
        or args.global_route_iterations <= 0
        or args.macro_channel_um <= 0
    ):
        raise SystemExit(
            "--period-ns, --global-route-iterations, and --macro-channel-um must be positive and --utilization must be between 0 and 100"
        )
    if shutil.which(args.openroad) is None:
        raise SystemExit("OpenROAD not found in PATH; source tools/ppa/env.sh first")
    try:
        pdk_root = find_pdk_root(args.pdk_root)
        lib_root = pdk_root / "libs.ref" / "sky130_fd_sc_hd"
        liberty = lib_root / "lib" / "sky130_fd_sc_hd__tt_025C_1v80.lib"
        tech_lef = lib_root / "techlef" / "sky130_fd_sc_hd__nom.tlef"
        cell_lef = lib_root / "lef" / "sky130_fd_sc_hd.lef"
        blackbox = lib_root / "verilog" / "sky130_fd_sc_hd__blackbox.v"
        for required in (liberty, tech_lef, cell_lef, blackbox):
            if not required.is_file():
                raise OpenRoadError(f"missing Sky130 PDK file: {required}")

        sram_views: dict[str, Path] | None = None
        macro_name, macro_wrapper, macro_count, macro_cols = sram_profile(args.sram_profile)
        if args.sram_macro_dir is not None:
            if args.product != "m0":
                raise OpenRoadError("OpenRAM SRAM integration is currently defined only for M0")
            macro_dir = args.sram_macro_dir.resolve()
            sram_views = {
                suffix: macro_dir / f"{macro_name}.{suffix}"
                for suffix in ("gds", "lef", "sp", "v")
            }
            sram_views["lib"] = macro_dir / (
                f"{macro_name}.lib"
                if args.sram_profile == "openram16k"
                else f"{macro_name}_TT_1p8V_25C.lib"
            )
            missing_views = [str(path) for path in sram_views.values() if not path.is_file()]
            if missing_views:
                raise OpenRoadError("OpenRAM macro views missing: " + ", ".join(missing_views))
            if not macro_wrapper.is_file():
                raise OpenRoadError(f"missing SRAM wrapper: {macro_wrapper}")
            macro_width, macro_height = lef_size(sram_views["lef"], macro_name)
        output_dir = args.output_dir.resolve()
        output_dir.mkdir(parents=True, exist_ok=True)
        link_viewer_lefs(output_dir, tech_lef, cell_lef, *( [sram_views["lef"]] if sram_views else [] ))
        # A failed run must not leave a prior target's successful summary behind.
        (output_dir / "summary.json").unlink(missing_ok=True)
        prep_dir = output_dir / "synthesis"
        ppa_command = [
                sys.executable,
                str(RUN_PPA),
                "--product",
                args.product,
                "--period-ns",
                str(args.period_ns),
                "--liberty",
                str(liberty),
                "--input-driver-cell",
                "sky130_fd_sc_hd__buf_1",
                "--input-driver-pin",
                "X",
                "--clock-gate-model",
                "sky130",
                "--clock-gate-blackbox",
                str(blackbox),
                "--output-dir",
                str(prep_dir),
                "--yosys",
                args.yosys,
                "--sta",
                args.sta,
            ]
        if sram_views is not None:
            ppa_command.extend(
                [
                    "--sram-wrapper",
                    str(macro_wrapper),
                    "--sram-liberty",
                    str(sram_views["lib"]),
                ]
            )
        run(
            ppa_command,
            output_dir / "synthesis.log",
        )

        netlist = prep_dir / "soc_mapped.v"
        constraints = prep_dir / "constraints.sdc"
        tcl = output_dir / "run_openroad.tcl"
        macro_tcl: list[str] = []
        floorplan_arguments = f"-utilization {args.utilization:g} -core_space 20 -site unithd"
        if sram_views is not None:
            # M0 has separate 64 KiB IMEM and DMEM instances.  Place their
            # banks on opposite sides so standard-cell logic retains a
            # continuous central placement region.
            macro_channel = args.macro_channel_um
            macro_tcl = [
                f"read_lef {tcl_brace(sram_views['lef'])}",
                f"read_liberty {tcl_brace(sram_views['lib'])}",
                "# Deterministic hard-macro placement before standard-cell placement.",
                "set macro_instances {}",
                "set db_block [ord::get_db_block]",
                "foreach inst [$db_block getInsts] {",
                f"  if {{[[$inst getMaster] getName] eq {{{macro_name}}}}} {{",
                "    lappend macro_instances [list [$inst getName] $inst]",
                "  }",
                "}",
                f"if {{[llength $macro_instances] != {macro_count}}} {{",
                f"  error \"expected {macro_count} {macro_name} instances, got [llength $macro_instances]\"",
                "}",
                "set macro_instances [lsort -index 0 $macro_instances]",
                "lassign [ord::get_core_area] core_lx core_ly core_ux core_uy",
                f"set macro_width {macro_width:.8g}",
                f"set macro_height {macro_height:.8g}",
                f"set macro_channel {macro_channel:.8g}",
                "set macro_index 0",
            ]
            if args.sram_profile == "prebuilt4k":
                macros_per_memory = macro_count // 2
                stack_columns = 2
                stack_rows = macros_per_memory // stack_columns
                stack_width = stack_columns * macro_width + (stack_columns - 1) * macro_channel
                stack_height = stack_rows * macro_height + (stack_rows - 1) * macro_channel
                floorplan_arguments = (
                    f"-utilization {args.utilization:g} -aspect_ratio 1.0 -core_space 20 -site unithd"
                )
                macro_tcl.extend(
                    [
                        f"set macro_stack_width {stack_width:.8g}",
                        f"set macro_stack_height {stack_height:.8g}",
                        "set macro_origin_y [expr {$core_ly + (($core_uy - $core_ly) - $macro_stack_height) / 2.0}]",
                        "set macro_index 0",
                        "foreach macro_entry $macro_instances {",
                        "  lassign $macro_entry macro_name macro",
                        f"  set macro_group [expr {{$macro_index / {macros_per_memory}}}]",
                        f"  set macro_local_index [expr {{$macro_index % {macros_per_memory}}}]",
                        f"  set macro_col [expr {{$macro_local_index % {stack_columns}}}]",
                        f"  set macro_row [expr {{$macro_local_index / {stack_columns}}}]",
                        "  if {$macro_group == 0} {",
                        "    set macro_stack_x [expr {$core_lx + $macro_channel}]",
                        "    set macro_orient MY",
                        "  } else {",
                        "    set macro_stack_x [expr {$core_ux - $macro_channel - $macro_stack_width}]",
                        "    set macro_orient R0",
                        "  }",
                        "  set macro_x [expr {$macro_stack_x + $macro_col * ($macro_width + $macro_channel)}]",
                        "  if {$macro_orient eq {MY}} {",
                        "    set macro_x [expr {$macro_x + $macro_width}]",
                        "  }",
                        "  set macro_y [expr {$macro_origin_y + $macro_row * ($macro_height + $macro_channel)}]",
                        "  $macro setLocation [ord::microns_to_dbu $macro_x] [ord::microns_to_dbu $macro_y]",
                        "  $macro setOrient $macro_orient",
                        "  $macro setPlacementStatus FIRM",
                        "  incr macro_index",
                        "}",
                        "cut_rows -halo_width_x 20 -halo_width_y 20",
                    ]
                )
            else:
                macro_rows = macro_count // macro_cols
                grid_width = macro_cols * macro_width + (macro_cols - 1) * macro_channel
                grid_height = macro_rows * macro_height + (macro_rows - 1) * macro_channel
                floorplan_arguments = (
                    f"-utilization {args.utilization:g} -aspect_ratio {grid_height / grid_width:.8g} -core_space 20 -site unithd"
                )
                macro_tcl.extend(
                    [
                        f"set macro_grid_width {grid_width:.8g}",
                        f"set macro_grid_height {grid_height:.8g}",
                        "set macro_origin_x [expr {$core_lx + (($core_ux - $core_lx) - $macro_grid_width) / 2.0}]",
                        "set macro_origin_y [expr {$core_ly + (($core_uy - $core_ly) - $macro_grid_height) / 2.0}]",
                        "foreach macro_entry $macro_instances {",
                        "  lassign $macro_entry macro_name macro",
                        f"  set macro_col [expr {{$macro_index % {macro_cols}}}]",
                        f"  set macro_row [expr {{$macro_index / {macro_cols}}}]",
                        "  set macro_x [expr {$macro_origin_x + $macro_col * ($macro_width + $macro_channel)}]",
                        "  set macro_y [expr {$macro_origin_y + $macro_row * ($macro_height + $macro_channel)}]",
                        "  $macro setLocation [ord::microns_to_dbu $macro_x] [ord::microns_to_dbu $macro_y]",
                        "  $macro setOrient R0",
                        "  $macro setPlacementStatus FIRM",
                        "  incr macro_index",
                        "}",
                        "cut_rows -halo_width_x 20 -halo_width_y 20",
                    ]
                )
        if args.route_mode == "full":
            route_tcl = [
                f"global_route -congestion_iterations {args.global_route_iterations}",
                "estimate_parasitics -global_routing",
            ]
            if args.route_repair == "full":
                route_tcl.extend(
                    [
                        "puts OR_PRE_REPAIR_SETUP_BEGIN",
                        "report_checks -path_delay max -group_path_count 1 -digits 4",
                        "puts OR_PRE_REPAIR_SETUP_END",
                        "puts OR_PRE_REPAIR_AREA_BEGIN",
                        "report_design_area",
                        "puts OR_PRE_REPAIR_AREA_END",
                        "repair_timing -setup -max_utilization 65",
                        "detailed_placement",
                        f"global_route -congestion_iterations {args.global_route_iterations}",
                        "estimate_parasitics -global_routing",
                        "repair_timing -hold -max_utilization 65",
                        "detailed_placement",
                        f"global_route -congestion_iterations {args.global_route_iterations}",
                        "estimate_parasitics -global_routing",
                    ]
                )
                route_scope = "global-routing RC, post-CTS setup/hold repair, and detailed routing"
            else:
                route_scope = "global-routing RC and detailed routing without post-route timing repair"
            route_tcl.extend(
                [
                    f"detailed_route -output_drc {tcl_brace(output_dir / 'detailed_route_drc.rpt')}",
                    "estimate_parasitics -global_routing",
                ]
            )
            output_netlist = "soc_postroute.v"
        else:
            route_tcl = ["estimate_parasitics -placement"]
            route_scope = "post-CTS placement-based RC estimation"
            output_netlist = "soc_postcts.v"
        placement_command = (
            "global_placement -density 0.50 -timing_driven"
            if args.route_mode == "full"
            else "global_placement -density 0.50"
        )

        tcl.write_text(
            "\n".join(
                [
                    "# Generated by tools/ppa/run_openroad.py.",
                    f"read_lef {tcl_brace(tech_lef)}",
                    f"read_lef {tcl_brace(cell_lef)}",
                    f"read_liberty {tcl_brace(liberty)}",
                    *macro_tcl[:2],
                    f"read_verilog {tcl_brace(netlist)}",
                    "link_design soc",
                    "# OpenROAD classifies conb_1 outputs as POWER/GROUND from their",
                    "# constant Liberty functions.  They have physical tie-cell drivers,",
                    "# so make the output nets ordinary signals for detailed routing.",
                    "set db_block [ord::get_db_block]",
                    "foreach inst [$db_block getInsts] {",
                    "  if {[[$inst getMaster] getName] ne {sky130_fd_sc_hd__conb_1}} { continue }",
                    "  foreach iterm [$inst getITerms] {",
                    "    set mterm_name [[$iterm getMTerm] getName]",
                    "    if {$mterm_name ni {HI LO}} { continue }",
                    "    set tie_net [$iterm getNet]",
                    "    if {$tie_net ne {NULL}} { $tie_net setSigType SIGNAL }",
                    "  }",
                    "}",
                    "# read_verilog may retain empty one_/zero_ placeholders after hilomap.",
                    "# They have no pins; keep them out of the special-net router path.",
                    "foreach placeholder_name {one_ zero_} {",
                    "  set placeholder_net [$db_block findNet $placeholder_name]",
                    "  if {$placeholder_net eq {NULL}} { continue }",
                    "  if {[llength [$placeholder_net getITerms]] == 0 && [llength [$placeholder_net getBTerms]] == 0} {",
                    "    $placeholder_net setSigType SIGNAL",
                    "  }",
                    "}",
                    f"source {tcl_brace(constraints)}",
                    f"initialize_floorplan {floorplan_arguments}",
                    *macro_tcl[2:],
                    "make_tracks li1 -x_offset 0.23 -x_pitch 0.46 -y_offset 0.17 -y_pitch 0.34",
                    "make_tracks met1 -x_offset 0.17 -x_pitch 0.34 -y_offset 0.17 -y_pitch 0.34",
                    "make_tracks met2 -x_offset 0.23 -x_pitch 0.46 -y_offset 0.23 -y_pitch 0.46",
                    "make_tracks met3 -x_offset 0.34 -x_pitch 0.68 -y_offset 0.34 -y_pitch 0.68",
                    "make_tracks met4 -x_offset 0.46 -x_pitch 0.92 -y_offset 0.46 -y_pitch 0.92",
                    "make_tracks met5 -x_offset 1.70 -x_pitch 3.40 -y_offset 1.70 -y_pitch 3.40",
                    "set_routing_layers -signal met1-met5 -clock met3-met5",
                    "set_wire_rc -signal -layer met2",
                    "set_wire_rc -clock -layer met5",
                    "place_pins -hor_layers met3 -ver_layers met2 -annealing",
                    placement_command,
                    "estimate_parasitics -placement",
                    "repair_design -max_utilization 65",
                    "detailed_placement",
                    "clock_tree_synthesis -root_buf sky130_fd_sc_hd__clkbuf_16 -buf_list {sky130_fd_sc_hd__clkbuf_8 sky130_fd_sc_hd__clkbuf_4 sky130_fd_sc_hd__clkbuf_2} -repair_clock_nets",
                    "# CTS inserts clock buffers/inverters; legalize them before routing.",
                    "detailed_placement",
                    "set_propagated_clock [all_clocks]",
                    "puts OR_POST_CTS_AREA_BEGIN",
                    "report_design_area",
                    "puts OR_POST_CTS_AREA_END",
                    *route_tcl,
                    "puts OR_AREA_BEGIN",
                    "report_design_area",
                    "puts OR_AREA_END",
                    "puts OR_SETUP_BEGIN",
                    "report_checks -path_delay max -group_path_count 1 -digits 4",
                    "report_worst_slack -max",
                    "report_tns -max",
                    "puts OR_SETUP_END",
                    "puts OR_HOLD_BEGIN",
                    "report_checks -path_delay min -group_path_count 1 -digits 4",
                    "report_worst_slack -min",
                    "report_tns -min",
                    "puts OR_HOLD_END",
                    f"write_def {tcl_brace(output_dir / 'soc.def')}",
                    f"write_verilog {tcl_brace(output_dir / output_netlist)}",
                    "exit",
                    "",
                ]
            ),
            encoding="utf-8",
        )
        log = run(
            [args.openroad, "-no_init", "-threads", args.threads, "-exit", str(tcl)],
            output_dir / "openroad.log",
        )
    except OpenRoadError as exc:
        print(f"OpenROAD PPA FAIL: {exc}", file=sys.stderr)
        return 1

    setup_wns = _marked_number("OR_SETUP", r"worst slack max\s+(-?[0-9.eE+-]+)", log)
    hold_wns = _marked_number("OR_HOLD", r"worst slack min\s+(-?[0-9.eE+-]+)", log)
    area_um2 = _marked_number("OR_AREA", r"Design area\s+([0-9.eE+-]+)", log)
    critical_path_ns = args.period_ns - setup_wns if setup_wns is not None else None
    summary = {
        "product": args.product,
        "top": "soc",
        "clock_period_ns": args.period_ns,
        "initial_core_utilization_pct": args.utilization,
        "route_mode": args.route_mode,
        "global_route_iterations": args.global_route_iterations if args.route_mode == "full" else None,
        "route_repair": args.route_repair if args.route_mode == "full" else None,
        "macro_channel_um": args.macro_channel_um if sram_views is not None else None,
        "pdk_root": str(pdk_root),
        "liberty": str(liberty),
        "setup_wns_ns": setup_wns,
        "hold_wns_ns": hold_wns,
        "critical_path_ns": critical_path_ns,
        "fmax_mhz": 1000.0 / critical_path_ns if critical_path_ns and critical_path_ns > 0 else None,
        "area_um2": area_um2,
        "clock_gate_model": "sky130_fd_sc_hd__dlclkp_2",
        "memory_model": (
            "sram_1rw blackbox; SRAM macro area, timing, LEF, and routing excluded"
            if sram_views is None
            else f"{macro_count} placed {macro_name} hard macros; Liberty and LEF included"
        ),
        "sram_macro_dir": str(args.sram_macro_dir.resolve()) if args.sram_macro_dir else None,
        "implementation_scope": (
            f"Sky130 standard-cell logic with floorplan, global placement, high-fanout repair, CTS, and {route_scope}. No SRAM macro, PDN, extracted SPEF, IR/EM, or signoff checks"
            if sram_views is None
            else f"Sky130 standard-cell logic and placed SRAM macros with floorplan, global placement, high-fanout repair, CTS, and {route_scope}. Macro PDN, extracted SPEF, IR/EM, and signoff checks are excluded"
        ),
    }
    (output_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


def _marked_number(marker: str, pattern: str, text: str) -> float | None:
    block = re.search(rf"{marker}_BEGIN(?P<body>[\s\S]*?){marker}_END", text)
    if not block:
        return None
    match = re.search(pattern, block.group("body"), flags=re.IGNORECASE | re.MULTILINE)
    return float(match.group(1)) if match else None


if __name__ == "__main__":
    raise SystemExit(main())
