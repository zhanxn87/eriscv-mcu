# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

PYTHON ?= python3
SIM_BACKEND ?= verilator
LINT_PRODUCT ?= m2
LINT_TARGET ?= soc
M0_CORE_SMOKE_TESTS ?= --directed-only --act-smoke
M0_SOC_SMOKE_TESTS ?= MCU-C-01 MCU-BOOT-DATA-INIT-01 MCU-CLKRST-01 MCU-LP-WFI-TIMER-01 UART-HELLO-01 GPIO-BASIC-01 SPI-BASIC-01 TIMER-POLL-01 MCU-CLINT-MTIP-IRQ-01 MCU-PLIC-IRQ-01
M1_CORE_SMOKE_TESTS ?= --directed-only --act-smoke
M1_SOC_SMOKE_TESTS ?= MCU-C-01 MCU-BOOT-DATA-INIT-01 MCU-CLKRST-01 MCU-LP-WFI-TIMER-01 UART-HELLO-01 GPIO-BASIC-01 SPI-BASIC-01 TIMER-POLL-01 MCU-CLINT-MTIP-IRQ-01 MCU-PLIC-IRQ-01
M2_CORE_SMOKE_TESTS ?= --directed-only --act-smoke
M2_SOC_SMOKE_TESTS ?= MCU-C-01 MCU-TCM-UPPER-HALF-01 MCU-BOOT-DATA-INIT-01 MCU-CLKRST-01 MCU-LP-WFI-TIMER-01 UART-HELLO-01 GPIO-BASIC-01 SPI-BASIC-01 TIMER-POLL-01 MCU-CLINT-MTIP-IRQ-01 MCU-PLIC-IRQ-01

.PHONY: all help wizard lint lint-m0 lint-m1 lint-m2 lint-all copyright-check tb-contract \
	act-generate-m0 act-generate-m1 act-generate-m2 act-generate-all \
	act-generate-m0-container act-generate-m1-container act-generate-m2-container act-generate-all-container \
	act-bootstrap-native \
	eriscv-m0-core eriscv-m0-core-smoke eriscv-m0-soc eriscv-m0-soc-smoke eriscv-m0-act eriscv-m0-clk-rst eriscv-m0-tcm-arbitration eriscv-m0-openocd-gdb \
	eriscv-m1-core eriscv-m1-core-smoke eriscv-m1-soc eriscv-m1-soc-smoke eriscv-m1-act eriscv-m1-tcm-arbitration eriscv-m1-openocd-gdb \
	eriscv-m2-core eriscv-m2-core-smoke eriscv-m2-soc eriscv-m2-soc-smoke eriscv-m2-act eriscv-m2-tcm-arbitration eriscv-m2-dma-system-sram eriscv-m2-openocd-gdb \
	eriscv-m0-bsp eriscv-m0-bsp-async eriscv-m0-sw eriscv-m0-sw-async eriscv-m0-coremark eriscv-m0-dhrystone eriscv-m0-embench eriscv-m0-microbench eriscv-m0-freertos eriscv-m0-freertos-qualification eriscv-m0-zephyr \
	eriscv-m1-bsp eriscv-m1-bsp-async eriscv-m1-sw eriscv-m1-sw-async eriscv-m1-mcycle-counter eriscv-m1-coremark eriscv-m1-dhrystone eriscv-m1-embench eriscv-m1-microbench eriscv-m1-freertos eriscv-m1-freertos-qualification eriscv-m1-freertos-umode eriscv-m1-zephyr \
	eriscv-m2-bsp eriscv-m2-bsp-async eriscv-m2-bsp-fpu-dma-sram eriscv-m2-sw eriscv-m2-sw-async eriscv-m2-sw-fpu-dma-sram eriscv-m2-mcycle-counter eriscv-m2-coremark eriscv-m2-dhrystone eriscv-m2-embench eriscv-m2-microbench eriscv-m2-freertos eriscv-m2-freertos-qualification eriscv-m2-freertos-umode eriscv-m2-zephyr \
	eriscv-m0-full eriscv-m1-full eriscv-m2-full \
	eriscv-m0-smoke-no-act eriscv-m1-smoke-no-act eriscv-m2-smoke-no-act \
	eriscv-m0-full-no-act eriscv-m1-full-no-act eriscv-m2-full-no-act \
	eriscv-mcu-full clean clean-dry-run

all: help

wizard:
	$(PYTHON) tools/project/run_test_wizard.py

help:
	@echo "Static RTL checks:"

	@echo "  make lint-m0|lint-m1|lint-m2 [LINT_TARGET=core|soc] - run Verilator RTL lint for one product"
	@echo "  make lint-all                    - run Verilator SoC RTL lint for M0, M1, and M2"
	@echo "  make copyright-check              - verify SPDX headers on original source files"
	@echo ""
	@echo "ACT4 native environment (default; see README for setup):"
	@echo "  make act-bootstrap-native         - opt-in Debian/Ubuntu bootstrap; pass ACT_BOOTSTRAP_ARGS=--all"
	@echo "  make act-generate-m0|m1|m2       - generate a local cache with the installed native environment"
	@echo "  make act-generate-all             - generate M0, M1, and M2 caches serially"
	@echo ""
	@echo "ACT4 Docker fallback (isolated, larger first-run setup):"
	@echo "  make act-generate-m0-container   - build/use the pinned Docker environment and generate M0"
	@echo "  make act-generate-m1-container   - build/use the pinned Docker environment and generate M1"
	@echo "  make act-generate-m2-container   - build/use the pinned Docker environment and generate M2"
	@echo "  make act-generate-all-container  - generate M0, M1, and M2 caches serially in the shared image"
	@echo ""
	@echo "Regression:"
	@echo "  make eriscv-m0-core              - run the M0 core regression; skip unavailable ACT smoke with a warning"
	@echo "  make eriscv-m0-core-smoke        - run the eRISCV-M0 core smoke regression"
	@echo "  make eriscv-m0-soc               - run the eRISCV-M0 SoC regression"
	@echo "  make eriscv-m0-soc-smoke         - run the eRISCV-M0 SoC integration smoke regression"
	@echo "  make eriscv-m0-act               - run the eRISCV-M0 full ACT4 regression"
	@echo "  make eriscv-m1-core              - run the M1 core regression; skip unavailable ACT smoke with a warning"
	@echo "  make eriscv-m1-core-smoke        - run the eRISCV-M1 core smoke regression"
	@echo "  make eriscv-m1-soc               - run the eRISCV-M1 SoC regression"
	@echo "  make eriscv-m1-soc-smoke         - run the eRISCV-M1 SoC integration smoke regression"
	@echo "  make eriscv-m1-act               - run the eRISCV-M1 full ACT4 regression"
	@echo "  make eriscv-m2-core              - run the M2 core regression; skip unavailable ACT smoke with a warning"
	@echo "  make eriscv-m2-core-smoke        - run the eRISCV-M2 core smoke regression"
	@echo "  make eriscv-m2-soc               - run the eRISCV-M2 SoC regression"
	@echo "  make eriscv-m2-soc-smoke         - run the eRISCV-M2 SoC integration smoke regression"
	@echo "  make eriscv-m2-act               - run the eRISCV-M2 full ACT4 regression"
	@echo "  make eriscv-m0-full              - run M0 ACT-full + SoC; fall back to full no-ACT if cache is absent"
	@echo "  make eriscv-m1-full              - run M1 ACT-full + SoC; fall back to full no-ACT if cache is absent"
	@echo "  make eriscv-m2-full              - run M2 ACT-full + SoC; fall back to full no-ACT if cache is absent"
	@echo "  make eriscv-m0-smoke-no-act      - run directed/compliance-smoke core and SoC checks without ACT4"
	@echo "  make eriscv-m1-smoke-no-act      - run directed/compliance-smoke core and SoC checks without ACT4"
	@echo "  make eriscv-m2-smoke-no-act      - run directed/compliance-smoke core and SoC checks without ACT4"
	@echo "  make eriscv-m0-full-no-act       - run directed/compliance-full core and full SoC regression without ACT4"
	@echo "  make eriscv-m1-full-no-act       - run directed/compliance-full core and full SoC regression without ACT4"
	@echo "  make eriscv-m2-full-no-act       - run directed/compliance-full core and full SoC regression without ACT4"
	@echo "  make eriscv-mcu-full             - run M0, M1, and M2 full regressions"
	@echo ""
	@echo "Focused ModelSim diagnostics (not part of standard regression):"
	@echo "  make eriscv-m0-clk-rst           - run M0 clock/reset diagnostic"
	@echo "  make eriscv-m0-tcm-arbitration   - run M0 TCM arbitration diagnostic"
	@echo "  make eriscv-m1-tcm-arbitration   - run M1 TCM arbitration diagnostic"
	@echo "  make eriscv-m2-tcm-arbitration   - run M2 TCM arbitration diagnostic"
	@echo "  make eriscv-m2-dma-system-sram   - run M2 DMA/System-SRAM diagnostic"
	@echo ""
	@echo "Software and benchmarks:"
	@echo "  make eriscv-m0-bsp               - run the eRISCV-M0 BSP workload"
	@echo "  make eriscv-m0-bsp-async         - run the eRISCV-M0 async BSP workload"
	@echo "  make eriscv-m0-coremark          - build and run CoreMark on M0"
	@echo "  make eriscv-m0-dhrystone         - build and run Dhrystone on M0"
	@echo "  make eriscv-m0-embench           - build and run Embench-IoT on M0"
	@echo "  make eriscv-m0-microbench        - build and run M0 microbenchmarks"
	@echo "  make eriscv-m0-freertos          - build and run FreeRTOS on M0"
	@echo "  make eriscv-m0-freertos-qualification - run M0 FreeRTOS fail-stop qualification"
	@echo "  make eriscv-m0-zephyr            - build and run Zephyr on M0"
	@echo "  make eriscv-m1-bsp               - run the eRISCV-M1 BSP workload"
	@echo "  make eriscv-m1-bsp-async         - run the eRISCV-M1 async BSP workload"
	@echo "  make eriscv-m1-mcycle-counter    - run the eRISCV-M1 mcycle-counter workload"
	@echo "  make eriscv-m1-coremark          - build and run CoreMark on M1"
	@echo "  make eriscv-m1-dhrystone         - build and run Dhrystone on M1"
	@echo "  make eriscv-m1-embench           - build and run Embench-IoT on M1"
	@echo "  make eriscv-m1-microbench        - build and run M1 microbenchmarks"
	@echo "  make eriscv-m1-freertos          - build and run FreeRTOS on M1"
	@echo "  make eriscv-m1-freertos-qualification - run M1 FreeRTOS fail-stop qualification"
	@echo "  make eriscv-m1-freertos-umode    - build and run FreeRTOS U-mode on M1"
	@echo "  make eriscv-m1-zephyr            - build and run Zephyr on M1"
	@echo "  make eriscv-m2-bsp               - run the eRISCV-M2 BSP workload"
	@echo "  make eriscv-m2-bsp-async         - run the eRISCV-M2 async BSP workload"
	@echo "  make eriscv-m2-bsp-fpu-dma-sram  - run the eRISCV-M2 FPU/DMA/System-SRAM BSP workload"
	@echo "  make eriscv-m2-mcycle-counter    - run the eRISCV-M2 mcycle-counter workload"
	@echo "  make eriscv-m2-coremark          - build and run CoreMark on M2"
	@echo "  make eriscv-m2-dhrystone         - build and run Dhrystone on M2"
	@echo "  make eriscv-m2-embench           - build and run Embench-IoT on M2"
	@echo "  make eriscv-m2-microbench        - build and run M2 microbenchmarks"
	@echo "  make eriscv-m2-freertos          - build and run M2 FreeRTOS"
	@echo "  make eriscv-m2-freertos-qualification - run M2 FreeRTOS fail-stop qualification"
	@echo "  make eriscv-m2-freertos-umode    - build and run M2 FreeRTOS U-mode"
	@echo "  make eriscv-m2-zephyr            - build and run Zephyr on M2"
	@echo ""
	@echo "Simulation wizard:"
	@echo "  make wizard                      - interactively select and run simulation targets"
	@echo ""
	@echo "Board debug and maintenance:"
	@echo "  make eriscv-m0-openocd-gdb       - run board debug smoke (requires ADAPTER_CFG)"
	@echo "  make eriscv-m1-openocd-gdb       - run board debug smoke (requires ADAPTER_CFG)"
	@echo "  make eriscv-m2-openocd-gdb       - run board debug smoke (requires ADAPTER_CFG)"
	@echo "  make clean                         - remove all repository-generated simulation/script artifacts"
	@echo "  make clean-dry-run                 - list artifacts that make clean would remove"
	@echo ""
	@echo "  SIM_BACKEND=verilator|modelsim|auto selects the full-target simulator (default: verilator)"
	@echo ""
	@echo "Other:"
	@echo "  make tb-contract                 - check M0/M1 local-TB parity contract"

lint:
	$(PYTHON) tools/lint/run_eriscv_lint.py --product $(LINT_PRODUCT) --target $(LINT_TARGET)

lint-m0: LINT_PRODUCT = m0
lint-m0: lint

lint-m1: LINT_PRODUCT = m1
lint-m1: lint

lint-m2: LINT_PRODUCT = m2
lint-m2: lint

lint-all:
	$(PYTHON) tools/lint/run_eriscv_lint.py --all-products --target $(LINT_TARGET)

copyright-check:
	$(PYTHON) tools/project/check_spdx_headers.py

tb-contract:
	$(PYTHON) tools/project/check_m0_m1_tb_contract.py

act-generate-m0:
	tools/compliance/riscv-arch-test/generate_act4_cache.sh m0

act-generate-m1:
	tools/compliance/riscv-arch-test/generate_act4_cache.sh m1

act-generate-m2:
	tools/compliance/riscv-arch-test/generate_act4_cache.sh m2

act-generate-all:
	$(MAKE) act-generate-m0
	$(MAKE) act-generate-m1
	$(MAKE) act-generate-m2

act-generate-m0-container:
	tools/compliance/riscv-arch-test/run_act4_container.sh m0

act-generate-m1-container:
	tools/compliance/riscv-arch-test/run_act4_container.sh m1

act-generate-m2-container:
	tools/compliance/riscv-arch-test/run_act4_container.sh m2

act-generate-all-container:
	$(MAKE) act-generate-m0-container
	$(MAKE) act-generate-m1-container
	$(MAKE) act-generate-m2-container

act-bootstrap-native:
	tools/compliance/riscv-arch-test/bootstrap_act4_native.sh $(ACT_BOOTSTRAP_ARGS)

eriscv-m0-core:
	$(MAKE) -C eriscv-m0/dv/core/sim $(SIM_BACKEND)

eriscv-m0-core-smoke:
	$(MAKE) -C eriscv-m0/dv/core/sim $(SIM_BACKEND) TESTS="$(M0_CORE_SMOKE_TESTS)"

eriscv-m0-soc:
	$(MAKE) -C eriscv-m0/dv/soc/sim $(SIM_BACKEND)

eriscv-m0-soc-smoke:
	$(MAKE) -C eriscv-m0/dv/soc/sim $(SIM_BACKEND) TESTS="$(M0_SOC_SMOKE_TESTS)"

eriscv-m0-act:
	$(MAKE) -C eriscv-m0/dv/core/sim $(SIM_BACKEND) TESTS=--act-full

eriscv-m0-clk-rst:
	$(MAKE) -C eriscv-m0/dv/clk_rst/sim modelsim

eriscv-m0-tcm-arbitration:
	$(MAKE) -C eriscv-m0/dv/soc/sim tcm-arbitration

eriscv-m1-core:
	$(MAKE) -C eriscv-m1/dv/core/sim $(SIM_BACKEND)

eriscv-m1-core-smoke:
	$(MAKE) -C eriscv-m1/dv/core/sim $(SIM_BACKEND) TESTS="$(M1_CORE_SMOKE_TESTS)"

eriscv-m1-soc:
	$(MAKE) -C eriscv-m1/dv/soc/sim $(SIM_BACKEND)

eriscv-m1-soc-smoke:
	$(MAKE) -C eriscv-m1/dv/soc/sim $(SIM_BACKEND) TESTS="$(M1_SOC_SMOKE_TESTS)"

eriscv-m1-act:
	$(MAKE) -C eriscv-m1/dv/core/sim $(SIM_BACKEND) TESTS=--act-full

eriscv-m1-tcm-arbitration:
	$(MAKE) -C eriscv-m1/dv/soc/sim tcm-arbitration

eriscv-m2-core:
	$(MAKE) -C eriscv-m2/dv/core/sim $(SIM_BACKEND)

eriscv-m2-core-smoke:
	$(MAKE) -C eriscv-m2/dv/core/sim $(SIM_BACKEND) TESTS="$(M2_CORE_SMOKE_TESTS)"

eriscv-m2-soc:
	$(MAKE) -C eriscv-m2/dv/soc/sim $(SIM_BACKEND)

eriscv-m2-soc-smoke:
	$(MAKE) -C eriscv-m2/dv/soc/sim $(SIM_BACKEND) TESTS="$(M2_SOC_SMOKE_TESTS)"

eriscv-m2-act:
	$(MAKE) -C eriscv-m2/dv/core/sim $(SIM_BACKEND) TESTS=--act-full

eriscv-m2-tcm-arbitration:
	$(MAKE) -C eriscv-m2/dv/soc/sim tcm-arbitration

eriscv-m2-dma-system-sram:
	$(MAKE) -C eriscv-m2/dv/soc/sim dma-system-sram

eriscv-m0-openocd-gdb:
	ADAPTER_CFG="$(ADAPTER_CFG)" FIRMWARE_ELF="$(FIRMWARE_ELF)" eriscv-m0/dv/soc/openocd-gdb/scripts/run_smoke.sh

eriscv-m1-openocd-gdb:
	ADAPTER_CFG="$(ADAPTER_CFG)" FIRMWARE_ELF="$(FIRMWARE_ELF)" eriscv-m1/dv/soc/openocd-gdb/scripts/run_smoke.sh

eriscv-m2-openocd-gdb:
	ADAPTER_CFG="$(ADAPTER_CFG)" FIRMWARE_ELF="$(FIRMWARE_ELF)" eriscv-m2/dv/soc/openocd-gdb/scripts/run_smoke.sh

eriscv-m0-bsp:
	$(MAKE) -C eriscv-m0/sw sim

eriscv-m0-bsp-async:
	$(MAKE) -C eriscv-m0/sw sim-async

eriscv-m0-sw: eriscv-m0-bsp
eriscv-m0-sw-async: eriscv-m0-bsp-async

eriscv-m0-coremark:
	$(MAKE) -C eriscv-m0/sw coremark sim-coremark

eriscv-m0-dhrystone:
	$(MAKE) -C eriscv-m0/sw dhrystone sim-dhrystone

eriscv-m0-embench:
	$(MAKE) -C eriscv-m0/sw embench sim-embench

eriscv-m0-microbench:
	$(MAKE) -C eriscv-m0/sw microbench sim-microbench

eriscv-m0-freertos:
	$(MAKE) -C eriscv-m0/sw sim-freertos

eriscv-m0-freertos-qualification:
	$(MAKE) -C eriscv-m0/sw sim-freertos-qualification

eriscv-m0-zephyr:
	$(MAKE) -C eriscv-m0/sw zephyr sim-zephyr

eriscv-m1-bsp:
	$(MAKE) -C eriscv-m1/sw sim

eriscv-m1-bsp-async:
	$(MAKE) -C eriscv-m1/sw sim-async

eriscv-m1-sw: eriscv-m1-bsp
eriscv-m1-sw-async: eriscv-m1-bsp-async

eriscv-m1-mcycle-counter:
	$(MAKE) -C eriscv-m1/sw sim-mcycle-counter

eriscv-m1-coremark:
	$(MAKE) -C eriscv-m1/sw coremark sim-coremark

eriscv-m1-dhrystone:
	$(MAKE) -C eriscv-m1/sw dhrystone sim-dhrystone

eriscv-m1-embench:
	$(MAKE) -C eriscv-m1/sw embench sim-embench

eriscv-m1-microbench:
	$(MAKE) -C eriscv-m1/sw microbench sim-microbench

eriscv-m1-freertos:
	$(MAKE) -C eriscv-m1/sw sim-freertos

eriscv-m1-freertos-qualification:
	$(MAKE) -C eriscv-m1/sw sim-freertos-qualification

eriscv-m1-freertos-umode:
	$(MAKE) -C eriscv-m1/sw freertos-umode sim-freertos-umode

eriscv-m1-zephyr:
	$(MAKE) -C eriscv-m1/sw zephyr sim-zephyr

eriscv-m2-bsp:
	$(MAKE) -C eriscv-m2/sw SIM_BACKEND=$(SIM_BACKEND) sim

eriscv-m2-bsp-async:
	$(MAKE) -C eriscv-m2/sw SIM_BACKEND=$(SIM_BACKEND) sim-async

eriscv-m2-bsp-fpu-dma-sram:
	$(MAKE) -C eriscv-m2/sw SIM_BACKEND=$(SIM_BACKEND) sim-fpu-dma-sram

eriscv-m2-sw: eriscv-m2-bsp
eriscv-m2-sw-async: eriscv-m2-bsp-async
eriscv-m2-sw-fpu-dma-sram: eriscv-m2-bsp-fpu-dma-sram

eriscv-m2-mcycle-counter:
	$(MAKE) -C eriscv-m2/sw SIM_BACKEND=$(SIM_BACKEND) sim-mcycle-counter

eriscv-m2-coremark:
	$(MAKE) -C eriscv-m2/sw SIM_BACKEND=$(SIM_BACKEND) coremark sim-coremark

eriscv-m2-dhrystone:
	$(MAKE) -C eriscv-m2/sw SIM_BACKEND=$(SIM_BACKEND) dhrystone sim-dhrystone

eriscv-m2-embench:
	$(MAKE) -C eriscv-m2/sw SIM_BACKEND=$(SIM_BACKEND) embench sim-embench

eriscv-m2-microbench:
	$(MAKE) -C eriscv-m2/sw SIM_BACKEND=$(SIM_BACKEND) microbench sim-microbench

eriscv-m2-freertos:
	$(MAKE) -C eriscv-m2/sw SIM_BACKEND=$(SIM_BACKEND) sim-freertos

eriscv-m2-freertos-qualification:
	$(MAKE) -C eriscv-m2/sw SIM_BACKEND=$(SIM_BACKEND) sim-freertos-qualification

eriscv-m2-freertos-umode:
	$(MAKE) -C eriscv-m2/sw SIM_BACKEND=$(SIM_BACKEND) freertos-umode sim-freertos-umode

eriscv-m2-zephyr:
	$(MAKE) -C eriscv-m2/sw SIM_BACKEND=$(SIM_BACKEND) zephyr sim-zephyr

eriscv-m0-full:
	@if test -n "$$(find eriscv-m0/compliance/riscv-arch-test/generated -maxdepth 1 -name '*.mem' -type f -print -quit 2>/dev/null)"; then \
	  $(MAKE) -C eriscv-m0/dv/core/sim full BACKEND=$(SIM_BACKEND); \
	  $(MAKE) -C eriscv-m0/dv/soc/sim $(SIM_BACKEND); \
	else \
	  printf '\n*** ACT4 CACHE ABSENT: M0 full is running the full no-ACT baseline. ***\n'; \
	  printf '*** Generate ACT4 later with make act-generate-m0 or make act-generate-m0-container. ***\n\n'; \
	  $(MAKE) eriscv-m0-full-no-act; \
	fi

eriscv-m1-full:
	@if test -n "$$(find eriscv-m1/compliance/riscv-arch-test/generated -maxdepth 1 -name '*.mem' -type f -print -quit 2>/dev/null)"; then \
	  $(MAKE) -C eriscv-m1/dv/core/sim full BACKEND=$(SIM_BACKEND); \
	  $(MAKE) -C eriscv-m1/dv/soc/sim $(SIM_BACKEND); \
	else \
	  printf '\n*** ACT4 CACHE ABSENT: M1 full is running the full no-ACT baseline. ***\n'; \
	  printf '*** Generate ACT4 later with make act-generate-m1 or make act-generate-m1-container. ***\n\n'; \
	  $(MAKE) eriscv-m1-full-no-act; \
	fi

eriscv-m2-full:
	@if test -n "$$(find eriscv-m2/compliance/riscv-arch-test/generated -maxdepth 1 -name '*.mem' -type f -print -quit 2>/dev/null)"; then \
	  $(MAKE) -C eriscv-m2/dv/core/sim full BACKEND=$(SIM_BACKEND); \
	  $(MAKE) -C eriscv-m2/dv/soc/sim $(SIM_BACKEND); \
	else \
	  printf '\n*** ACT4 CACHE ABSENT: M2 full is running the full no-ACT baseline. ***\n'; \
	  printf '*** Generate ACT4 later with make act-generate-m2 or make act-generate-m2-container. ***\n\n'; \
	  $(MAKE) eriscv-m2-full-no-act; \
	fi

eriscv-m0-smoke-no-act:
	$(MAKE) -C eriscv-m0/dv/core/sim $(SIM_BACKEND) TESTS="--directed-only --compliance-smoke"
	$(MAKE) -C eriscv-m0/dv/soc/sim $(SIM_BACKEND) TESTS="$(M0_SOC_SMOKE_TESTS)"

eriscv-m1-smoke-no-act:
	$(MAKE) -C eriscv-m1/dv/core/sim $(SIM_BACKEND) TESTS="--directed-only --compliance-smoke"
	$(MAKE) -C eriscv-m1/dv/soc/sim $(SIM_BACKEND) TESTS="$(M1_SOC_SMOKE_TESTS)"

eriscv-m2-smoke-no-act:
	$(MAKE) -C eriscv-m2/dv/core/sim $(SIM_BACKEND) TESTS="--directed-only --compliance-smoke"
	$(MAKE) -C eriscv-m2/dv/soc/sim $(SIM_BACKEND) TESTS="$(M2_SOC_SMOKE_TESTS)"

eriscv-m0-full-no-act:
	$(MAKE) -C eriscv-m0/dv/core/sim $(SIM_BACKEND) TESTS="--directed-only --compliance-full"
	$(MAKE) -C eriscv-m0/dv/soc/sim $(SIM_BACKEND)

eriscv-m1-full-no-act:
	$(MAKE) -C eriscv-m1/dv/core/sim $(SIM_BACKEND) TESTS="--directed-only --compliance-full"
	$(MAKE) -C eriscv-m1/dv/soc/sim $(SIM_BACKEND)

eriscv-m2-full-no-act:
	$(MAKE) -C eriscv-m2/dv/core/sim $(SIM_BACKEND) TESTS="--directed-only --compliance-full"
	$(MAKE) -C eriscv-m2/dv/soc/sim $(SIM_BACKEND)

eriscv-mcu-full:
	$(MAKE) eriscv-m0-full
	$(MAKE) eriscv-m1-full
	$(MAKE) eriscv-m2-full

clean:
	$(PYTHON) tools/project/clean_work_artifacts.py

clean-dry-run:
	$(PYTHON) tools/project/clean_work_artifacts.py --dry-run
