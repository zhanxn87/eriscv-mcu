#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

trace=""
trace_dir=""
test_name=""
viewer="${KONATA_VIEWER_HTML:-}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  konata_viewer.sh [trace.kanata]
  konata_viewer.sh --trace-dir konata_traces [--test TESTCASE]

When --trace-dir is used, --test selects TESTCASE.kanata. If --test is omitted
and exactly one trace exists, that trace is opened. If multiple traces exist,
the script prints the available testcase names and exits.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --trace-dir)
      trace_dir="${2:-}"
      if [[ -z "$trace_dir" ]]; then
        echo "--trace-dir requires a directory" >&2
        exit 2
      fi
      shift 2
      ;;
    --test)
      test_name="${2:-}"
      if [[ -z "$test_name" ]]; then
        echo "--test requires a testcase name" >&2
        exit 2
      fi
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      if [[ -n "$trace" ]]; then
        echo "Only one trace path can be passed" >&2
        exit 2
      fi
      trace="$1"
      shift
      ;;
  esac
done

if [[ -z "$viewer" ]]; then
  candidates=(
    "$repo_root/tools/visual/konata_viewer/KonataViewer.html"
    "$PWD/konata_viewer/KonataViewer.html"
  )
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      viewer="$candidate"
      break
    fi
  done
fi

if [[ -z "$viewer" || ! -f "$viewer" ]]; then
  echo "Konata viewer HTML was not found." >&2
  echo "Set KONATA_VIEWER_HTML=/path/to/KonataViewer.html or install tools/visual/konata_viewer/KonataViewer.html." >&2
  exit 1
fi

if [[ -n "$trace_dir" ]]; then
  if [[ ! -d "$trace_dir" ]]; then
    echo "Konata trace directory was not found: $trace_dir" >&2
    exit 1
  fi

  if [[ -n "$test_name" ]]; then
    trace="$trace_dir/$test_name.kanata"
    if [[ ! -f "$trace" ]]; then
      echo "Konata trace was not found: $trace" >&2
      echo "Available traces:" >&2
      find "$trace_dir" -maxdepth 1 -type f -name '*.kanata' -printf '  %f\n' 2>/dev/null | sed 's/\.kanata$//' >&2
      exit 1
    fi
  else
    mapfile -t traces < <(find "$trace_dir" -maxdepth 1 -type f -name '*.kanata' | sort)
    case "${#traces[@]}" in
      0)
        echo "No Konata traces found in $trace_dir. Run make visual first." >&2
        exit 1
        ;;
      1)
        trace="${traces[0]}"
        ;;
      *)
        echo "Multiple Konata traces found in $trace_dir."
        echo "Select one with:"
        for candidate in "${traces[@]}"; do
          name="$(basename "$candidate" .kanata)"
          echo "  make konata TESTS=$name"
        done
        exit 2
        ;;
    esac
  fi
fi

open_target="$viewer"
if [[ -n "$trace" ]]; then
  if [[ ! -f "$trace" ]]; then
    echo "Konata trace was not found: $trace" >&2
    exit 1
  fi
  open_target="$(python3 - "$viewer" "$trace" <<'PYGEN'
from pathlib import Path
import json
import sys

viewer = Path(sys.argv[1]).resolve()
trace = Path(sys.argv[2]).resolve()
html = viewer.read_text(encoding="utf-8")
trace_text = trace.read_text(encoding="ascii", errors="replace")
stage_note = """
<strong>Stage mapping</strong>
<span>IF: inferred as the cycle before an instruction enters ID.</span>
<span>ID: if_id_q.valid with if_id_q.pc/instr.</span>
<span>EX: id_ex_q.valid.</span>
<span>MEM: ex_mem_q.valid.</span>
<span>WB: mem_wb_q.valid.</span>
<span>Squashed fetch requests that never enter ID are omitted.</span>
"""
needle = "window.app=app;"
if needle not in html:
    needle = "const app=new App;"
    replacement = "const app=new App;window.app=app;"
else:
    replacement = needle
inject = (
    replacement
    + "\n(()=>{\n"
    + "  const text = " + json.dumps(trace_text) + ";\n"
    + "  const note = document.createElement('div');\n"
    + "  note.id = 'riscz-stage-mapping-note';\n"
    + "  note.innerHTML = " + json.dumps(stage_note) + ";\n"
    + "  note.style.cssText = 'position:fixed;right:12px;bottom:12px;z-index:9999;max-width:420px;padding:10px 12px;border:1px solid rgba(160,170,190,.55);border-radius:6px;background:rgba(24,28,36,.92);color:#e8edf5;font:12px/1.35 sans-serif;box-shadow:0 8px 24px rgba(0,0,0,.28)';\n"
    + "  note.querySelectorAll('span').forEach((item)=>{item.style.display='block';});\n"
    + "  note.querySelector('strong').style.display='block';\n"
    + "  note.querySelector('strong').style.marginBottom='4px';\n"
    + "  document.body.appendChild(note);\n"
    + "  app.loadFile(new File([text], " + json.dumps(trace.name) + ", {type: 'text/plain'}));\n"
    + "})();"
)
out = trace.parent / f".{trace.stem}.konata_autoload.html"
out.write_text(html.replace(needle, inject, 1), encoding="utf-8")
print(out)
PYGEN
)"
fi

echo "Konata viewer: $viewer"
if [[ -n "$trace" ]]; then
  echo "Loaded trace: $trace"
  echo "Autoload page: $open_target"
fi

if [[ -n "${BROWSER:-}" ]]; then
  exec "$BROWSER" "$open_target"
elif command -v xdg-open >/dev/null 2>&1; then
  exec xdg-open "$open_target"
elif command -v firefox >/dev/null 2>&1; then
  exec firefox "$open_target"
elif command -v firefox.exe >/dev/null 2>&1; then
  exec firefox.exe "$(wslpath -w "$open_target" 2>/dev/null || printf '%s' "$open_target")"
elif command -v wslview >/dev/null 2>&1; then
  exec wslview "$open_target"
elif command -v powershell.exe >/dev/null 2>&1; then
  exec powershell.exe -NoProfile -Command Start-Process "$(wslpath -w "$open_target" 2>/dev/null || printf '%s' "$open_target")"
else
  echo "No BROWSER or xdg-open found; open the path above manually."
fi
