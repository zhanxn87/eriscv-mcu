# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

PYTHON ?= python3
BROWSER ?= firefox
BACKEND ?= verilator
TESTS ?=
MODELSIM_GUI_TEST ?=
WAVE ?= $(shell find visual_waves waves -maxdepth 1 -type f \( -name '*.fst' -o -name '*.vcd' -o -name '*.ghw' \) -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
FULL_TESTS ?= --directed-only --act-full
SMOKE_TESTS ?= --directed-only --compliance-smoke --act-smoke
REGRESSION_FLAGS = $(if $(filter full,$(MAKECMDGOALS)),$(FULL_TESTS),$(if $(filter smoke,$(MAKECMDGOALS)),$(SMOKE_TESTS),$(TESTS)))

FILELIST_RESOLVER = ../../../../tools/project/resolve_filelist.py

.DEFAULT_GOAL := verilator

.PHONY: all help filelist check-filelist list verilator modelsim modelsim-gui auto wave visual surfer full smoke bht-predictor clean

all: verilator

help:
	@echo "eRISCV-M2 simulation shortcuts"
	@echo
	@echo "Inspect:"
	@echo "  make filelist"
	@echo "  make check-filelist"
	@echo "  make list"
	@echo
	@echo "Run regressions:"
	@echo "  make                         (Verilator directed + smoke regression)"
	@echo "  make modelsim [TESTS=P1-ALU-01]  (focused batch debug)"
	@echo "  make modelsim-gui MODELSIM_GUI_TEST=P1-ALU-01"
	@echo "  make full [BACKEND=verilator]"
	@echo "  make smoke"
	@echo "  make verilator [TESTS=P1-ALU-01]"
	@echo "  make auto      [TESTS=P1-ALU-01]"
	@echo "  make bht-predictor              (focused 64-entry BHT unit test)"
	@echo
	@echo "Clean:"
	@echo "  make clean"

filelist:
	$(PYTHON) $(FILELIST_RESOLVER) filelist.f --output file.list

check-filelist:
	$(PYTHON) $(FILELIST_RESOLVER) filelist.f --check

list: filelist
	$(PYTHON) run_regression.py --list-tests

full:
	$(MAKE) $(BACKEND) TESTS="$(FULL_TESTS)"

smoke:
	$(MAKE) $(BACKEND) TESTS="$(SMOKE_TESTS)"

verilator:
	$(PYTHON) run_regression.py --backend verilator $(REGRESSION_FLAGS)

modelsim:
	$(PYTHON) run_regression.py --backend modelsim $(REGRESSION_FLAGS)

modelsim-gui:
	@test -n "$(MODELSIM_GUI_TEST)" || (echo "Set MODELSIM_GUI_TEST=<directed testcase>"; exit 2)
	$(PYTHON) run_regression.py --modelsim-gui-test "$(MODELSIM_GUI_TEST)"

auto:
	$(PYTHON) run_regression.py --backend auto $(REGRESSION_FLAGS)

bht-predictor:
	rm -rf obj_dir_bht
	verilator --binary --timing --Wno-TIMESCALEMOD --top-module branch_predictor_tb ../../../rtl/riscv_core/return_address_stack.sv ../../../rtl/riscv_core/branch_predictor.sv ../tb/branch_predictor_tb.sv --Mdir obj_dir_bht
	./obj_dir_bht/Vbranch_predictor_tb

wave:
	$(PYTHON) run_regression.py --backend verilator --wave --dump-format fst --wave-dir visual_waves $(TESTS)

visual:
	$(PYTHON) ../../../../tools/sim/run_visual_phase.py --sim-dir . $(TESTS)

clean:
	rm -rf obj_dir regression_logs visual_waves waves work transcript *.log .modelsim_work_cache.json
