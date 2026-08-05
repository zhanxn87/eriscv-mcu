#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Emit an eRISCV private-DMI IMEM boot trace from an ELF32 LE image."""

from __future__ import annotations

import argparse
from pathlib import Path

from elf_to_mem import add_bytes, elf_entry_point, load_segments

DMI_BOOT_ADDR = 0x60
DMI_BOOT_WDATA = 0x61
DMI_BOOT_CTRL = 0x62
BOOT_CTRL_HOLD_AUTOINC = 0x0000000E
BOOT_CTRL_RELEASE_AUTOINC = 0x00000005


def parse_int(value: str) -> int:
    return int(value, 0)


def build_imem_words(elf: Path, imem_base: int, imem_size: int) -> dict[int, int]:
    imem_limit = imem_base + imem_size
    words: dict[int, int] = {}
    for _vaddr, paddr, _flags, payload in load_segments(elf):
        if not imem_base <= paddr or (paddr + len(payload)) > imem_limit:
            raise ValueError(
                f"load segment at physical address 0x{paddr:08x} lies outside "
                f"IMEM [0x{imem_base:08x}, 0x{imem_limit:08x})"
            )
        add_bytes(words, paddr, payload, imem_base, imem_limit)
    if not words:
        raise ValueError("ELF has no loadable IMEM bytes")
    return words


def write_dmi_trace(path: Path, words: dict[int, int]) -> None:
    """Write two-column hexadecimal DMI writes for the JTAG TB agent."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", newline="\n") as stream:
        stream.write(f"{DMI_BOOT_CTRL:02x} {BOOT_CTRL_HOLD_AUTOINC:08x}\n")
        expected_index: int | None = None
        for index in sorted(words):
            if index != expected_index:
                stream.write(f"{DMI_BOOT_ADDR:02x} {index:08x}\n")
            stream.write(f"{DMI_BOOT_WDATA:02x} {words[index]:08x}\n")
            expected_index = index + 1
        stream.write(f"{DMI_BOOT_CTRL:02x} {BOOT_CTRL_RELEASE_AUTOINC:08x}\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("elf", type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--imem-base", type=parse_int, default=0x10000000)
    parser.add_argument("--imem-size", type=parse_int, default=0x10000)
    parser.add_argument(
        "--expected-entry",
        type=parse_int,
        default=0x10000000,
        help="require this ELF entry point",
    )
    args = parser.parse_args()

    if args.imem_size <= 0 or (args.imem_size & 3):
        raise ValueError("IMEM size must be a positive multiple of four bytes")
    if args.expected_entry is not None and elf_entry_point(args.elf) != args.expected_entry:
        raise ValueError(
            f"ELF entry is 0x{elf_entry_point(args.elf):08x}; "
            f"expected 0x{args.expected_entry:08x}"
        )

    words = build_imem_words(args.elf, args.imem_base, args.imem_size)
    write_dmi_trace(args.out, words)
    print(f"DMI boot trace: {len(words)} words -> {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
