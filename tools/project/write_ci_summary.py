#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Render concise GitHub Actions summaries from eRISCV CI output."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


EMBENCH_WORKLOADS = (
    "matmult-int", "crc32", "huffbench", "sglib-combined", "slre", "qrduino",
    "aha-mont64", "minver", "nettle-aes", "nettle-sha256", "picojpeg", "wikisort",
)
EMBENCH_RESULT_RE = re.compile(
    r"EMBENCH SIM PASS: backend=(\S+) bench=([\w-]+) profile=(\w+) scale=(\d+) "
    r"mcycle=(\d+) mcycle_per_scale=([0-9.]+)"
)


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


def embench_suite_data(log_path: Path) -> tuple[str, int | None, int | None, dict[str, int], str | None, int | None]:
    text = log_path.read_text(encoding="utf-8", errors="replace") if log_path.is_file() else ""
    matches = re.findall(r"EMBENCH SUITE (PASS|FAIL): total=(\d+) passed=(\d+) failed=(\d+)", text)
    measurements = {
        bench: int(mcycle)
        for _backend, bench, _profile, _scale, mcycle, _per_scale in EMBENCH_RESULT_RE.findall(text)
    }
    configurations = {(profile, int(scale)) for _backend, _bench, profile, scale, _mcycle, _per_scale in EMBENCH_RESULT_RE.findall(text)}
    profile, scale = next(iter(configurations)) if len(configurations) == 1 else (None, None)
    if not matches:
        return benchmark_value(log_path, r"mcycle=([0-9]+)")[0], None, None, measurements, profile, scale
    state, total, passed, failed = matches[-1]
    total_count, passed_count = int(total), int(passed)
    result = f"✅ {passed}/{total} passed" if state == "PASS" and failed == "0" else f"❌ {failed}/{total} failed"
    return result, passed_count, total_count, measurements, profile, scale


def benchmark_data(product: str, coremark: Path, dhrystone: Path, embench: Path) -> dict[str, object]:
    coremark_status, coremark_value = benchmark_value(
        coremark, r"coremark_per_mhz=([0-9.]+)"
    )
    dhrystone_status, dhrystone_value = benchmark_value(
        dhrystone, r"dmips_per_mhz=([0-9.]+)"
    )
    embench_status, embench_passed, embench_total, embench_workloads, embench_profile, embench_scale = embench_suite_data(embench)
    return {
        "product": product.lower(),
        "coremark_status": coremark_status,
        "coremark_per_mhz": number_or_none(coremark_value),
        "dhrystone_status": dhrystone_status,
        "dmips_per_mhz": number_or_none(dhrystone_value),
        "embench_status": embench_status,
        "embench_passed": embench_passed,
        "embench_total": embench_total,
        "embench_workload_mcycles": embench_workloads,
        "embench_profile": embench_profile,
        "embench_scale": embench_scale,
    }


def write_benchmark(product: str, coremark: Path, dhrystone: Path, embench: Path) -> None:
    data = benchmark_data(product, coremark, dhrystone, embench)
    coremark_status = str(data["coremark_status"])
    dhrystone_status = str(data["dhrystone_status"])
    embench_status = str(data["embench_status"])
    coremark_value = "—" if data["coremark_per_mhz"] is None else f"{data['coremark_per_mhz']:.6f}"
    dhrystone_value = "—" if data["dmips_per_mhz"] is None else f"{data['dmips_per_mhz']:.6f}"
    embench_value = (
        "—" if data["embench_total"] is None
        else f"{data['embench_passed']}/{data['embench_total']} workloads"
    )
    print(f"### Nightly benchmarks ({product.upper()})\n")
    print("| Workload | Result | Measurement |")
    print("| --- | --- | --- |")
    print(f"| CoreMark smoke | {coremark_status} | {coremark_value} CoreMark/MHz |")
    print(f"| Dhrystone | {dhrystone_status} | {dhrystone_value} DMIPS/MHz |")
    print(f"| Embench-IoT suite | {embench_status} | {embench_value} |")
    measurements = data["embench_workload_mcycles"]
    if measurements:
        print()
        print("| Embench-IoT workload | Raw mcycle (lower is better) |")
        print("| --- | ---: |")
        for workload in EMBENCH_WORKLOADS:
            value = measurements.get(workload)
            print(f"| {workload} | {value if value is not None else '—'} |")
    print()
    print("CoreMark and Embench values are simulation measurements, not official scores.")


def parse_benchmark_product(value: str) -> tuple[str, tuple[Path, Path, Path]]:
    product, separator, raw_paths = value.partition("=")
    paths = raw_paths.split(",")
    if not separator or not product or len(paths) != 3 or any(not path for path in paths):
        raise argparse.ArgumentTypeError(
            "product logs must be PRODUCT=COREMARK_LOG,DHRYSTONE_LOG,EMBENCH_LOG"
        )
    return product.lower(), (Path(paths[0]), Path(paths[1]), Path(paths[2]))


def write_benchmark_matrix(products: list[tuple[str, tuple[Path, Path, Path]]]) -> None:
    data = {
        product: benchmark_data(product, coremark, dhrystone, embench)
        for product, (coremark, dhrystone, embench) in products
    }
    ordered_products = tuple(product for product in ("m0", "m1", "m2") if product in data)
    ordered_products += tuple(sorted(product for product in data if product not in ordered_products))

    print("### Nightly benchmarks\n")
    print("| MCU | CoreMark smoke | CoreMark/MHz | Dhrystone | DMIPS/MHz | Embench-IoT suite |")
    print("| --- | --- | ---: | --- | ---: | --- |")
    for product in ordered_products:
        report = data[product]
        coremark_value = "—" if report["coremark_per_mhz"] is None else f"{report['coremark_per_mhz']:.6f}"
        dhrystone_value = "—" if report["dmips_per_mhz"] is None else f"{report['dmips_per_mhz']:.6f}"
        embench_value = (
            "—" if report["embench_total"] is None
            else str(report["embench_status"])
        )
        print(
            f"| {product.upper()} | {report['coremark_status']} | {coremark_value} | "
            f"{report['dhrystone_status']} | {dhrystone_value} | {embench_value} |"
        )

    if any(data[product]["embench_workload_mcycles"] for product in ordered_products):
        print("\n#### Embench-IoT raw mcycle (lower is better)\n")
        print("| Workload | " + " | ".join(product.upper() for product in ordered_products) + " |")
        print("| --- | " + " | ".join("---:" for _ in ordered_products) + " |")
        for workload in EMBENCH_WORKLOADS:
            values = [data[product]["embench_workload_mcycles"].get(workload, "—") for product in ordered_products]
            print(f"| {workload} | " + " | ".join(str(value) for value in values) + " |")
    print()
    print("CoreMark and Embench values are simulation measurements, not official scores.")


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

    benchmark_matrix = subparsers.add_parser("benchmark-matrix")
    benchmark_matrix.add_argument("--product-logs", action="append", type=parse_benchmark_product, required=True)

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
    elif args.command == "benchmark-matrix":
        write_benchmark_matrix(args.product_logs)
    else:
        if args.format == "json":
            print(json.dumps(ppa_data(args.report_dir), separators=(",", ":")))
        else:
            write_ppa(args.report_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
