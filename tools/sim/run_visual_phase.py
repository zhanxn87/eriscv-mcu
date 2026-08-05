#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Generate Surfer waveforms and Konata traces for a phase-local sim directory."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sim-dir", type=Path, default=Path.cwd(), help="Phase sim directory.")
    parser.add_argument("--dump-format", choices=("fst", "vcd"), default="fst")
    parser.add_argument("--wave-dir", default="visual_waves")
    parser.add_argument("--trace-dir", default="konata_traces")
    parser.add_argument("--index-file", default="visual_index.txt")
    parser.add_argument("--surfer-command", default="surfer_default.sucl")
    parser.add_argument("regression_args", nargs=argparse.REMAINDER, help="Arguments passed to run_regression.py.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    sim_dir = args.sim_dir.resolve()
    run_regression = sim_dir / "run_regression.py"
    if not run_regression.exists():
        print(f"Missing run_regression.py in {sim_dir}", file=sys.stderr)
        return 2

    wave_dir = sim_dir / args.wave_dir
    trace_dir = sim_dir / args.trace_dir
    index_file = sim_dir / args.index_file
    shutil.rmtree(wave_dir, ignore_errors=True)
    shutil.rmtree(trace_dir, ignore_errors=True)
    index_file.unlink(missing_ok=True)

    command = [
        sys.executable,
        str(run_regression),
        "--backend",
        "verilator",
        "--wave",
        "--dump-format",
        args.dump_format,
        "--wave-dir",
        args.wave_dir,
        *args.regression_args,
    ]
    result = subprocess.run(command, cwd=sim_dir, check=False)
    if result.returncode != 0:
        return result.returncode

    waves = sorted(wave_dir.glob(f"*.{args.dump_format}"))
    if not waves:
        print(f"No .{args.dump_format} waveforms found in {wave_dir}", file=sys.stderr)
        return 1

    trace_dir.mkdir(parents=True, exist_ok=True)
    converter = repo_root() / "tools" / "visual" / "fst_to_kanata.py"

    surfer_command = sim_dir / args.surfer_command
    with index_file.open("w", encoding="ascii") as index:
        index.write(f"{sim_dir.parent.name} visual artifacts\n")
        index.write("=========================\n\n")
        if surfer_command.exists():
            index.write("Surfer signal command file:\n")
            index.write(f"  {surfer_command}\n\n")
        index.write("Konata traces:\n")
        index.write(f"  {trace_dir}\n\n")

        for wave in waves:
            test_name = wave.stem
            trace = trace_dir / f"{test_name}.kanata"
            subprocess.run([sys.executable, str(converter), str(wave), "-o", str(trace)], cwd=sim_dir, check=True)
            index.write(f"{test_name}\n")
            index.write("  Waveform:\n")
            index.write(f"    {wave}\n")
            if surfer_command.exists():
                index.write("  Surfer:\n")
                index.write(f"    surfer --command-file \"{surfer_command}\" \"{wave}\"\n")
            else:
                index.write("  Surfer:\n")
                index.write(f"    surfer \"{wave}\"\n")
            index.write("  Konata trace:\n")
            index.write(f"    {trace}\n\n")

    print()
    print(f"Visual artifacts generated for {len(waves)} testcase(s).")
    print("Index:")
    print(f"  {index_file}")
    print()
    print("Open signals in Surfer, for example:")
    if surfer_command.exists():
        print(f"  surfer --command-file \"{surfer_command}\" \"{waves[0]}\"")
    else:
        print(f"  surfer \"{waves[0]}\"")
    print()
    print("Open pipeline view in Konata and load the matching .kanata file:")
    print(f"  {trace_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
