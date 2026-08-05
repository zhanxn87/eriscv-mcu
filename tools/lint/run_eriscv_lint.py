#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Run reproducible Verilator lint for eRISCV M0/M1/M2 RTL manifests."""
from __future__ import annotations
import argparse
import datetime as dt
import re
import shutil
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "project"))
from resolve_filelist import write_resolved_filelist  # noqa: E402

PRODUCTS = ("m0", "m1", "m2")
TARGETS = {
    "core": ("rtl/riscv_core/filelist.f", "riscv_core", "dv/core/sim"),
    "soc": ("rtl/soc/filelist.f", "soc", "dv/soc/sim"),
}
DIAG_RE = re.compile(r"^%(Warning|Error)-?([A-Z0-9_]*)?:\s+([^:]+):")

def diagnostic_origin(path: str) -> str:
    normalized = path.replace("\\", "/")
    if "/rtl/vendor/" in normalized:
        return "vendor"
    if "/rtl/" in normalized:
        return "project"
    return "testbench"

def summarize(text: str) -> Counter[tuple[str, str]]:
    counts: Counter[tuple[str, str]] = Counter()
    for line in text.splitlines():
        match = DIAG_RE.match(line)
        if match:
            level, code, path = match.groups()
            counts[(diagnostic_origin(path), f"{level}-{code or 'GENERIC'}")] += 1
    return counts

def run(command: list[str], cwd: Path, report: Path, version: str) -> int:
    result = subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    report.write_text(
        f"VERILATOR_VERSION={version}\nCOMMAND={' '.join(command)}\n\n"
        f"{result.stdout}\nVERILATOR_EXIT_STATUS={result.returncode}\n",
        encoding="utf-8", errors="replace")
    return result.returncode

def lint_product(product: str, target: str, verilator: str, stamp: str) -> int:
    manifest_rel, top_module, sim_rel = TARGETS[target]
    product_dir = ROOT / f"eriscv-{product}"
    manifest = product_dir / manifest_rel
    sim_dir = product_dir / sim_rel
    if not manifest.is_file() or not sim_dir.is_dir():
        raise RuntimeError(f"missing product target: {product}/{target}")
    report_dir = sim_dir / "lint_logs" / f"verilator_{target}_{stamp}"
    report_dir.mkdir(parents=True, exist_ok=True)
    version = subprocess.run([verilator, "--version"], text=True, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, check=False).stdout.strip()
    with tempfile.TemporaryDirectory(prefix=f"eriscv-{product}-{target}-lint-") as temp:
        resolved = Path(temp) / "sources.f"
        write_resolved_filelist(manifest, resolved, absolute=True)
        base = [verilator, "--lint-only", "--sv", "--timing", "--Wall", "-Wno-fatal",
                "-Wno-TIMESCALEMOD", "-Wno-CASEINCOMPLETE", "-f", str(resolved),
                "--top-module", top_module]
        strict_status = run(base, sim_dir, report_dir / "strict.log", version)
        completed = [*base]
        if product == "m2":
            completed.append("-Wno-BLKANDNBLK")
        completed_status = run(completed, sim_dir, report_dir / "completed.log", version)
    counts = summarize((report_dir / "completed.log").read_text(encoding="utf-8",
                                                                  errors="replace"))
    print("---ERISCV-RTL-LINT-RESULT---")
    print(f"PRODUCT: eriscv-{product}")
    print(f"TARGET: {target}")
    print(f"STRICT_EXIT: {strict_status}")
    print(f"COMPLETED_EXIT: {completed_status}")
    print(f"STRICT_REPORT: {report_dir / 'strict.log'}")
    print(f"COMPLETED_REPORT: {report_dir / 'completed.log'}")
    for (origin, code), count in sorted(counts.items()):
        print(f"{origin.upper()}_{code}: {count}")
    print("---END-ERISCV-RTL-LINT-RESULT---")
    return completed_status

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--product", choices=PRODUCTS, default="m2")
    parser.add_argument("--all-products", action="store_true")
    parser.add_argument("--target", choices=TARGETS, default="soc")
    parser.add_argument("--verilator", default="verilator")
    args = parser.parse_args()
    if shutil.which(args.verilator) is None:
        print(f"ERROR: Verilator not found: {args.verilator}", file=sys.stderr)
        return 2
    stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    products = PRODUCTS if args.all_products else (args.product,)
    statuses = [lint_product(product, args.target, args.verilator, stamp)
                for product in products]
    return 1 if any(statuses) else 0

if __name__ == "__main__":
    raise SystemExit(main())
