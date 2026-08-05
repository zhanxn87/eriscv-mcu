#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Remove repository-generated simulation and script workflow artifacts."""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path


PRODUCT_GLOB = "eriscv-m*"
SIM_DIR_NAMES = (
    "obj_dir",
    "sim_build",
    "work",
    "regression_logs",
    "regression_data",
    "visual_waves",
    "waves",
    "konata_traces",
    "vdb",
    "build",
)
SIM_FILE_PATTERNS = (
    "modelsim.ini",
    "transcript",
    "*.log",
    "*.wlf",
    "*.vstf",
    "*.ucdb",
    "*.vcd",
    "*.fst",
    "*.vpd",
    "*.fsdb",
    "*.ghw",
    "coverage.dat",
    "simv",
)


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="List artifacts without removing them.")
    return parser.parse_args()


def add_if_present(paths: set[Path], path: Path) -> None:
    if path.exists() or path.is_symlink():
        paths.add(path)


def collect_artifacts(root: Path) -> list[Path]:
    paths: set[Path] = set()
    add_if_present(paths, root / "build")
    add_if_present(paths, root / ".cache" / "act4")

    for product in root.glob(PRODUCT_GLOB):
        add_if_present(paths, product / "sw" / "build")
        act4_dir = product / "compliance" / "riscv-arch-test"
        add_if_present(paths, act4_dir / "work")
        add_if_present(paths, act4_dir / "work-pmp")
        add_if_present(paths, act4_dir / "work-u")
        add_if_present(paths, act4_dir / "generated")

    for tree in (*root.glob(PRODUCT_GLOB), root / "peripherals", root / "tools"):
        if not tree.exists():
            continue
        for cache_dir in tree.rglob("__pycache__"):
            add_if_present(paths, cache_dir)
        for sim_dir in tree.rglob("sim"):
            if not sim_dir.is_dir():
                continue
            for name in SIM_DIR_NAMES:
                add_if_present(paths, sim_dir / name)
            for pattern in SIM_FILE_PATTERNS:
                for artifact in sim_dir.glob(pattern):
                    add_if_present(paths, artifact)

    return sorted(paths, key=lambda path: path.as_posix())


def remove(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    else:
        shutil.rmtree(path)


def main() -> int:
    args = parse_args()
    root = repo_root()
    artifacts = collect_artifacts(root)
    action = "Would remove" if args.dry_run else "Removing"
    for path in artifacts:
        print(f"{action}: {path.relative_to(root)}")
        if not args.dry_run:
            remove(path)
    print(f"{'Would remove' if args.dry_run else 'Removed'} {len(artifacts)} artifact(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
