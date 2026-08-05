#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Check the deliberate local-testbench contract between eRISCV-M0 and M1.

The products keep independent DV trees: this checker prevents unintentional
drift without making either product import the other's files at simulation time.
"""

from __future__ import annotations

import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PRODUCTS = {
    "M0": ROOT / "eriscv-m0",
    "M1": ROOT / "eriscv-m1",
}

COMMON_CORE_CASES = (
    "MCU-C-IFETCH-CROSSWORD-01",
    "MCU-LOAD-RESP-BYPASS-01",
    "MCU-BTFNT-ID-01",
    "MCU-BTFNT-C-01",
    "MCU-RAS-01",
)
COMMON_SOC_CASES = (
    "UART-ECHO-01",
    "MCU-BOOT-DATA-INIT-JTAG-ELF-01",
    "MCU-LMEM-LOAD-BRANCH-01",
    "MCU-LMEM-LOAD-STORE-DATA-01",
    "MCU-LOAD-RESPONSE-BYPASS-01",
)
COMMON_PROFILE_MARKERS = (
    "TB PERF IDEX EMPTY:",
    "TB PERF RAS MODEL:",
    "TB PERF FWD:",
    "TB PERF BRANCH PREDICTION:",
    "TB PERF RAS HW:",
    "TB PERF LOAD BYPASS:",
)


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        raise AssertionError(f"missing required file: {path.relative_to(ROOT)}") from None


def require_contains(path: Path, token: str) -> None:
    if token not in read(path):
        raise AssertionError(f"{path.relative_to(ROOT)}: missing contract token {token!r}")


def require_case(product: str, runner: Path, case: str) -> None:
    require_contains(runner, f'"{case}"')
    if case == "MCU-C-IFETCH-CROSSWORD-01":
        case_dir = PRODUCTS[product] / "dv/core/tests/C"
    elif case in {"MCU-LOAD-RESP-BYPASS-01"}:
        case_dir = PRODUCTS[product] / "dv/core/tests/LDST"
    elif case == "MCU-RAS-01":
        case_dir = PRODUCTS[product] / "dv/core/tests/RAS"
    else:
        return
    for suffix in (".S", ".expected_regs"):
        artifact = case_dir / f"{case}{suffix}"
        if not artifact.exists():
            raise AssertionError(f"{product}: missing local testcase source/oracle {artifact.relative_to(ROOT)}")


def require_boot_image_contract(product: str) -> None:
    """Keep UART word images relative while JTAG ELF images remain absolute."""
    case_dir = PRODUCTS[product] / "dv/soc/tests"
    elf = case_dir / "MCU-BOOT-DATA-INIT-01.elf"
    mem = case_dir / "MCU-BOOT-DATA-INIT-01.mem"
    image = elf.read_bytes()
    if image[:4] != b"\x7fELF" or image[4] != 1 or image[5] != 1:
        raise AssertionError(f"{elf.relative_to(ROOT)}: expected ELF32 little-endian image")
    entry = struct.unpack_from("<I", image, 0x18)[0]
    if entry != 0x1000_0000:
        raise AssertionError(f"{elf.relative_to(ROOT)}: entry must be 0x10000000, got 0x{entry:08x}")
    first_line = next((line.strip() for line in read(mem).splitlines() if line.strip()), "")
    if first_line != "@0":
        raise AssertionError(f"{mem.relative_to(ROOT)}: UART boot image must start at relative word @0")


def check_product(product: str) -> None:
    root = PRODUCTS[product]
    core_runner = root / "dv/core/sim/run_regression.py"
    soc_runner = root / "dv/soc/sim/run_regression.py"
    profile = root / "dv/soc/tb/tb_perf_profile.svh"
    soc_tb = root / "dv/soc/tb/soc_tb.sv"
    sim_do = root / "dv/soc/sim/run_sim.do"
    jtag_agent = root / "dv/soc/tb/tb_jtag_dmi_agent.svh"
    tcm_tb = root / "dv/soc/tb/tcm_arbitration_tb.sv"

    for case in COMMON_CORE_CASES:
        require_case(product, core_runner, case)
    for case in COMMON_SOC_CASES:
        require_contains(soc_runner, f'"{case}"')
    for marker in COMMON_PROFILE_MARKERS:
        require_contains(profile, marker)
    for path in (soc_tb, sim_do):
        require_contains(path, "jtag_boot_trace_file")
    require_contains(jtag_agent, "load_instruction_memory_via_jtag_boot_trace")
    for token in ("lmem_req", "lmem_accept", "lmem_resp_valid", "mem_write_accept"):
        require_contains(tcm_tb, token)
    require_boot_image_contract(product)

    sibling = "eriscv-m1" if product == "M0" else "eriscv-m0"
    for path in (root / "dv").rglob("*"):
        if path.suffix not in {".py", ".sv", ".svh", ".do", ".list", ".f", ".mk"}:
            continue
        if path.is_file() and sibling in path.read_text(encoding="utf-8", errors="ignore"):
            raise AssertionError(f"{path.relative_to(ROOT)}: product-local DV references sibling {sibling}")

    if product == "M1":
        require_contains(profile, "TB PERF MULDIV:")
        require_contains(core_runner, '"MCU-PMP-01"')
    else:
        if "TB PERF MULDIV:" in read(profile):
            raise AssertionError("M0 profile must not claim RV32M observations")


def main() -> None:
    for product in PRODUCTS:
        check_product(product)
    print("M0/M1 TB contract OK: local trees, shared scenarios, and profile schema aligned")


if __name__ == "__main__":
    main()
