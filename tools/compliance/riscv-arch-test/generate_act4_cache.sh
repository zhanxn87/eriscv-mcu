#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

# Build one complete default ACT4 runtime cache for an eRISCV MCU product.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 {m0|m1|m2}" >&2
  exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../.." && pwd)"
product="eriscv-$1"
act_dir="${repo_root}/${product}/compliance/riscv-arch-test"
act_root="${repo_root}/third_party/riscv-arch-test"
cache_dir="${act_dir}/generated"

case "$1" in
  m0)
    profiles=(build.sh)
    ;;
  m1|m2)
    # The public default corpus includes the base ISA selection and the U-mode
    # profile. PMPSm remains an explicit, separately documented profile.
    profiles=(build.sh build_u.sh)
    ;;
  *)
    echo "Unsupported product '$1'; expected m0, m1, or m2" >&2
    exit 2
    ;;
esac

if [[ ! -e "${act_root}/.git" ]]; then
  echo "Missing ACT4 submodule. Run: git submodule update --init third_party/riscv-arch-test" >&2
  exit 2
fi

case "${cache_dir}" in
  "${repo_root}"/eriscv-m*/compliance/riscv-arch-test/generated)
    ;;
  *)
    echo "Refusing to remove unexpected ACT4 cache path: ${cache_dir}" >&2
    exit 2
    ;;
esac

rm -rf -- "${cache_dir}"
for profile in "${profiles[@]}"; do
  "${act_dir}/${profile}"
done

count="$(find "${cache_dir}" -maxdepth 1 -name '*.act.json' -type f | wc -l)"
if [[ "${count}" -eq 0 ]]; then
  echo "ACT4 generation completed without manifests: ${cache_dir}" >&2
  exit 1
fi
echo "Generated ${count} ACT4 runtime manifests for ${product}."
