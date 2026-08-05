#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Check SPDX headers on eRISCV-MCU original source files."""

from __future__ import annotations

import argparse
from pathlib import Path


SOURCE_NAMES = {"Makefile", "Dockerfile"}
SOURCE_SUFFIXES = {
    ".S", ".c", ".cfg", ".do", ".h", ".ld", ".mk", ".ps1", ".py",
    ".sh", ".sv", ".svh", ".tcl", ".xdc", ".yaml", ".yml",
}
EXCLUDED_PARTS = {
    ".git", "build", "generated", "obj_dir", "third_party", "vendor",
    "zephyr", "__pycache__",
}
BSD2_PATHS = {
    Path(f"eriscv-m{product}/sw/benchmarks/dhrystone/{name}")
    for product in ("0", "1", "2")
    for name in ("dhry.h", "dhry_1.c", "dhry_2.c")
}
COPYRIGHT = "SPDX-FileCopyrightText: 2025-2026 Xianning Zhan"
LICENSE = "SPDX-License-Identifier: BSD-3-Clause"


def is_source(path: Path) -> bool:
    return path.name in SOURCE_NAMES or path.suffix in SOURCE_SUFFIXES


def is_original_source(root: Path, path: Path) -> bool:
    relative = path.relative_to(root)
    return (
        is_source(path)
        and not any(part in EXCLUDED_PARTS for part in relative.parts)
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    root = args.root.resolve()

    missing: list[Path] = []
    checked = 0
    for path in sorted(root.rglob("*")):
        if not path.is_file() or not is_original_source(root, path):
            continue
        checked += 1
        header_lines = path.read_text(encoding="utf-8", errors="replace").splitlines()[:20]
        relative = path.relative_to(root)
        required_license = "SPDX-License-Identifier: BSD-2-Clause" if relative in BSD2_PATHS else LICENSE
        comment_prefixes = ("#", "//", "/*", "*")
        has_copyright = any(COPYRIGHT in line and line.lstrip().startswith(comment_prefixes) for line in header_lines)
        has_license = any(required_license in line and line.lstrip().startswith(comment_prefixes) for line in header_lines)
        if not has_copyright or not has_license:
            missing.append(path.relative_to(root))

    if missing:
        print("Missing required SPDX header:")
        for path in missing:
            print(f"  {path}")
        return 1
    print(f"SPDX header check passed: {checked} original source files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
