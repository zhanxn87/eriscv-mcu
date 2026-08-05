#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/act4-standard-env.sh"

mise_toml="${repo_root}/third_party/riscv-arch-test/.mise.toml"
ruby_version="$(awk -F'"' '/^ruby = / {print $2}' "${mise_toml}")"
uv_version="$(awk -F'"' '/^uv = / {print $2}' "${mise_toml}")"
mise_data_dir="${MISE_DATA_DIR:-${HOME}/.local/share/mise}"
ruby_bin="${mise_data_dir}/installs/ruby/${ruby_version}/bin/ruby"
bundle_bin="${mise_data_dir}/installs/ruby/${ruby_version}/bin/bundle"
uv_root="${mise_data_dir}/installs/uv/${uv_version}"
uv_bin="$(find "${uv_root}" -type f -name uv | head -n 1)"
bundle_home="${ERISCV_ACT4_BUNDLE_HOME:-${ERISCV_ACT4_CACHE_ROOT}/bundle-home}"

if [[ -z "${ruby_version}" || ! -x "${ruby_bin}" ]]; then
  echo "Missing mise-managed ruby install for version ${ruby_version}" >&2
  exit 1
fi
if [[ ! -x "${bundle_bin}" ]]; then
  echo "Missing bundle executable at ${bundle_bin}" >&2
  exit 1
fi
if [[ -z "${uv_bin}" || ! -x "${uv_bin}" ]]; then
  echo "Missing mise-managed uv install for version ${uv_version}" >&2
  exit 1
fi

mkdir -p "${bundle_home}"

echo "Checking ACT4 standard environment..."
echo

echo "[tool manager]"
echo "mise executable: ${mise_bin}"

echo
echo "[tool versions from installed paths]"
"${ruby_bin}" --version
HOME="${bundle_home}" BUNDLE_USER_HOME="${bundle_home}/.bundle" BUNDLE_APP_CONFIG="${bundle_home}/.bundle" "${bundle_bin}" --version
"${uv_bin}" --version

echo
echo "[reference model]"
sail_riscv_sim --version

echo
echo "[compiler]"
riscv64-unknown-elf-gcc --version | head -n 1

echo
echo "[cache roots]"
echo "XDG_CACHE_HOME=${XDG_CACHE_HOME:-<not set>}"

echo
echo "[notes]"
echo "- riscv-arch-test README currently documents GCC 15 / Binutils 2.44 or LLVM 21 as the officially tested compiler baseline."
echo "- This script checks installed tool paths directly and avoids network-heavy mise exec probes."
