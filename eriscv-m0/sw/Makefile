# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

PYTHON ?= python3
SIM_BACKEND ?= verilator
CROSS_COMPILE ?= riscv64-unknown-elf-
CC := $(CROSS_COMPILE)gcc

include isa.mk

EXAMPLE ?= hello_uart
VERSION ?= 0.1.0
RELEASE_EXAMPLES := hello_uart timer_apb_poll timer_clint wfi_tickless irq_timer_uart wdt_smoke
BUILD_DIR ?= build/$(EXAMPLE)
ELF := $(BUILD_DIR)/$(EXAMPLE).elf
IMEM_MEM := $(BUILD_DIR)/$(EXAMPLE).imem.mem
DMEM_MEM := $(BUILD_DIR)/$(EXAMPLE).dmem.mem

COMMON_SRCS := bsp/startup/crt0.S lib/trap.S lib/trap.c bsp/drivers/uart.c
EXAMPLE_SRC := examples/$(EXAMPLE)/main.c
CFLAGS := -march=$(ISA) -mabi=$(ABI) -mcmodel=medany \
  -DERISCV_MCU_UART_DIVISOR=$(UART_DIVISOR)u \
  -ffreestanding -fno-builtin -fdata-sections -ffunction-sections \
  -Wall -Wextra -Werror -Os -Iinclude
LDFLAGS := -nostdlib -nostartfiles -Wl,--gc-sections -Wl,-Tlinker/eriscv_mcu.ld \
  -Wl,-Map,$(BUILD_DIR)/$(EXAMPLE).map -lgcc

.PHONY: all images images-all ci sim sim-async clean print-config \
  coremark sim-coremark embench sim-embench microbench sim-microbench \
  freertos sim-freertos sim-freertos-qualification dhrystone sim-dhrystone zephyr sim-zephyr

COREMARK_ITERATIONS ?= 1
EMBENCH_BENCH ?= matmult-int
EMBENCH_PROFILE ?= speed
EMBENCH_SCALE ?= 1
DHRY_ITERATIONS ?= 1000
DHRY_HPM ?= 0

all: images

images: $(IMEM_MEM) $(DMEM_MEM)

images-all:
	@for example in $(RELEASE_EXAMPLES); do \
	  $(MAKE) EXAMPLE=$$example images || exit $$?; \
	done

ci: images-all
	$(PYTHON) tools/run_mcu_ci.py --skip-build

sim: images
	$(PYTHON) tools/run_hello_uart_sim.py --backend $(SIM_BACKEND)

sim-async:
	$(PYTHON) tools/run_hello_uart_sim.py --backend $(SIM_BACKEND) --example async_uart --tc BSP-UART-ASYNC --expected-uart 655249534356204d4355206173796e63205541525420495251204649464f20736d6f6b653a20303132333435363738396162636465666768696a6b6c6d6e6f707172737475767778797a4142434445464748494a4b4c4d4e4f505152535455565758595a0d0a --max-cycles 20000

$(ELF): $(COMMON_SRCS) $(EXAMPLE_SRC) linker/eriscv_mcu.ld | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) $(COMMON_SRCS) $(EXAMPLE_SRC) -o $@ -lgcc

$(IMEM_MEM) $(DMEM_MEM): $(ELF) tools/elf_to_mem.py
	$(PYTHON) tools/elf_to_mem.py $(ELF) --imem-out $(IMEM_MEM) --dmem-out $(DMEM_MEM)

$(BUILD_DIR):
	mkdir -p $@

print-config:
	@echo "VERSION=$(VERSION)"
	@echo "EXAMPLE=$(EXAMPLE)"
	@echo "CROSS_COMPILE=$(CROSS_COMPILE)"
	@echo "ISA=$(ISA)"
	@echo "ABI=$(ABI)"
	@echo "RTOS_ABI=$(RTOS_ABI)"
	@echo "RTOS_ISA=$(RTOS_ISA)"
	@echo "SOC_CLOCK_HZ=$(SOC_CLOCK_HZ)"
	@echo "UART_MODE=$(UART_MODE)"
	@echo "UART_DIVISOR=$(UART_DIVISOR)"
	@echo "UART_BOARD_DIVISOR=$(UART_BOARD_DIVISOR)"
	@echo "IMEM=$(IMEM_MEM)"
	@echo "DMEM=$(DMEM_MEM)"

coremark:
	$(MAKE) -C benchmarks/coremark SW_DIR=$(CURDIR) ISA=$(ISA) ABI=$(ABI) SOC_CLOCK_HZ=$(SOC_CLOCK_HZ) UART_DIVISOR=$(UART_DIVISOR) ITERATIONS=$(COREMARK_ITERATIONS) images

sim-coremark:
	$(PYTHON) tools/run_coremark_sim.py

embench:
	$(MAKE) -C benchmarks/embench SW_DIR=$(CURDIR) ISA=$(ISA) ABI=$(ABI) UART_DIVISOR=$(UART_DIVISOR) BENCH=$(EMBENCH_BENCH) PROFILE=$(EMBENCH_PROFILE) SCALE=$(EMBENCH_SCALE) images

sim-embench:
	$(PYTHON) tools/run_embench_sim.py --backend $(SIM_BACKEND)

microbench:
	$(MAKE) -C benchmarks/microbench SW_DIR=$(CURDIR) ISA=$(ISA) ABI=$(ABI) UART_DIVISOR=$(UART_DIVISOR) images

sim-microbench:
	$(PYTHON) tools/run_microbench_sim.py

freertos:
	$(MAKE) -C rtos/freertos SW_DIR=$(CURDIR) RTOS_ISA=$(RTOS_ISA) RTOS_ABI=$(RTOS_ABI) UART_DIVISOR=$(UART_DIVISOR) images

sim-freertos:
	$(PYTHON) tools/run_freertos_sim.py

sim-freertos-qualification:
	$(PYTHON) tools/run_freertos_sim.py --failstops

dhrystone:
	$(MAKE) -C benchmarks/dhrystone SW_DIR=$(CURDIR) ISA=$(ISA) ABI=$(ABI) UART_DIVISOR=$(UART_DIVISOR) ITERATIONS=$(DHRY_ITERATIONS) HPM=$(DHRY_HPM) images

sim-dhrystone:
	$(PYTHON) tools/run_dhrystone_sim.py

zephyr:
	$(MAKE) -C rtos/zephyr SW_DIR=$(CURDIR) RTOS_ISA=$(RTOS_ISA) RTOS_ABI=$(RTOS_ABI) images

sim-zephyr:
	$(PYTHON) tools/run_zephyr_sim.py

clean:
	rm -rf build
