# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

.DEFAULT_GOAL := modelsim

.PHONY: all help modelsim

all: modelsim

help:
	@echo "eRISCV-M0 clock/reset ModelSim regression"
	@echo "  make  or  make modelsim"

modelsim:
	vsim -c -do run_sim.do
