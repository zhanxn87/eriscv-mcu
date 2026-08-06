#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

# Opt-in Debian/Ubuntu host bootstrap for the eRISCV ACT4 generator.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bootstrap_act4_native.sh [--all|--system-packages|--mise|--sail|--toolchain]

Install selected ACT4 prerequisites into .cache/act4.  --all installs every
item; --system-packages is the only option that invokes sudo/apt-get.
The toolchain build is source-based and can take a long time.
EOF
}

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 2
fi

install_system=0
install_mise=0
install_sail=0
install_toolchain=0
for option in "$@"; do
  case "${option}" in
    --all) install_system=1; install_mise=1; install_sail=1; install_toolchain=1 ;;
    --system-packages) install_system=1 ;;
    --mise) install_mise=1 ;;
    --sail) install_sail=1 ;;
    --toolchain) install_toolchain=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: ${option}" >&2; usage >&2; exit 2 ;;
  esac
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../.." && pwd)"
act_root="${repo_root}/third_party/riscv-arch-test"
cache_root="${ERISCV_ACT4_CACHE_ROOT:-${repo_root}/.cache/act4}"
toolchain_root="${ERISCV_ACT4_TOOLCHAIN_ROOT:-${cache_root}/toolchain}"
sail_root="${ERISCV_ACT4_SAIL_ROOT:-${cache_root}/sail}"
mise_bin="${cache_root}/mise/bin/mise"
# mise invokes its own binary from Ruby gem post-install hooks while it is
# installing the pinned ACT4 tool set.  Keep the cache-local binary visible
# throughout bootstrap; the generated standard environment repeats this for
# later ACT4 commands.
export PATH="$(dirname -- "${mise_bin}"):${PATH}"

if [[ ! -e "${act_root}/.git" ]]; then
  echo "Missing ACT4 submodule. Run: git submodule update --init third_party/riscv-arch-test" >&2
  exit 2
fi
if [[ "${install_sail}" -eq 1 && ( "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ) ]]; then
  echo "The pinned Sail archive supports Linux x86_64 only; use the container flow or install Sail manually." >&2
  exit 2
fi
if [[ "${install_system}" -eq 1 && ! -r /etc/debian_version ]]; then
  echo "--system-packages currently supports Debian/Ubuntu only; use the container flow on other hosts." >&2
  exit 2
fi

if [[ "${install_system}" -eq 1 ]]; then
  sudo apt-get update
  sudo apt-get install -y \
    autoconf automake autotools-dev bc bison build-essential ca-certificates \
    cmake curl flex gawk git gperf libexpat-dev libglib2.0-dev libgmp-dev \
    libmpc-dev libmpfr-dev libncurses-dev libslirp-dev libtool make ninja-build \
    patchutils python3 python3-pip python3-tomli texinfo xz-utils zlib1g-dev
fi

mkdir -p "${cache_root}"
if [[ "${install_mise}" -eq 1 ]]; then
  mkdir -p "$(dirname "${mise_bin}")"
  curl --fail --location --retry 3 https://mise.jdx.dev/install.sh -o "${cache_root}/install-mise.sh"
  MISE_INSTALL_PATH="${mise_bin}" sh "${cache_root}/install-mise.sh"
  rm -f "${cache_root}/install-mise.sh"
  MISE_DATA_DIR="${cache_root}/mise-data" MISE_CONFIG_DIR="${cache_root}/mise-config" \
    "${mise_bin}" trust "${act_root}/.mise.toml"
  (
    cd "${act_root}"
    MISE_DATA_DIR="${cache_root}/mise-data" MISE_CONFIG_DIR="${cache_root}/mise-config" \
      "${mise_bin}" install
  )
fi

if [[ "${install_sail}" -eq 1 ]]; then
  if [[ ! -x "${sail_root}/bin/sail_riscv_sim" ]]; then
    mkdir -p "${sail_root}"
    curl --fail --location --retry 3 \
      https://github.com/riscv/sail-riscv/releases/download/0.12/sail-riscv-Linux-x86_64.tar.gz \
      | tar -xz --directory="${sail_root}" --strip-components=1
  fi
fi

if [[ "${install_toolchain}" -eq 1 ]]; then
  build_root="${cache_root}/riscv-gnu-toolchain-2025.06.07"
  rm -rf -- "${build_root}" "${toolchain_root}"
  git clone --depth 1 --branch 2025.06.07 \
    https://github.com/riscv-collab/riscv-gnu-toolchain.git "${build_root}"
  (
    cd "${build_root}"
    ./configure --prefix="${toolchain_root}" \
      --with-multilib-generator="rv32e-ilp32e--;rv32i-ilp32--;rv32im-ilp32--;rv32iac-ilp32--;rv32imac-ilp32--;rv32imafc-ilp32f--;rv32imafdc-ilp32d--;rv64i-lp64--;rv64ic-lp64--;rv64iac-lp64--;rv64imac-lp64--;rv64imafdc-lp64d--;rv64im-lp64--;"
    make -j"$(nproc)"
  )
  rm -rf -- "${build_root}"
fi

echo "ACT4 bootstrap complete. Verify with:"
echo "  tools/compliance/riscv-arch-test/check_act4_standard_env.sh"
