#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
act_root="${repo_root}/third_party/riscv-arch-test"
export ERISCV_ACT4_CACHE_ROOT="${ERISCV_ACT4_CACHE_ROOT:-${repo_root}/.cache/act4}"
local_mise_bin="${ERISCV_ACT4_CACHE_ROOT}/mise/bin/mise"
mise_bin="${MISE_BIN:-}"
if [[ -z "${mise_bin}" && -x "${local_mise_bin}" ]]; then
  mise_bin="${local_mise_bin}"
fi
if [[ -z "${mise_bin}" ]]; then
  mise_bin="$(command -v mise || true)"
fi
sail_root="${ERISCV_ACT4_SAIL_ROOT:-${ERISCV_ACT4_CACHE_ROOT}/sail}"
toolchain_root="${ERISCV_ACT4_TOOLCHAIN_ROOT:-${ERISCV_ACT4_CACHE_ROOT}/toolchain}"

if [[ ! -f "${act_root}/.mise.toml" ]]; then
  echo "Missing ACT4 submodule. Run: git submodule update --init third_party/riscv-arch-test" >&2
  return 1 2>/dev/null || exit 1
fi

if [[ -z "${mise_bin}" || ! -x "${mise_bin}" ]]; then
  echo "Missing mise; install it or set MISE_BIN" >&2
  return 1 2>/dev/null || exit 1
fi

if [[ ! -x "${sail_root}/bin/sail_riscv_sim" ]]; then
  echo "Missing Sail install at ${sail_root}/bin/sail_riscv_sim" >&2
  return 1 2>/dev/null || exit 1
fi

export XDG_CACHE_HOME="${ERISCV_ACT4_CACHE_ROOT}/xdg-cache"
export XDG_DATA_HOME="${ERISCV_ACT4_CACHE_ROOT}/xdg-data"
export UV_CACHE_DIR="${ERISCV_ACT4_CACHE_ROOT}/uv-cache"
export UV_PYTHON_INSTALL_DIR="${ERISCV_ACT4_CACHE_ROOT}/uv-python"
export MISE_DATA_DIR="${MISE_DATA_DIR:-${ERISCV_ACT4_CACHE_ROOT}/mise-data}"
export MISE_CONFIG_DIR="${MISE_CONFIG_DIR:-${ERISCV_ACT4_CACHE_ROOT}/mise-config}"

# ACT4's test generator requires Python 3.12 on this host. Its Makefile uses
# ':=' for UV_RUN, so export the value and promote it through MAKEFLAGS, whose
# command-line assignment has precedence over the Makefile default.
export UV_RUN="mise exec -- uv run --python 3.12"
export MAKEFLAGS="${MAKEFLAGS:-} UV_RUN=mise\\ exec\\ --\\ uv\\ run\\ --python\\ 3.12"

mise_data_dir="${MISE_DATA_DIR}"
ruby_version="$(awk -F'"' '/^ruby = / {print $2}' "${act_root}/.mise.toml")"
ruby_bin_dir="${mise_data_dir}/installs/ruby/${ruby_version}/bin"
export BUNDLE_PATH="${ERISCV_ACT4_CACHE_ROOT}/ruby-bundle"

mkdir -p "${XDG_CACHE_HOME}" "${XDG_DATA_HOME}" "${UV_CACHE_DIR}" "${UV_PYTHON_INSTALL_DIR}" "${BUNDLE_PATH}" "${MISE_DATA_DIR}" "${MISE_CONFIG_DIR}"

export PATH="${ruby_bin_dir}:$(dirname "${mise_bin}"):${MISE_DATA_DIR}/shims:${sail_root}/bin:${toolchain_root}/bin:${PATH}"

if [[ "${1:-}" == "--print" ]]; then
  echo "repo_root=${repo_root}"
  echo "mise_bin=${mise_bin}"
  echo "sail_root=${sail_root}"
  echo "toolchain_root=${toolchain_root}"
  echo "ERISCV_ACT4_CACHE_ROOT=${ERISCV_ACT4_CACHE_ROOT}"
  echo "MISE_DATA_DIR=${MISE_DATA_DIR}"
  echo "XDG_CACHE_HOME=${XDG_CACHE_HOME}"
  echo "XDG_DATA_HOME=${XDG_DATA_HOME}"
  echo "BUNDLE_PATH=${BUNDLE_PATH}"
  echo "PATH=${PATH}"
fi
