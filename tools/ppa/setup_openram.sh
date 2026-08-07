#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

# Initialize pinned OpenRAM Sky130 build-space under PPA_HOME.  Magic, Netgen,
# and ngspice are system tools and deliberately are not installed by this script.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ppa_home="${PPA_HOME:-${repo_root}/.cache/ppa}"
openram_root="${ppa_home}/src/OpenRAM"
sram_root="${ppa_home}/src/sky130_fd_bd_sram"
prebuilt_sram_root="${ppa_home}/src/sky130_sram_macros"
openram_ref="ed369f1af468110a230ffbde17e9159f2f021a4e"
sram_ref="dd64256961317205343a3fd446908b42bafba388"
prebuilt_sram_ref="41be8c50c969fc822daa84d9c0cb41baca815ced"

if [ -n "${PPA_SKY130_ROOT:-}" ]; then
  sky130_root="${PPA_SKY130_ROOT}"
else
  versions=("${ppa_home}"/pdks/volare/sky130/versions/*/sky130A)
  if [ "${#versions[@]}" -ne 1 ] || [ ! -d "${versions[0]}" ]; then
    echo "Sky130 PDK root is ambiguous or missing; set PPA_SKY130_ROOT" >&2
    exit 1
  fi
  sky130_root="${versions[0]}"
fi

if [ ! -d "${sky130_root}" ]; then
  echo "Sky130 PDK root not found: ${sky130_root}" >&2
  exit 1
fi

if [ ! -d "${openram_root}/.git" ]; then
  git clone https://github.com/VLSIDA/OpenRAM.git "${openram_root}"
fi
git -C "${openram_root}" fetch --depth 1 origin "${openram_ref}"
git -C "${openram_root}" checkout --detach "${openram_ref}"
python3 -m pip install --target "${ppa_home}/pydeps" -r "${openram_root}/requirements.txt"

if [ ! -d "${sram_root}/.git" ]; then
  git clone https://github.com/VLSIDA/sky130_fd_bd_sram.git "${sram_root}"
fi
git -C "${sram_root}" fetch --depth 1 origin "${sram_ref}"
git -C "${sram_root}" checkout --detach "${sram_ref}"

# This revision retains complete published 4 KiB Sky130 macro views.  Use it
# for physical PPA rather than regenerating the much larger 16 KiB macro.
if [ ! -d "${prebuilt_sram_root}/.git" ]; then
  git clone https://github.com/VLSIDA/sky130_sram_macros.git "${prebuilt_sram_root}"
fi
git -C "${prebuilt_sram_root}" fetch --depth 1 origin "${prebuilt_sram_ref}"
git -C "${prebuilt_sram_root}" checkout --detach "${prebuilt_sram_ref}"

# OpenRAM's installer expects historical per-cell SkyWater source paths.  The
# Volare PDK has equivalent consolidated standard-cell GDS/SPICE views, so
# expose the one required DFF cell through a small overlay.
overlay_root="${ppa_home}/openram-pdk"
mkdir -p "${overlay_root}/skywater-pdk/libraries/sky130_fd_sc_hd/latest/cells/dlxtn"
if [ ! -e "${overlay_root}/sky130A" ]; then
  ln -s "${sky130_root}" "${overlay_root}/sky130A"
fi
if [ ! -e "${overlay_root}/skywater-pdk/libraries/sky130_fd_sc_hd/latest/cells/dlxtn/sky130_fd_sc_hd__dlxtn_1.gds" ]; then
  ln -s "${sky130_root}/libs.ref/sky130_fd_sc_hd/gds/sky130_fd_sc_hd.gds" \
    "${overlay_root}/skywater-pdk/libraries/sky130_fd_sc_hd/latest/cells/dlxtn/sky130_fd_sc_hd__dlxtn_1.gds"
fi
if [ ! -e "${overlay_root}/skywater-pdk/libraries/sky130_fd_sc_hd/latest/cells/dlxtn/sky130_fd_sc_hd__dlxtn_1.spice" ]; then
  ln -s "${sky130_root}/libs.ref/sky130_fd_sc_hd/spice/sky130_fd_sc_hd.spice" \
    "${overlay_root}/skywater-pdk/libraries/sky130_fd_sc_hd/latest/cells/dlxtn/sky130_fd_sc_hd__dlxtn_1.spice"
fi

make -C "${openram_root}" PDK_ROOT="${overlay_root}" SRAM_LIB_DIR="${sram_root}" sky130-install
echo "OpenRAM initialized with published 4 KiB SRAM macro views. Install Magic + Netgen before verified custom macro generation."
