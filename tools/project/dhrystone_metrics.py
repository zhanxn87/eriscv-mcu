#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Structured Dhrystone measurement helpers shared by product-local runners."""

from __future__ import annotations

import csv
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Mapping


CSV_COLUMNS = (
    "timestamp_utc", "product", "backend", "iterations", "isa", "git_revision",
    "git_dirty", "core_lmem_early_load", "core_load_response_bypass",
    "core_bht", "core_ras", "core_upper_32_prefetch", "core_imem_pair_fetch",
    "dhrystone_phase_pad", "compiler_layout_align",
    "text_bytes", "rodata_bytes", "imem_image_bytes", "dmem_image_bytes",
    "raw_mcycle", "cycles_per_iteration", "dmips_per_mhz", "hpm_enabled",
    "hpm_instret", "hpm_branch_taken", "hpm_ifetch_wait", "hpm_data_wait",
    "hpm_load_use_stall", "tb_profile_available", "tb_window_cycles", "tb_retired",
    "tb_cpi", "tb_retired_compressed", "tb_retired_instr32",
    "tb_crossword_instr32_upper_half", "tb_ifetch_wait_cycles", "tb_ifetch_requests",
    "tb_ifetch_latency_avg", "tb_ifetch_latency_max", "tb_ifetch_latency_2plus",
    "tb_imem_dbus_collisions", "tb_imem_service_blocks", "tb_dbus_wait_cycles",
    "tb_load_use_stall_cycles", "tb_redirect_lost_cycles", "tb_branch_predictions",
    "tb_branch_direction_correct", "tb_branch_prediction_corrections",
    "tb_forward_exmem_selected", "tb_forward_memwb_selected", "tb_lmem_accepted",
    "tb_muldiv_wait_cycles", "wall_seconds", "sim_log",
)


def _command_output(command: list[str], cwd: Path) -> str:
    return subprocess.run(
        command, cwd=cwd, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, check=False,
    ).stdout.strip()


def _key_values(line: str) -> dict[str, int]:
    return {key: int(value) for key, value in re.findall(r"([A-Za-z][A-Za-z0-9_]*)=(\d+)", line)}


def _profile_text(log_text: str, label: str) -> str:
    # ``TB PERF PROFILE: enabled`` precedes the aggregate line.  Use the last
    # matching line so the parser always consumes the numeric report.
    matches = re.findall(rf"^TB PERF {re.escape(label)}: (.+)$", log_text, re.MULTILINE)
    return matches[-1] if matches else ""


def _profile_line(log_text: str, label: str) -> dict[str, int]:
    return _key_values(_profile_text(log_text, label))


def _group_value(text: str, group: str, key: str) -> int | str:
    match = re.search(rf"{re.escape(group)}\([^)]*\b{re.escape(key)}=(\d+)", text)
    return int(match.group(1)) if match else ""


def parse_tb_profile(log_text: str) -> dict[str, int]:
    """Parse the stable, aggregate TB PERF display lines into CSV fields."""
    profile = _profile_line(log_text, "PROFILE")
    retire = _profile_line(log_text, "RETIRE")
    stalls_text = _profile_text(log_text, "STALL LEVEL CYCLES")
    stalls = _key_values(stalls_text)
    redirects = _profile_line(log_text, "REDIRECT RECOVERY")
    forwarding = _profile_line(log_text, "FWD")
    lmem = _profile_line(log_text, "LMEM")
    bht = _profile_line(log_text, "BRANCH PREDICTION")
    if not bht:
        bht = _profile_line(log_text, "BTFNT DIRECTION")
    ifetch = _profile_line(log_text, "IFETCH ACCEPTED")
    contention = _profile_line(log_text, "IMEM CONTENTION")
    muldiv = _profile_line(log_text, "MULDIV")
    if not profile or not retire or not ifetch:
        return {}

    retired = retire["total"]
    window_cycles = profile["window_cycles"]
    return {
        "tb_window_cycles": window_cycles,
        "tb_retired": retired,
        "tb_cpi": round(window_cycles / retired, 6) if retired else "",
        "tb_retired_compressed": retire["compressed"],
        "tb_retired_instr32": retire["instr32"],
        "tb_crossword_instr32_upper_half": retire["instr32_upper_half"],
        "tb_ifetch_wait_cycles": stalls.get("ifetch", ""),
        "tb_ifetch_requests": ifetch["req"],
        "tb_ifetch_latency_avg": round(ifetch["total"] / ifetch["req"], 6) if ifetch["req"] else "",
        "tb_ifetch_latency_max": ifetch["max"],
        "tb_ifetch_latency_2plus": ifetch["hist2plus"],
        "tb_imem_dbus_collisions": contention.get("simultaneous_if_dbus_requests", ""),
        "tb_imem_service_blocks": contention.get("blocked_fetch_request_cycles", ""),
        "tb_dbus_wait_cycles": stalls.get("dbus", ""),
        "tb_load_use_stall_cycles": _group_value(stalls_text, "load_use", "total"),
        "tb_redirect_lost_cycles": redirects.get("lost_cycles", ""),
        "tb_branch_predictions": bht.get("predicted", ""),
        "tb_branch_direction_correct": bht.get("correct", ""),
        "tb_branch_prediction_corrections": bht.get("corrections", ""),
        "tb_forward_exmem_selected": forwarding.get("exmem", ""),
        "tb_forward_memwb_selected": forwarding.get("memwb", ""),
        "tb_lmem_accepted": lmem.get("accepted", ""),
        "tb_muldiv_wait_cycles": _group_value(stalls_text, "muldiv", "total"),
    }


def _elf_section_sizes(elf: Path) -> tuple[int | str, int | str, str]:
    output = _command_output(["riscv64-unknown-elf-size", "-A", str(elf)], elf.parent)
    sections: dict[str, int] = {}
    for line in output.splitlines():
        fields = line.split()
        if len(fields) >= 2 and fields[0].startswith(".") and fields[1].isdigit():
            sections[fields[0]] = int(fields[1])
    text_bytes = sum(size for name, size in sections.items() if name.startswith(".text") or name == ".init")
    rodata_bytes = sum(size for name, size in sections.items() if name.startswith(".rodata") or name.startswith(".srodata"))
    attributes = _command_output(["riscv64-unknown-elf-readelf", "-A", str(elf)], elf.parent)
    isa_match = re.search(r"Tag_RISCV_arch:\s*(\S+)", attributes)
    return text_bytes, rodata_bytes, isa_match.group(1) if isa_match else ""


def _configured_isa(sw_dir: Path) -> str:
    match = re.search(r"^ISA\s*\?=\s*(\S+)", (sw_dir / "isa.mk").read_text(encoding="utf-8"), re.MULTILINE)
    return match.group(1) if match else ""


def _mem_image_bytes(path: Path) -> int:
    return sum(1 for line in path.read_text(encoding="utf-8").splitlines() if line.strip()) * 4


def _git_metadata(root: Path) -> tuple[str, int]:
    revision = _command_output(["git", "rev-parse", "--short", "HEAD"], root)
    dirty = bool(_command_output(["git", "status", "--porcelain"], root))
    return revision, int(dirty)


def append_dhrystone_csv(
    *, root: Path, csv_path: Path, product: str, backend: str, iterations: int,
    sw_dir: Path, elf: Path, imem: Path, dmem: Path, raw_mcycle: int, elapsed_seconds: float,
    hpm_enabled: bool, hpm_report: Mapping[int, int], log_path: Path,
    core_lmem_early_load: bool | None = None,
    core_load_response_bypass: bool | None = None,
    core_bht: bool | None = None,
    core_ras: bool | None = None,
    core_upper_32_prefetch: bool | None = None,
    core_imem_pair_fetch: bool | None = None,
    dhrystone_phase_pad: bool | None = None,
    compiler_layout_align: bool | None = None,
) -> dict[str, object]:
    """Append one successful Dhrystone measurement and return its row."""
    text_bytes, rodata_bytes, isa = _elf_section_sizes(elf)
    isa = isa or _configured_isa(sw_dir)
    revision, dirty = _git_metadata(root)
    log_text = log_path.read_text(encoding="utf-8")
    profile = parse_tb_profile(log_text)
    row: dict[str, object] = {column: "" for column in CSV_COLUMNS}
    row.update({
        "timestamp_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "product": product,
        "backend": backend,
        "iterations": iterations,
        "isa": isa,
        "git_revision": revision,
        "git_dirty": dirty,
        "core_lmem_early_load": "" if core_lmem_early_load is None else int(core_lmem_early_load),
        "core_load_response_bypass": "" if core_load_response_bypass is None else int(core_load_response_bypass),
        "core_bht": "" if core_bht is None else int(core_bht),
        "core_ras": "" if core_ras is None else int(core_ras),
        "core_upper_32_prefetch": "" if core_upper_32_prefetch is None else int(core_upper_32_prefetch),
        "core_imem_pair_fetch": "" if core_imem_pair_fetch is None else int(core_imem_pair_fetch),
        "dhrystone_phase_pad": "" if dhrystone_phase_pad is None else int(dhrystone_phase_pad),
        "compiler_layout_align": "" if compiler_layout_align is None else int(compiler_layout_align),
        "text_bytes": text_bytes,
        "rodata_bytes": rodata_bytes,
        "imem_image_bytes": _mem_image_bytes(imem),
        "dmem_image_bytes": _mem_image_bytes(dmem),
        "raw_mcycle": raw_mcycle,
        "cycles_per_iteration": round(raw_mcycle / iterations, 6),
        "dmips_per_mhz": round(iterations * 1_000_000 / raw_mcycle / 1757, 6),
        "hpm_enabled": int(hpm_enabled),
        "hpm_instret": hpm_report.get(3, ""),
        "hpm_branch_taken": hpm_report.get(4, ""),
        "hpm_ifetch_wait": hpm_report.get(5, ""),
        "hpm_data_wait": hpm_report.get(6, ""),
        "hpm_load_use_stall": hpm_report.get(7, ""),
        "tb_profile_available": int(bool(profile)),
        "wall_seconds": round(elapsed_seconds, 3),
        "sim_log": str(log_path.relative_to(root)),
    })
    row.update(profile)
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    write_header = not csv_path.exists() or csv_path.stat().st_size == 0
    # Preserve historical measurements while extending the schema. Existing
    # rows receive empty cells for configuration fields unavailable at capture.
    if not write_header:
        with csv_path.open("r", encoding="utf-8", newline="") as stream:
            reader = csv.DictReader(stream)
            old_columns = tuple(reader.fieldnames or ())
            old_rows = list(reader)
        if old_columns != CSV_COLUMNS:
            with csv_path.open("w", encoding="utf-8", newline="") as stream:
                writer = csv.DictWriter(stream, fieldnames=CSV_COLUMNS,
                                        lineterminator="\n")
                writer.writeheader()
                for old_row in old_rows:
                    writer.writerow({column: old_row.get(column, "") for column in CSV_COLUMNS})
    with csv_path.open("a", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=CSV_COLUMNS,
                                lineterminator="\n")
        if write_header:
            writer.writeheader()
        writer.writerow(row)
    return row
