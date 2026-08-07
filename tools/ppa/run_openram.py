#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Generate the M0 Sky130 OpenRAM macro used by physical PPA."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
CONFIG = Path(__file__).with_name("openram") / "sky130_sram_16kbyte_1rw_32x4096_8.py"
MACRO_NAME = "eriscv_sram_16kbyte_1rw_32x4096_8"


def ppa_home() -> Path:
    return Path(os.environ.get("PPA_HOME", REPO_ROOT / ".cache" / "ppa")).resolve()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=ppa_home() / "openram" / MACRO_NAME)
    parser.add_argument("--openram-root", type=Path, default=ppa_home() / "src" / "OpenRAM")
    parser.add_argument("--pdk-root", type=Path, help="Sky130A root; defaults to PPA_SKY130_ROOT")
    parser.add_argument("--skip-verification", action="store_true", help="generate views without Magic/Netgen DRC/LVS")
    return parser.parse_args()


def find_pdk_root(explicit_root: Path | None) -> Path:
    if explicit_root is not None:
        candidates = [explicit_root]
    elif os.environ.get("PPA_SKY130_ROOT"):
        candidates = [Path(os.environ["PPA_SKY130_ROOT"])]
    else:
        candidates = sorted((ppa_home() / "pdks" / "volare" / "sky130" / "versions").glob("*/sky130A"))
    if len(candidates) != 1 or not candidates[0].is_dir():
        raise RuntimeError("Sky130 PDK root is ambiguous or missing; set PPA_SKY130_ROOT")
    return candidates[0].resolve()


def main() -> int:
    args = parse_args()
    openram_root = args.openram_root.resolve()
    compiler = openram_root / "sram_compiler.py"
    required_tech_dirs = ("gds_lib", "mag_lib", "sp_lib", "maglef_lib", "lvs_lib")
    if not CONFIG.is_file() or not compiler.is_file():
        raise SystemExit("OpenRAM is not initialized; run make ppa-openram-setup first")
    if any(not (openram_root / "technology" / "sky130" / directory).is_dir() for directory in required_tech_dirs):
        raise SystemExit("OpenRAM Sky130 build-space is incomplete; run make ppa-openram-setup first")

    pdk_root = find_pdk_root(args.pdk_root)
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    output_files = {suffix: output_dir / f"{MACRO_NAME}.{suffix}" for suffix in ("gds", "lef", "lib", "sp", "v")}
    environment = os.environ.copy()
    environment.update(
        {
            "OPENRAM_HOME": str(openram_root / "compiler"),
            "OPENRAM_TECH": str(openram_root / "technology"),
            "OPENRAM_TMP": str(output_dir / "tmp"),
            "PDK_ROOT": str(pdk_root.parent),
            "ERISCV_OPENRAM_OUTPUT": str(output_dir),
            "ERISCV_OPENRAM_CHECK_LVSDRC": "0" if args.skip_verification else "1",
        }
    )
    pydeps = ppa_home() / "pydeps"
    environment["PYTHONPATH"] = str(pydeps) + (
        os.pathsep + environment["PYTHONPATH"] if environment.get("PYTHONPATH") else ""
    )
    if not args.skip_verification:
        missing = [tool for tool in ("magic", "netgen") if shutil.which(tool, path=environment.get("PATH")) is None]
        if missing:
            raise SystemExit("OpenRAM DRC/LVS requires " + ", ".join(missing) + "; use --skip-verification only for preliminary PPA")

    log = output_dir / "openram.log"
    # OpenRAM gives command-line options precedence over the configuration file.
    # Use -p rather than relying solely on the config environment so a stale
    # shell setting cannot redirect generated macro views outside output_dir.
    command = [sys.executable, str(compiler), "-p", str(output_dir), str(CONFIG)]
    print("+", " ".join(command), flush=True)
    with log.open("w", encoding="utf-8") as log_file:
        completed = subprocess.run(command, env=environment, text=True, stdout=log_file, stderr=subprocess.STDOUT)
    if completed.returncode:
        raise SystemExit(f"OpenRAM failed ({completed.returncode}); see {log}")
    missing_outputs = [str(path) for path in output_files.values() if not path.is_file()]
    if missing_outputs:
        raise SystemExit("OpenRAM did not produce required views: " + ", ".join(missing_outputs))
    manifest = {
        "macro": MACRO_NAME,
        "configuration": str(CONFIG),
        "openram_root": str(openram_root),
        "pdk_root": str(pdk_root),
        "physical_verification": "skipped" if args.skip_verification else "OpenRAM Magic/Netgen",
        "views": {suffix: str(path) for suffix, path in output_files.items()},
    }
    (output_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
