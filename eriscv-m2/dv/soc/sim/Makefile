# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

PYTHON ?= python3
TESTS ?=
FILELIST_RESOLVER = ../../../../tools/project/resolve_filelist.py

.DEFAULT_GOAL := verilator

.PHONY: all help filelist check-filelist list verilator modelsim auto tcm-arbitration dma-system-sram dma-uart-tx clean

all: verilator

help:
	@echo "eRISCV-M2 SoC simulation"
	@echo
	@echo "Inspect:"
	@echo "  make filelist"
	@echo "  make check-filelist"
	@echo "  make list"
	@echo
	@echo "Build and run:"
	@echo "  make                         (Verilator directed regression)"
	@echo "  make modelsim [TESTS=SOC-SMOKE-01]"
	@echo "  make tcm-arbitration"
	@echo "  make dma-system-sram"
	@echo "  make verilator [TESTS=SOC-SMOKE-01]"
	@echo "  make auto      [TESTS=SOC-SMOKE-01]"
	@echo "  make clean  (remove the incremental Verilator cache)"

filelist:
	$(PYTHON) $(FILELIST_RESOLVER) filelist.f --output file.list

check-filelist:
	$(PYTHON) $(FILELIST_RESOLVER) filelist.f --check

list: filelist
	$(PYTHON) run_regression.py --list-tests

verilator:
	$(PYTHON) run_regression.py --backend verilator $(TESTS)

modelsim:
	$(PYTHON) run_regression.py --backend modelsim $(TESTS)

auto:
	$(PYTHON) run_regression.py --backend auto $(TESTS)

tcm-arbitration: filelist
	vsim -c -do run_tcm_arbitration.do

dma-system-sram: filelist
	vsim -c -do run_dma_system_sram.do

dma-uart-tx: filelist
	vsim -c -do run_dma_uart_tx.do

clean:
	rm -rf obj_dir regression_logs visual_waves waves work transcript *.log .modelsim_work_cache.json
