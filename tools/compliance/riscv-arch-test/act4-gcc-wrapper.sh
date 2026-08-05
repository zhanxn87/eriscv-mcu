#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

if [[ "${1:-}" == "-dumpversion" ]]; then
  printf '15.0.0\n'
  exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
tmp_root="${TMPDIR:-${repo_root}/.cache/act4/tmp}"
mkdir -p "${tmp_root}"

tmpdir=""
cleanup() {
  if [[ -n "${tmpdir}" && -d "${tmpdir}" ]]; then
    rm -rf "${tmpdir}"
  fi
}
trap cleanup EXIT

rewrite_source() {
  local src="$1"
  local dst="$2"
  local compressed="$3"
  python3 - "$src" "$dst" "$compressed" <<'PY2'
from pathlib import Path
import re
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
compressed = sys.argv[3] == "1"
p2align_line_pat = re.compile(r'^(\s*)\.p2align\s+(\d+)(\s*(?:#.*)?)$')
p2align_any_pat = re.compile(r'\.p2align\s+(\d+)')
norvc_pat = re.compile(r'^(\s*)\.option\s+norvc(\s*(?:#.*)?)$')
out = []
data_macro = False
in_data_section = False
for line in src.read_text().splitlines(True):
    stripped = line.strip()
    if stripped == "RVTEST_DATA_BEGIN":
        in_data_section = True
        out.append(line)
        continue
    if stripped == "RVTEST_DATA_END":
        in_data_section = False
        out.append(line)
        continue
    if in_data_section:
        out.append(line)
        continue
    if data_macro:
        out.append(line)
        if stripped == ".endm":
            data_macro = False
        continue
    if stripped.startswith((".macro RVTEST_DATA_BEGIN", ".macro RVTEST_DATA_END", ".macro RVTEST_SIG_SETUP", ".macro RVTEST_FAILURE_DATA")):
        data_macro = True
        out.append(line)
        continue

    norvc = norvc_pat.match(line)
    if norvc:
        out.append(line)
        if compressed:
            indent, trailing = norvc.groups()
            comment = trailing if trailing.strip().startswith('#') else ''
            suffix = f' {comment}' if comment else ''
            out.append(f"{indent}.balignw 4, 0x0001{suffix}\n")
        continue

    if compressed:
        def compressed_p2align(match):
            power = int(match.group(1))
            return match.group(0) if power < 2 else f".balignw {1 << power}, 0x0001"
        out.append(p2align_any_pat.sub(compressed_p2align, line))
        continue

    p2align = p2align_line_pat.match(line)
    if not p2align:
        out.append(line)
        continue
    indent, power_s, trailing = p2align.groups()
    power = int(power_s)
    if power < 2:
        out.append(line)
        continue
    align = 1 << power
    comment = trailing if trailing.strip().startswith('#') else ''
    suffix = f' {comment}' if comment else ''
    out.append(f"{indent}.balignl {align}, 0x00000013{suffix}\n")
dst.write_text(''.join(out))
PY2
}

compressed=0
for arg in "$@"; do
  case "$arg" in
    -march=*zca*|-march=*zcf*) compressed=1 ;;
  esac
done

# Preprocess first so alignment directives from ACT4 environment headers are
# rewritten together with directives in the test source itself.
cpp_args=()
skip_next=0
for arg in "$@"; do
  if [[ "$skip_next" == "1" ]]; then
    skip_next=0
    continue
  fi
  case "$arg" in
    *.S|*.s)
      ;;
    -o)
      skip_next=1
      ;;
    *)
      cpp_args+=("$arg")
      ;;
  esac
done

args=()
index=0
for arg in "$@"; do
  case "$arg" in
    *.S|*.s)
      if [[ -f "$arg" ]]; then
        if [[ -z "$tmpdir" ]]; then
          tmpdir="$(mktemp -d "${tmp_root}/act4-gcc.XXXXXX")"
        fi
        preprocessed="${tmpdir}/$(printf '%03d' "$index")-$(basename "$arg").pp.S"
        rewritten="${tmpdir}/$(printf '%03d' "$index")-$(basename "$arg")"
        riscv64-unknown-elf-gcc "${cpp_args[@]}" -E -P -o "$preprocessed" "$arg"
        rewrite_source "$preprocessed" "$rewritten" "$compressed"
        args+=("$rewritten")
        index=$((index + 1))
      else
        args+=("$arg")
      fi
      ;;
    *)
      args+=("$arg")
      ;;
  esac
done

riscv64-unknown-elf-gcc "${args[@]}"
