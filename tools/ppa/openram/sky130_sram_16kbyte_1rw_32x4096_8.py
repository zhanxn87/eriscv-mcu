# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""OpenRAM configuration for one eRISCV M0 16 KiB SRAM bank."""

import os


word_size = 32
num_words = 4096
write_size = 8
num_rw_ports = 1
num_r_ports = 0
num_w_ports = 0
# One physical 16 KiB macro.  The SoC memory wrapper composes four of these
# macros per 64 KiB TCM; do not add an internal OpenRAM bank hierarchy here.
num_banks = 1
num_spare_rows = 1
num_spare_cols = 1
tech_name = "sky130"

# Keep PPA runs self-contained and use the locally installed toolchain.
use_nix = False
nominal_corner_only = True
route_supplies = "ring"
perimeter_pins = True
analytical_delay = True
check_lvsdrc = os.environ.get("ERISCV_OPENRAM_CHECK_LVSDRC", "1") == "1"

output_name = "eriscv_sram_16kbyte_1rw_32x4096_8"
output_path = os.path.join(os.environ["ERISCV_OPENRAM_OUTPUT"], "")
