#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

# Install a reproducible local Yosys/OpenSTA/generic-Liberty toolchain for WSL or CI.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ppa_home="${PPA_HOME:-${repo_root}/.cache/ppa}"
prefix="${ppa_home}/prefix"
cudd_ref="3.0.0"
opensta_ref="3f4b337e30afccf8075118860daf2e4fea8a5c18"
oss_cad_release="2026-08-05"
oss_cad_archive="oss-cad-suite-linux-x64-20260805.tgz"
liberty_ref="c2cdaddb1ff4b0a54e9121768b248c73ec7d3723"
liberty_path="${ppa_home}/liberty/NangateOpenCellLibrary_typical.lib"
liberty_url="https://raw.githubusercontent.com/The-OpenROAD-Project/OpenROAD-flow-scripts/${liberty_ref}/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib"

sudo apt-get update
sudo apt-get install --yes build-essential bison cmake curl flex git libeigen3-dev swig tcl-dev

mkdir -p "${ppa_home}/src" "${ppa_home}/build" "${ppa_home}/liberty" "${prefix}"

if [ ! -f "${prefix}/lib/libcudd.a" ]; then
  if [ ! -d "${ppa_home}/src/cudd" ]; then
    git clone --branch "${cudd_ref}" --depth 1 https://github.com/cuddorg/cudd.git "${ppa_home}/src/cudd"
  fi
  (
    cd "${ppa_home}/src/cudd"
    # Avoid regenerating the release Makefile with a host-specific automake.
    touch aclocal.m4 configure Makefile.in
    ./configure --prefix="${prefix}"
    make -j"${PPA_JOBS:-2}"
    make install
  )
fi

if [ ! -x "${ppa_home}/oss-cad/oss-cad-suite/bin/yosys" ]; then
  mkdir -p "${ppa_home}/oss-cad"
  curl -fL --retry 3 \
    --output "${ppa_home}/oss-cad/${oss_cad_archive}" \
    "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/${oss_cad_release}/${oss_cad_archive}"
  tar -xzf "${ppa_home}/oss-cad/${oss_cad_archive}" -C "${ppa_home}/oss-cad"
fi

if [ ! -d "${ppa_home}/src/OpenSTA" ]; then
  git clone --depth 1 https://github.com/parallaxsw/OpenSTA.git "${ppa_home}/src/OpenSTA"
fi
if [ ! -x "${prefix}/bin/sta" ]; then
  git -C "${ppa_home}/src/OpenSTA" fetch --depth 1 origin "${opensta_ref}"
  git -C "${ppa_home}/src/OpenSTA" checkout --detach "${opensta_ref}"
  cmake -S "${ppa_home}/src/OpenSTA" -B "${ppa_home}/build/opensta" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${prefix}" \
    -DCUDD_DIR="${prefix}"
  cmake --build "${ppa_home}/build/opensta" --parallel "${PPA_JOBS:-2}"
  cmake --install "${ppa_home}/build/opensta"
fi

if [ ! -s "${liberty_path}" ]; then
  curl -fL --retry 3 --output "${liberty_path}.tmp" "${liberty_url}"
  mv "${liberty_path}.tmp" "${liberty_path}"
fi

"${ppa_home}/oss-cad/oss-cad-suite/bin/yosys" -m slang -p "help read_slang" >/dev/null
"${prefix}/bin/sta" -version
echo "Using generic standard-cell Liberty: ${liberty_path}"
echo "Run: source tools/ppa/env.sh && make ppa-all"
