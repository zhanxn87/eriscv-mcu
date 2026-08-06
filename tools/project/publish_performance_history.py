#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Append one nightly result and render the lightweight performance dashboard."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


HTML = """<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>eRISCV nightly performance</title>
<style>
body { max-width: 1100px; margin: 2rem auto; padding: 0 1rem; color: #17202a; font: 15px system-ui, sans-serif; }
h1, h2 { margin-top: 2rem; } .note { color: #536471; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(330px, 1fr)); gap: 1rem; }
.chart { border: 1px solid #d0d7de; border-radius: 6px; padding: .6rem; }
table { border-collapse: collapse; width: 100%; } th, td { border-bottom: 1px solid #d0d7de; padding: .45rem; text-align: right; }
th:first-child, td:first-child { text-align: left; } .legend span { margin-right: 1rem; } .m0 { color: #0969da; } .m1 { color: #1a7f37; } .m2 { color: #cf222e; }
</style>
<h1>eRISCV nightly performance</h1>
<p class="note">Updated only after a changed-source nightly run succeeds. Generic Liberty PPA: SRAM macro area and timing excluded. CoreMark and Embench are simulation-smoke measurements, not official scores.</p>
<div id="latest"></div>
<h2>Trend</h2><div class="grid" id="charts"></div>
<h2>Recent runs</h2><div id="history"></div>
<script>
const products = ["m0", "m1", "m2"], colors = {m0:"#0969da",m1:"#1a7f37",m2:"#cf222e"};
const value = (run, product, metric) => metric.startsWith("ppa.") ? run.ppa.products[product]?.[metric.slice(4)] : run.benchmarks[product]?.[metric];
const text = (number, digits=2) => Number.isFinite(number) ? number.toFixed(digits) : "—";
function chart(runs, title, metric, digits=2) {
  const points = products.flatMap(p => runs.map((run, index) => ({p,index,value:value(run,p,metric)})).filter(x => Number.isFinite(x.value)));
  if (!points.length) return "";
  const min = Math.min(...points.map(x => x.value)), max = Math.max(...points.map(x => x.value));
  const range = max - min || 1, width = 440, height = 220, pad = 36;
  const line = p => runs.map((run, index) => ({index,value:value(run,p,metric)})).filter(x => Number.isFinite(x.value)).map(x => `${pad + x.index * (width - 2 * pad) / Math.max(runs.length - 1, 1)},${height - pad - (x.value - min) * (height - 2 * pad) / range}`).join(" ");
  return `<div class="chart"><strong>${title}</strong><svg viewBox="0 0 ${width} ${height}" width="100%" aria-label="${title}"><line x1="${pad}" y1="${pad}" x2="${pad}" y2="${height-pad}" stroke="#57606a"/><line x1="${pad}" y1="${height-pad}" x2="${width-pad}" y2="${height-pad}" stroke="#57606a"/><text x="2" y="${pad+4}" font-size="11">${text(max,digits)}</text><text x="2" y="${height-pad+4}" font-size="11">${text(min,digits)}</text>${products.map(p => `<polyline fill="none" stroke="${colors[p]}" stroke-width="2" points="${line(p)}"/>`).join("")}</svg><div class="legend">${products.map(p => `<span class="${p}">● ${p.toUpperCase()}</span>`).join("")}</div></div>`;
}
fetch("data/history.json").then(r => r.json()).then(data => {
  const runs = data.runs || [], latest = runs.at(-1);
  if (!latest) { document.body.insertAdjacentHTML("beforeend", "<p>No successful nightly data yet.</p>"); return; }
  document.querySelector("#latest").innerHTML = `<h2>Latest: <a href="${latest.run_url}">${latest.timestamp} (${latest.sha.slice(0,7)})</a></h2><table><thead><tr><th>MCU</th><th>Area µm²</th><th>Fmax MHz</th><th>Sync WNS ns</th><th>CoreMark/MHz</th><th>DMIPS/MHz</th><th>Embench mcycle</th></tr></thead><tbody>${products.map(p => `<tr><td>${p.toUpperCase()}</td><td>${text(value(latest,p,"ppa.area_um2"),0)}</td><td>${text(value(latest,p,"ppa.fmax_mhz"))}</td><td>${text(value(latest,p,"ppa.synchronous_path_wns_ns"))}</td><td>${text(value(latest,p,"coremark_per_mhz"),6)}</td><td>${text(value(latest,p,"dmips_per_mhz"),6)}</td><td>${text(value(latest,p,"embench_mcycle"),0)}</td></tr>`).join("")}</tbody></table>`;
  const recent = runs.slice(-30);
  document.querySelector("#charts").innerHTML = chart(recent,"Cell area (µm²)","ppa.area_um2",0) + chart(recent,"Fmax (MHz)","ppa.fmax_mhz") + chart(recent,"CoreMark/MHz","coremark_per_mhz",6) + chart(recent,"DMIPS/MHz","dmips_per_mhz",6);
  document.querySelector("#history").innerHTML = `<table><thead><tr><th>Run</th><th>SHA</th><th>M0 Fmax</th><th>M1 Fmax</th><th>M2 Fmax</th><th>M0 CoreMark/MHz</th><th>M1 CoreMark/MHz</th><th>M2 CoreMark/MHz</th></tr></thead><tbody>${[...runs].reverse().slice(0,30).map(run => `<tr><td><a href="${run.run_url}">${run.timestamp}</a></td><td>${run.sha.slice(0,7)}</td>${products.map(p => `<td>${text(value(run,p,"ppa.fmax_mhz"))}</td>`).join("")}${products.map(p => `<td>${text(value(run,p,"coremark_per_mhz"),6)}</td>`).join("")}</tr>`).join("")}</tbody></table>`;
});
</script>
</html>
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--site-dir", type=Path, required=True)
    parser.add_argument("--timestamp", required=True)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--run-url", required=True)
    parser.add_argument("--ppa", required=True)
    parser.add_argument("--benchmark", action="append", required=True)
    return parser.parse_args()


def load_json(value: str) -> dict[str, object]:
    parsed = json.loads(value)
    if not isinstance(parsed, dict):
        raise ValueError("metrics JSON must be an object")
    return parsed


def main() -> int:
    args = parse_args()
    ppa = load_json(args.ppa)
    benchmarks = [load_json(value) for value in args.benchmark]
    by_product = {str(item["product"]): item for item in benchmarks}
    if set(by_product) != {"m0", "m1", "m2"}:
        raise ValueError("expected exactly one benchmark report for m0, m1, and m2")

    data_dir = args.site_dir / "data"
    data_dir.mkdir(parents=True, exist_ok=True)
    history_path = data_dir / "history.json"
    history = {"runs": []}
    if history_path.is_file():
        history = json.loads(history_path.read_text(encoding="utf-8"))
    runs = [run for run in history.get("runs", []) if run.get("run_url") != args.run_url]
    runs.append({
        "timestamp": args.timestamp,
        "sha": args.sha,
        "run_url": args.run_url,
        "ppa": ppa,
        "benchmarks": by_product,
    })
    history_path.write_text(json.dumps({"runs": runs[-180:]}, indent=2) + "\n", encoding="utf-8")
    (args.site_dir / "index.html").write_text(HTML, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
