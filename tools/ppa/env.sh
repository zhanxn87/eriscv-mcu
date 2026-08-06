#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

# Source after tools/ppa/setup_wsl.sh when using the repository-local toolchain.
_ppa_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PPA_HOME="${PPA_HOME:-${_ppa_root}/.cache/ppa}"
_oss_cad="${PPA_HOME}/oss-cad/oss-cad-suite"
_openroad="${PPA_HOME}/openroad-cli/bin"
if [ -d "${_oss_cad}" ]; then
  export PATH="${_oss_cad}/bin:${PPA_HOME}/prefix/bin:${_openroad}:${PATH}"
  unset YOSYS_DATDIR
else
  export PATH="${PPA_HOME}/prefix/bin:${PPA_HOME}/prefix/usr/bin:${_openroad}:${PATH}"
  if [ -d "${PPA_HOME}/prefix/share/yosys" ]; then
    export YOSYS_DATDIR="${PPA_HOME}/prefix/share/yosys"
  elif [ -d "${PPA_HOME}/prefix/usr/share/yosys" ]; then
    export YOSYS_DATDIR="${PPA_HOME}/prefix/usr/share/yosys"
  fi
fi
if [ -d "${PPA_HOME}/prefix/usr/lib/x86_64-linux-gnu" ]; then
  export LD_LIBRARY_PATH="${PPA_HOME}/prefix/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
fi
export PPA_LIBERTY="${PPA_LIBERTY:-${PPA_HOME}/liberty/NangateOpenCellLibrary_typical.lib}"
unset _openroad _oss_cad _ppa_root
