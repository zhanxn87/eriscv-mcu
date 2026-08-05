# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

PYTHON ?= python3
CROSS_COMPILE ?= riscv64-unknown-elf-
CC := $(CROSS_COMPILE)gcc

SW_DIR ?= $(abspath ../..)
include $(SW_DIR)/isa.mk
THIRD_PARTY_DIR := $(abspath $(SW_DIR)/../../third_party)
KERNEL_DIR := $(THIRD_PARTY_DIR)/FreeRTOS-Kernel
PORT_DIR := $(KERNEL_DIR)/portable/GCC/RISC-V
PORT_EXT_DIR := $(PORT_DIR)/chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions
QUAL_DIR := $(SW_DIR)/rtos/freertos
DHRY_DIR := $(SW_DIR)/benchmarks/dhrystone
COREMARK_DIR := $(THIRD_PARTY_DIR)/CoreMark
BUILD_DIR ?= $(SW_DIR)/build/freertos_monitor
BOARD_BUILD_DIR := $(SW_DIR)/build/freertos_monitor_board
DHRY_ITERATIONS ?= 1000000
COREMARK_ITERATIONS ?= 1000
ELF := $(BUILD_DIR)/freertos_monitor.elf
IMEM_MEM := $(BUILD_DIR)/freertos_monitor.imem.mem
DMEM_MEM := $(BUILD_DIR)/freertos_monitor.dmem.mem

APP_SRCS := $(SW_DIR)/bsp/startup/crt0.S main.c $(QUAL_DIR)/freertos_libc.c $(SW_DIR)/bsp/drivers/uart.c \
  $(QUAL_DIR)/drivers/plic.c $(QUAL_DIR)/drivers/timer.c
BENCH_SRCS := benchmark_dhrystone.c $(DHRY_DIR)/dhry_2.c $(DHRY_DIR)/dhry_portme.c \
  benchmark_coremark.c $(COREMARK_DIR)/core_list_join.c $(COREMARK_DIR)/core_matrix.c \
  $(COREMARK_DIR)/core_state.c $(COREMARK_DIR)/core_util.c $(SW_DIR)/benchmarks/coremark/core_portme.c
KERNEL_SRCS := $(KERNEL_DIR)/tasks.c $(KERNEL_DIR)/queue.c $(KERNEL_DIR)/list.c \
  $(KERNEL_DIR)/portable/MemMang/heap_4.c
PORT_SRCS := $(PORT_DIR)/port.c $(PORT_DIR)/portASM.S
CFLAGS := -march=$(ISA) -mabi=$(RTOS_ABI) -mcmodel=medany \
  -DERISCV_MCU_UART_DIVISOR=$(UART_DIVISOR)u \
  -ffreestanding -fno-builtin -fdata-sections -ffunction-sections \
  -Wall -Wextra -Werror -Wno-error=maybe-uninitialized -O2 -I. -I$(SW_DIR)/include -I$(QUAL_DIR) -I$(QUAL_DIR)/drivers \
  -I$(KERNEL_DIR)/include -I$(PORT_DIR) -I$(PORT_EXT_DIR) -I$(DHRY_DIR) -I$(COREMARK_DIR) \
  -I$(SW_DIR)/benchmarks/coremark \
  -DFREERTOS_MONITOR_EMBEDDED=1 -DDHRY_ITERATIONS=$(DHRY_ITERATIONS) -DITERATIONS=$(COREMARK_ITERATIONS) \
  -DTOTAL_DATA_SIZE=2000 -DVALIDATION_RUN=1
CPPFLAGS ?=
CPPFLAGS += -DERISCV_MCU_BSP_SKIP_TRAP_INIT
LDFLAGS := -nostdlib -nostartfiles -Wl,--gc-sections \
  -Wl,-T$(SW_DIR)/linker/eriscv_mcu.ld -Wl,-Map,$(BUILD_DIR)/freertos_monitor.map
LDLIBS := -lgcc

.PHONY: images board-images clean size

images: $(IMEM_MEM) $(DMEM_MEM)

board-images:
	$(MAKE) images BUILD_DIR=$(BOARD_BUILD_DIR) CPPFLAGS="$(CPPFLAGS) -DFREERTOS_MONITOR_BOARD=1"

$(ELF): $(APP_SRCS) $(BENCH_SRCS) FreeRTOSConfig.h $(SW_DIR)/linker/eriscv_mcu.ld | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) $(APP_SRCS) $(BENCH_SRCS) $(KERNEL_SRCS) $(PORT_SRCS) $(LDLIBS) -o $@

$(IMEM_MEM) $(DMEM_MEM): $(ELF) $(SW_DIR)/tools/elf_to_mem.py
	$(PYTHON) $(SW_DIR)/tools/elf_to_mem.py $(ELF) --imem-out $(IMEM_MEM) --dmem-out $(DMEM_MEM)

size: $(ELF)
	$(CROSS_COMPILE)size $(ELF)

$(BUILD_DIR):
	mkdir -p $@

clean:
	rm -rf $(BUILD_DIR)
