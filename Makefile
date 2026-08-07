# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

PYTHON ?= python3
SIM_BACKEND ?= verilator
LINT_PRODUCT ?= m2
LINT_TARGET ?= soc
ACT_SMOKE_PHASE ?= compliance/riscv-arch-test/ci-smoke
M0_CORE_SMOKE_TESTS ?= --directed-only --compliance-smoke
M0_ACT_SMOKE_TESTS ?= --act-smoke
M0_SOC_SMOKE_TESTS ?= MCU-C-01 MCU-BOOT-DATA-INIT-01 MCU-CLKRST-01 MCU-LP-WFI-TIMER-01 UART-HELLO-01 GPIO-BASIC-01 SPI-BASIC-01 TIMER-POLL-01 MCU-CLINT-MTIP-IRQ-01 MCU-PLIC-IRQ-01
M1_CORE_SMOKE_TESTS ?= --directed-only --compliance-smoke
M1_ACT_SMOKE_TESTS ?= --act-smoke
M1_SOC_SMOKE_TESTS ?= MCU-C-01 MCU-BOOT-DATA-INIT-01 MCU-CLKRST-01 MCU-LP-WFI-TIMER-01 UART-HELLO-01 GPIO-BASIC-01 SPI-BASIC-01 TIMER-POLL-01 MCU-CLINT-MTIP-IRQ-01 MCU-PLIC-IRQ-01
M2_CORE_SMOKE_TESTS ?= --directed-only --compliance-smoke
M2_ACT_SMOKE_TESTS ?= --act-smoke
M2_SOC_SMOKE_TESTS ?= MCU-C-01 MCU-TCM-UPPER-HALF-01 MCU-BOOT-DATA-INIT-01 MCU-CLKRST-01 MCU-LP-WFI-TIMER-01 UART-HELLO-01 GPIO-BASIC-01 SPI-BASIC-01 TIMER-POLL-01 MCU-CLINT-MTIP-IRQ-01 MCU-PLIC-IRQ-01
PPA_PERIOD_NS ?= 10.0
PPA_LIBERTY ?=
PPA_OUT_DIR ?= build/ppa
PPA_OPENROAD_PERIOD_NS ?= 20.0
PPA_OPENROAD_UTILIZATION ?= 30.0
PPA_OPENROAD_SRAM_UTILIZATION ?= 35.0
PPA_OPENROAD_SRAM_CHANNEL_UM ?= 40.0
PPA_OPENROAD_SRAM_ROUTE_ITERATIONS ?= 20
PPA_OPENROAD_OUT_DIR ?= build/ppa-openroad
PPA_OPENRAM_MACRO_DIR ?= $(CURDIR)/.cache/ppa/openram/eriscv_sram_16kbyte_1rw_32x4096_8
PPA_PREBUILT_SRAM4K_MACRO_DIR ?= $(CURDIR)/.cache/ppa/src/sky130_sram_macros/sky130_sram_4kbyte_1rw1r_32x1024_8
PPA_OPENRAM_ARGS ?=
EMBENCH_BENCH ?= matmult-int
EMBENCH_PROFILE ?= speed
EMBENCH_SCALE ?= 1

.PHONY: all help check smoke act-smoke wizard lint lint-m0 lint-m1 lint-m2 lint-all copyright-check tb-contract \
	act-generate-m0 act-generate-m1 act-generate-m2 act-generate-all \
	act-generate-m0-container act-generate-m1-container act-generate-m2-container act-generate-all-container \
	act-bootstrap-native \
	eriscv-m0-core eriscv-m0-core-smoke eriscv-m0-soc eriscv-m0-soc-smoke eriscv-m0-act eriscv-m0-clk-rst eriscv-m0-tcm-arbitration eriscv-m0-openocd-gdb \
	eriscv-m0-act-smoke eriscv-m0-smoke \
	eriscv-m1-core eriscv-m1-core-smoke eriscv-m1-soc eriscv-m1-soc-smoke eriscv-m1-act eriscv-m1-tcm-arbitration eriscv-m1-openocd-gdb \
	eriscv-m1-act-smoke eriscv-m1-smoke \
	eriscv-m2-core eriscv-m2-core-smoke eriscv-m2-soc eriscv-m2-soc-smoke eriscv-m2-act eriscv-m2-tcm-arbitration eriscv-m2-dma-system-sram eriscv-m2-openocd-gdb \
	eriscv-m2-act-smoke eriscv-m2-smoke \
	eriscv-m0-bsp eriscv-m0-bsp-async eriscv-m0-sw eriscv-m0-sw-async eriscv-m0-coremark eriscv-m0-dhrystone eriscv-m0-embench eriscv-m0-microbench eriscv-m0-freertos eriscv-m0-freertos-qualification eriscv-m0-zephyr \
	eriscv-m1-bsp eriscv-m1-bsp-async eriscv-m1-sw eriscv-m1-sw-async eriscv-m1-mcycle-counter eriscv-m1-coremark eriscv-m1-dhrystone eriscv-m1-embench eriscv-m1-microbench eriscv-m1-freertos eriscv-m1-freertos-qualification eriscv-m1-freertos-umode eriscv-m1-zephyr \
	eriscv-m2-bsp eriscv-m2-bsp-async eriscv-m2-bsp-fpu-dma-sram eriscv-m2-sw eriscv-m2-sw-async eriscv-m2-sw-fpu-dma-sram eriscv-m2-mcycle-counter eriscv-m2-coremark eriscv-m2-dhrystone eriscv-m2-embench eriscv-m2-microbench eriscv-m2-freertos eriscv-m2-freertos-qualification eriscv-m2-freertos-umode eriscv-m2-zephyr \
	eriscv-m0-full eriscv-m1-full eriscv-m2-full \
	eriscv-m0-full-no-act eriscv-m1-full-no-act eriscv-m2-full-no-act \
	eriscv-mcu-full ppa-m0 ppa-m1 ppa-m2 ppa-all ppa-openroad-m0 ppa-openroad-m1 ppa-openroad-m2 ppa-openroad-m0-sram ppa-openroad-m0-sram-close ppa-openroad-m0-sram-fast ppa-openroad-m0-openram ppa-openroad-view-m0 ppa-openroad-view-m0-sram ppa-openroad-view-m1 ppa-openroad-view-m2 ppa-openram-setup ppa-openram-m0 ppa-setup ppa-setup-wsl clean clean-dry-run

all: help

# Recommended entry points. Product-specific targets remain available below.
check: copyright-check tb-contract lint-all

act-smoke: eriscv-m0-act-smoke eriscv-m1-act-smoke eriscv-m2-act-smoke

smoke: eriscv-m0-smoke eriscv-m1-smoke eriscv-m2-smoke

wizard:
	$(PYTHON) tools/project/run_test_wizard.py

help:
	@echo "eRISCV-MCU top-level commands (replace m0 with m1 or m2 where shown):"
	@echo ""
	@echo "Checks and lint:"
	@echo "  make check                       - SPDX, TB contracts, and M0/M1/M2 RTL lint at selected boundary"
	@echo "  make lint-all                    - lint M0/M1/M2 (LINT_TARGET=core or soc)"
	@echo "  make lint-m0                     - lint M0 (replace m0 with m1 or m2)"
	@echo "  make copyright-check             - check original-source SPDX headers"
	@echo "  make tb-contract                 - check M0/M1 testbench contracts"
	@echo ""
	@echo "RTL regressions:"
	@echo "  make smoke                       - core + SoC + ci-smoke ACT4, all products"
	@echo "  make act-smoke                   - ci-smoke ACT4 only, all products"
	@echo "  make eriscv-m0-smoke             - one-product core + SoC + ci-smoke ACT4"
	@echo "  make eriscv-m0-act-smoke         - one-product ci-smoke ACT4 only"
	@echo "  make eriscv-m0-core-smoke        - directed core tests plus any configured compliance smoke (no ACT4)"
	@echo "  make eriscv-m0-soc-smoke         - one-product SoC integration smoke"
	@echo "  make eriscv-m0-core              - default core regression; skip ACT4 smoke if cache is missing/incomplete"
	@echo "  make eriscv-m0-soc               - default SoC directed regression (replace m0 with m1 or m2)"
	@echo "  make eriscv-m0-act               - one-product full ACT4 core regression"
	@echo "  make eriscv-m0-full              - full directed core + ACT4 + SoC when cache exists; no-ACT baseline otherwise"
	@echo "  make eriscv-m0-full-no-act       - full directed/compliance core + SoC, no generated ACT4"
	@echo "  make eriscv-mcu-full             - full M0/M1/M2; each uses ACT4 if its generated cache exists, else no-ACT"
	@echo ""
	@echo "ACT4 generation:"
	@echo "  make act-bootstrap-native ACT_BOOTSTRAP_ARGS='--system-packages --mise --sail' - install selected native prerequisites"
	@echo "  make act-generate-m0             - generate M0 ACT4 cache on host (replace m0 with m1 or m2)"
	@echo "  make act-generate-all            - generate M0/M1/M2 ACT4 caches on host"
	@echo "  make act-generate-m0-container   - generate M0 ACT4 cache in container (replace m0 with m1 or m2)"
	@echo "  make act-generate-all-container  - generate all ACT4 caches in containers"
	@echo ""
	@echo "Software and performance:"
	@echo "  make eriscv-m0-bsp               - build/run M0 BSP hello-UART simulation"
	@echo "  make eriscv-m0-bsp-async         - build/run M0 asynchronous-UART BSP simulation"
	@echo "  make eriscv-m0-sw                - alias of the M0 BSP simulation"
	@echo "  make eriscv-m0-sw-async          - alias of the M0 asynchronous BSP simulation"
	@echo "  make eriscv-m0-coremark          - build/run M0 CoreMark"
	@echo "  make eriscv-m0-dhrystone         - build/run M0 Dhrystone"
	@echo "  make eriscv-m0-embench           - build/run M0 Embench (default matmult-int/speed/1)"
	@echo "  make eriscv-m0-microbench        - build/run M0 microbenchmarks"
	@echo "  make eriscv-m0-freertos          - build/run M0 FreeRTOS"
	@echo "  make eriscv-m0-freertos-qualification - M0 FreeRTOS fail-stop qualification"
	@echo "  make eriscv-m0-zephyr            - build/run M0 Zephyr"
	@echo "  eriscv-m1-* and eriscv-m2-*       - corresponding M1/M2 software targets"
	@echo "  M1 extras: eriscv-m1-mcycle-counter, eriscv-m1-freertos-umode"
	@echo "  M2 extras: eriscv-m2-mcycle-counter, eriscv-m2-bsp-fpu-dma-sram"
	@echo "              eriscv-m2-sw-fpu-dma-sram, eriscv-m2-freertos-umode"
	@echo ""
	@echo "PPA (generic Liberty; no PDK, OpenLane, or P&R):"
	@echo "  1) make ppa-setup                 - first-time Linux/WSL toolchain setup"
	@echo "  2) source tools/ppa/env.sh         - load the local Yosys/OpenSTA environment"
	@echo "  3) make ppa-m0                    - evaluate M0 (use ppa-m1/ppa-m2 for others)"
	@echo "     make ppa-all                   - evaluate M0, M1, and M2"
	@echo "  One-line example: source tools/ppa/env.sh && make ppa-m0"
	@echo "  Example override: source tools/ppa/env.sh && make ppa-m1 PPA_PERIOD_NS=5 PPA_OUT_DIR=build/ppa-fast"
	@echo "  Overrides: PPA_PERIOD_NS=<ns> PPA_LIBERTY=<file> PPA_OUT_DIR=<dir>"
	@echo "  SDC: tools/ppa/constraints.sdc (clock/reset/IO, generated-clock, load/transition/fanout)"
	@echo "       defaults: sys_clk 10ns, jtag 100ns, IO delay 20%, setup uncertainty 5%, hold 0.10ns"
	@echo "  make ppa-openroad-m0/m1/m2       - local Sky130/OpenROAD placement/CTS/global-route estimate"
	@echo "       needs local Sky130 PDK; set PPA_SKY130_ROOT if auto-discovery is ambiguous"
	@echo "       defaults: 20ns (50MHz), 30% initial core utilization"
	@echo "       overrides: PPA_OPENROAD_PERIOD_NS=<ns> PPA_OPENROAD_UTILIZATION=<pct> PPA_OPENROAD_OUT_DIR=<dir>"
	@echo "  make ppa-openram-setup           - install pinned OpenRAM + Sky130 SRAM build-space under PPA_HOME"
	@echo "  make ppa-openram-m0              - generate the M0 16 KiB x32, 1RW OpenRAM bank (Magic/Netgen verified)"
	@echo "  make ppa-openroad-m0-sram        - M0 global/detailed-route P&R with 32 published 4 KiB Sky130 SRAM macros"
	@echo "       defaults: 35% macro floorplan utilization and 40um channels; overrides: PPA_OPENROAD_SRAM_UTILIZATION=<pct> PPA_OPENROAD_SRAM_CHANNEL_UM=<um>"
	@echo "       default: 20 global-route iterations/pass; override: PPA_OPENROAD_SRAM_ROUTE_ITERATIONS=<count>"
	@echo "  make ppa-openroad-m0-sram-close  - add post-route setup/hold repair and two re-route passes"
	@echo "       run ppa-openram-setup once to cache the published macro views under PPA_HOME"
	@echo "  make ppa-openroad-m0-sram-fast   - M0 macro placement/CTS fast estimate (no routing)"
	@echo "  make ppa-openroad-m0-openram     - M0 physical PPA with eight placed OpenRAM banks (IMEM + DMEM)"
	@echo "       preliminary only: PPA_OPENRAM_ARGS=--skip-verification; this does not waive later macro DRC/LVS"
	@echo "  make ppa-openroad-view-m0/m1/m2  - open the latest product DEF in KLayout using Sky130 LEF geometry"
	@echo "  make ppa-openroad-view-m0-sram   - open the 32-macro M0 DEF in KLayout"
	@echo ""
	@echo "Debug and focused platform tests:"
	@echo "  make eriscv-m0-openocd-gdb       - M0 OpenOCD/GDB smoke; ADAPTER_CFG required, FIRMWARE_ELF optional"
	@echo "  make eriscv-m0-clk-rst           - M0 clock/reset ModelSim diagnostic"
	@echo "  make eriscv-m0-tcm-arbitration   - M0 TCM arbitration ModelSim test (replace m0 with m1 or m2)"
	@echo "  make eriscv-m2-dma-system-sram   - M2 DMA/System SRAM ModelSim test"
	@echo "  make wizard                      - interactive simulation selector"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean-dry-run               - list generated artifacts to remove"
	@echo "  make clean                       - remove generated sim/ACT4 caches; leave source, ci-smoke vectors, PPA cache"
	@echo ""
	@echo "Common options:"
	@echo "  SIM_BACKEND=<value>              one of: verilator, modelsim, auto"
	@echo "  ACT_SMOKE_PHASE=<path>           ACT4 smoke vector dir; default: compliance/riscv-arch-test/ci-smoke"
	@echo "  ACT_BOOTSTRAP_ARGS=<args>        (native ACT4 bootstrap options)"
	@echo "  LINT_PRODUCT=<value> LINT_TARGET=<value>  product m0/m1/m2; boundary core/soc"
	@echo "  M0_CORE_SMOKE_TESTS=<list> M0_ACT_SMOKE_TESTS=<list> (M1/M2 equivalents)"
	@echo "  EMBENCH_BENCH=<name> EMBENCH_PROFILE=<value> EMBENCH_SCALE=<n>  profile speed/size"
	@echo ""
	@echo "Use 'make -qp' for the complete compatibility target database."

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

ppa-setup:
	tools/ppa/setup_wsl.sh

ppa-setup-wsl: ppa-setup

ppa-m0:
	$(PYTHON) tools/ppa/run_ppa.py --product m0 --period-ns $(PPA_PERIOD_NS) --liberty "$(PPA_LIBERTY)" --output-dir "$(PPA_OUT_DIR)/m0"

ppa-m1:
	$(PYTHON) tools/ppa/run_ppa.py --product m1 --period-ns $(PPA_PERIOD_NS) --liberty "$(PPA_LIBERTY)" --output-dir "$(PPA_OUT_DIR)/m1"

ppa-m2:
	$(PYTHON) tools/ppa/run_ppa.py --product m2 --period-ns $(PPA_PERIOD_NS) --liberty "$(PPA_LIBERTY)" --output-dir "$(PPA_OUT_DIR)/m2"

ppa-all:
	$(MAKE) ppa-m0
	$(MAKE) ppa-m1
	$(MAKE) ppa-m2

ppa-openroad-m0:
	$(PYTHON) tools/ppa/run_openroad.py --product m0 --period-ns $(PPA_OPENROAD_PERIOD_NS) --utilization $(PPA_OPENROAD_UTILIZATION) --output-dir "$(PPA_OPENROAD_OUT_DIR)/m0"

ppa-openroad-m1:
	$(PYTHON) tools/ppa/run_openroad.py --product m1 --period-ns $(PPA_OPENROAD_PERIOD_NS) --utilization $(PPA_OPENROAD_UTILIZATION) --output-dir "$(PPA_OPENROAD_OUT_DIR)/m1"

ppa-openroad-m2:
	$(PYTHON) tools/ppa/run_openroad.py --product m2 --period-ns $(PPA_OPENROAD_PERIOD_NS) --utilization $(PPA_OPENROAD_UTILIZATION) --output-dir "$(PPA_OPENROAD_OUT_DIR)/m2"

ppa-openroad-m0-sram:
	$(PYTHON) tools/ppa/run_openroad.py --product m0 --period-ns $(PPA_OPENROAD_PERIOD_NS) --utilization $(PPA_OPENROAD_SRAM_UTILIZATION) --macro-channel-um $(PPA_OPENROAD_SRAM_CHANNEL_UM) --route-mode full --route-repair none --global-route-iterations $(PPA_OPENROAD_SRAM_ROUTE_ITERATIONS) --sram-profile prebuilt4k --sram-macro-dir "$(PPA_PREBUILT_SRAM4K_MACRO_DIR)" --output-dir "$(PPA_OPENROAD_OUT_DIR)/m0-sram"

ppa-openroad-m0-sram-close:
	$(PYTHON) tools/ppa/run_openroad.py --product m0 --period-ns $(PPA_OPENROAD_PERIOD_NS) --utilization $(PPA_OPENROAD_SRAM_UTILIZATION) --macro-channel-um $(PPA_OPENROAD_SRAM_CHANNEL_UM) --route-mode full --route-repair full --global-route-iterations $(PPA_OPENROAD_SRAM_ROUTE_ITERATIONS) --sram-profile prebuilt4k --sram-macro-dir "$(PPA_PREBUILT_SRAM4K_MACRO_DIR)" --output-dir "$(PPA_OPENROAD_OUT_DIR)/m0-sram-close"

ppa-openroad-m0-sram-fast:
	$(PYTHON) tools/ppa/run_openroad.py --product m0 --period-ns $(PPA_OPENROAD_PERIOD_NS) --utilization $(PPA_OPENROAD_SRAM_UTILIZATION) --macro-channel-um $(PPA_OPENROAD_SRAM_CHANNEL_UM) --route-mode post-cts --sram-profile prebuilt4k --sram-macro-dir "$(PPA_PREBUILT_SRAM4K_MACRO_DIR)" --output-dir "$(PPA_OPENROAD_OUT_DIR)/m0-sram-fast"

ppa-openram-setup:
	tools/ppa/setup_openram.sh

ppa-openram-m0:
	$(PYTHON) tools/ppa/run_openram.py --output-dir "$(PPA_OPENRAM_MACRO_DIR)" $(PPA_OPENRAM_ARGS)

ppa-openroad-m0-openram: ppa-openram-m0
	$(PYTHON) tools/ppa/run_openroad.py --product m0 --period-ns $(PPA_OPENROAD_PERIOD_NS) --utilization $(PPA_OPENROAD_UTILIZATION) --sram-macro-dir "$(PPA_OPENRAM_MACRO_DIR)" --output-dir "$(PPA_OPENROAD_OUT_DIR)/m0-openram"

ppa-openroad-view-m0:
	klayout -rr tools/ppa/view_openroad_def.rb -rd input_def="$(PPA_OPENROAD_OUT_DIR)/m0/soc.def"

ppa-openroad-view-m0-sram:
	klayout -rr tools/ppa/view_openroad_def.rb -rd input_def="$(PPA_OPENROAD_OUT_DIR)/m0-sram/soc.def"

ppa-openroad-view-m1:
	klayout -rr tools/ppa/view_openroad_def.rb -rd input_def="$(PPA_OPENROAD_OUT_DIR)/m1/soc.def"

ppa-openroad-view-m2:
	klayout -rr tools/ppa/view_openroad_def.rb -rd input_def="$(PPA_OPENROAD_OUT_DIR)/m2/soc.def"

eriscv-m0-core:
	$(MAKE) -C eriscv-m0/dv/core/sim $(SIM_BACKEND)

eriscv-m0-core-smoke:
	$(MAKE) -C eriscv-m0/dv/core/sim $(SIM_BACKEND) TESTS="$(M0_CORE_SMOKE_TESTS)"

eriscv-m0-act-smoke:
	ERISCV_ACT_PHASE="$(ACT_SMOKE_PHASE)" $(MAKE) -C eriscv-m0/dv/core/sim $(SIM_BACKEND) TESTS="$(M0_ACT_SMOKE_TESTS)"

eriscv-m0-soc:
	$(MAKE) -C eriscv-m0/dv/soc/sim $(SIM_BACKEND)

eriscv-m0-soc-smoke:
	$(MAKE) -C eriscv-m0/dv/soc/sim $(SIM_BACKEND) TESTS="$(M0_SOC_SMOKE_TESTS)"

eriscv-m0-act:
	$(MAKE) -C eriscv-m0/dv/core/sim $(SIM_BACKEND) TESTS=--act-full

eriscv-m0-smoke: eriscv-m0-core-smoke eriscv-m0-soc-smoke eriscv-m0-act-smoke

eriscv-m0-clk-rst:
	$(MAKE) -C eriscv-m0/dv/clk_rst/sim modelsim

eriscv-m0-tcm-arbitration:
	$(MAKE) -C eriscv-m0/dv/soc/sim tcm-arbitration

eriscv-m1-core:
	$(MAKE) -C eriscv-m1/dv/core/sim $(SIM_BACKEND)

eriscv-m1-core-smoke:
	$(MAKE) -C eriscv-m1/dv/core/sim $(SIM_BACKEND) TESTS="$(M1_CORE_SMOKE_TESTS)"

eriscv-m1-act-smoke:
	ERISCV_ACT_PHASE="$(ACT_SMOKE_PHASE)" $(MAKE) -C eriscv-m1/dv/core/sim $(SIM_BACKEND) TESTS="$(M1_ACT_SMOKE_TESTS)"

eriscv-m1-soc:
	$(MAKE) -C eriscv-m1/dv/soc/sim $(SIM_BACKEND)

eriscv-m1-soc-smoke:
	$(MAKE) -C eriscv-m1/dv/soc/sim $(SIM_BACKEND) TESTS="$(M1_SOC_SMOKE_TESTS)"

eriscv-m1-act:
	$(MAKE) -C eriscv-m1/dv/core/sim $(SIM_BACKEND) TESTS=--act-full

eriscv-m1-smoke: eriscv-m1-core-smoke eriscv-m1-soc-smoke eriscv-m1-act-smoke

eriscv-m1-tcm-arbitration:
	$(MAKE) -C eriscv-m1/dv/soc/sim tcm-arbitration

eriscv-m2-core:
	$(MAKE) -C eriscv-m2/dv/core/sim $(SIM_BACKEND)

eriscv-m2-core-smoke:
	$(MAKE) -C eriscv-m2/dv/core/sim $(SIM_BACKEND) TESTS="$(M2_CORE_SMOKE_TESTS)"

eriscv-m2-act-smoke:
	ERISCV_ACT_PHASE="$(ACT_SMOKE_PHASE)" $(MAKE) -C eriscv-m2/dv/core/sim $(SIM_BACKEND) TESTS="$(M2_ACT_SMOKE_TESTS)"

eriscv-m2-soc:
	$(MAKE) -C eriscv-m2/dv/soc/sim $(SIM_BACKEND)

eriscv-m2-soc-smoke:
	$(MAKE) -C eriscv-m2/dv/soc/sim $(SIM_BACKEND) TESTS="$(M2_SOC_SMOKE_TESTS)"

eriscv-m2-act:
	$(MAKE) -C eriscv-m2/dv/core/sim $(SIM_BACKEND) TESTS=--act-full

eriscv-m2-smoke: eriscv-m2-core-smoke eriscv-m2-soc-smoke eriscv-m2-act-smoke

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
