#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

# Build (if needed) and run one eRISCV ACT4 profile in an isolated Linux image.
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^m[012]$ ]]; then
  echo "Usage: $0 {m0|m1|m2}" >&2
  exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../.." && pwd)"
docker_bin="${DOCKER:-docker}"
image="${ERISCV_ACT4_IMAGE:-eriscv-act4:2025.06.07-sail0.12}"
act_root="${repo_root}/third_party/riscv-arch-test"

if ! command -v "${docker_bin}" >/dev/null 2>&1; then
  echo "Docker is required for the container ACT4 flow; install Docker Engine or Docker Desktop first." >&2
  exit 2
fi
if [[ ! -e "${act_root}/.git" ]]; then
  echo "Missing ACT4 submodule. Run: git submodule update --init third_party/riscv-arch-test" >&2
  exit 2
fi

if ! "${docker_bin}" image inspect "${image}" >/dev/null 2>&1; then
  echo "Building ACT4 image ${image}; the pinned RISC-V GCC build is intentionally slow." >&2
  "${docker_bin}" build --tag "${image}" --file "${script_dir}/Dockerfile" "${script_dir}"
fi

cache_root="${repo_root}/.cache/act4"
mkdir -p "${cache_root}"

exec "${docker_bin}" run --rm \
  --user "$(id -u):$(id -g)" \
  --env HOME=/tmp \
  --env ERISCV_ACT4_CACHE_ROOT=/work/.cache/act4 \
  --env MISE_DATA_DIR=/work/.cache/act4/mise-data \
  --env MISE_CONFIG_DIR=/work/.cache/act4/mise-config \
  --env ERISCV_ACT4_SAIL_ROOT=/opt/sail \
  --env ERISCV_ACT4_TOOLCHAIN_ROOT=/opt/riscv \
  --volume "${repo_root}:/work" \
  --workdir /work \
  "${image}" \
  bash -lc "mise trust /work/third_party/riscv-arch-test/.mise.toml && cd /work/third_party/riscv-arch-test && mise install && cd /work && make act-generate-$1"
