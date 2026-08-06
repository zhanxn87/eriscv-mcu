#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Render concise GitHub Actions summaries from eRISCV CI output."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


def status(log_path: Path) -> str:
    if not log_path.is_file():
        return "— not produced"
    text = log_path.read_text(encoding="utf-8", errors="replace")
    totals = re.findall(r"Total:\s*(\d+),\s*Passed:\s*(\d+),\s*Failed:\s*(\d+)", text)
    if totals:
        total, passed, failed = totals[-1]
        return f"✅ {passed}/{total} passed" if failed == "0" else f"❌ {failed}/{total} failed"
    if re.search(r"(?:\bFAIL\b|\*\*\* .*Error|Traceback \(most recent call last\))", text):
        return "❌ failed"
    return "✅ completed"


def parse_suite(value: str) -> tuple[str, Path]:
    label, separator, raw_path = value.partition("=")
    if not separator or not label or not raw_path:
        raise argparse.ArgumentTypeError("suite must be LABEL=PATH")
    return label, Path(raw_path)


def write_regression(title: str, suites: list[tuple[str, Path]]) -> None:
    print(f"### {title}\n")
    print("| Suite | Result |")
    print("| --- | --- |")
    for label, log_path in suites:
        print(f"| {label} | {status(log_path)} |")


def metric(text: str, pattern: str) -> str:
    match = re.search(pattern, text)
    return match.group(1) if match else "—"


def benchmark_value(log_path: Path, pattern: str) -> tuple[str, str]:
    result = status(log_path)
    if not result.startswith("✅"):
        return result, "—"
    text = log_path.read_text(encoding="utf-8", errors="replace")
    value = metric(text, pattern)
    return (result, value) if value != "—" else ("⚠ metric missing", value)


def number_or_none(value: str) -> float | None:
    return float(value) if value != "—" else None


def benchmark_data(product: str, coremark: Path, dhrystone: Path, embench: Path) -> dict[str, object]:
    coremark_status, coremark_value = benchmark_value(
        coremark, r"coremark_per_mhz=([0-9.]+)"
    )
    dhrystone_status, dhrystone_value = benchmark_value(
        dhrystone, r"dmips_per_mhz=([0-9.]+)"
    )
    embench_status, embench_value = benchmark_value(
        embench, r"mcycle=([0-9]+)"
    )
    return {
        "product": product.lower(),
        "coremark_status": coremark_status,
        "coremark_per_mhz": number_or_none(coremark_value),
        "dhrystone_status": dhrystone_status,
        "dmips_per_mhz": number_or_none(dhrystone_value),
        "embench_status": embench_status,
        "embench_mcycle": int(embench_value) if embench_value != "—" else None,
    }


def write_benchmark(product: str, coremark: Path, dhrystone: Path, embench: Path) -> None:
    data = benchmark_data(product, coremark, dhrystone, embench)
    coremark_status = str(data["coremark_status"])
    dhrystone_status = str(data["dhrystone_status"])
    embench_status = str(data["embench_status"])
    coremark_value = "—" if data["coremark_per_mhz"] is None else f"{data['coremark_per_mhz']:.6f}"
    dhrystone_value = "—" if data["dmips_per_mhz"] is None else f"{data['dmips_per_mhz']:.6f}"
    embench_value = "—" if data["embench_mcycle"] is None else str(data["embench_mcycle"])
    print(f"### Nightly benchmarks ({product.upper()})\n")
    print("| Workload | Result | Measurement |")
    print("| --- | --- | --- |")
    print(f"| CoreMark smoke | {coremark_status} | {coremark_value} CoreMark/MHz |")
    print(f"| Dhrystone | {dhrystone_status} | {dhrystone_value} DMIPS/MHz |")
    print(f"| Embench matmult-int smoke | {embench_status} | {embench_value} mcycle |")
    print()
    print("CoreMark and Embench values are simulation-smoke measurements, not official scores.")


def fmt_number(value: object, digits: int) -> str:
    return f"{float(value):.{digits}f}" if isinstance(value, (int, float)) else "—"


def ppa_data(report_dir: Path) -> dict[str, object]:
    products: dict[str, dict[str, object]] = {}
    for product in ("m0", "m1", "m2"):
        summary_path = report_dir / product / "summary.json"
        if not summary_path.is_file():
            products[product] = {"status": "not produced"}
            continue
        try:
            report = json.loads(summary_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            products[product] = {"status": "invalid summary"}
            continue
        products[product] = {
            "status": "complete",
            "area_um2": report.get("area_um2"),
            "fmax_mhz": report.get("fmax_mhz"),
            "synchronous_path_wns_ns": report.get("synchronous_path_wns_ns"),
        }
    return {"products": products}


def write_ppa(report_dir: Path) -> None:
    print("### Nightly generic-Liberty PPA\n")
    print("| MCU | Cell area (µm²) | Fmax (MHz) | Sync WNS (ns) | Result |")
    print("| --- | ---: | ---: | ---: | --- |")
    data = ppa_data(report_dir)
    for product in ("m0", "m1", "m2"):
        report = data["products"][product]
        if report["status"] != "complete":
            print(f"| {product.upper()} | — | — | — | ❌ {report['status']} |")
            continue
        print(
            f"| {product.upper()} | {fmt_number(report.get('area_um2'), 3)} | "
            f"{fmt_number(report.get('fmax_mhz'), 2)} | "
            f"{fmt_number(report.get('synchronous_path_wns_ns'), 2)} | ✅ complete |"
        )
    if any(item["status"] == "complete" for item in data["products"].values()):
        print()
        print("Generic Liberty only; SRAM macro area and timing are excluded.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    regression = subparsers.add_parser("regression")
    regression.add_argument("--title", required=True)
    regression.add_argument("--suite", action="append", type=parse_suite, required=True)
    regression.add_argument("--format", choices=("markdown", "json"), default="markdown")

    benchmark = subparsers.add_parser("benchmark")
    benchmark.add_argument("--product", required=True)
    benchmark.add_argument("--coremark", type=Path, required=True)
    benchmark.add_argument("--dhrystone", type=Path, required=True)
    benchmark.add_argument("--embench", type=Path, required=True)
    benchmark.add_argument("--format", choices=("markdown", "json"), default="markdown")

    ppa = subparsers.add_parser("ppa")
    ppa.add_argument("--report-dir", type=Path, required=True)
    ppa.add_argument("--format", choices=("markdown", "json"), default="markdown")

    args = parser.parse_args()
    if args.command == "regression":
        write_regression(args.title, args.suite)
    elif args.command == "benchmark":
        if args.format == "json":
            print(json.dumps(benchmark_data(args.product, args.coremark, args.dhrystone, args.embench), separators=(",", ":")))
        else:
            write_benchmark(args.product, args.coremark, args.dhrystone, args.embench)
    else:
        if args.format == "json":
            print(json.dumps(ppa_data(args.report_dir), separators=(",", ":")))
        else:
            write_ppa(args.report_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
