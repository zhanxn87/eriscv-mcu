# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

# eRISCV-M1 software build contract.
ISA ?= rv32imc_zicsr_zifencei_zicntr_zihpm_zihintpause
ABI ?= ilp32
RTOS_ABI ?= ilp32
RTOS_ISA ?= $(ISA)

# Hardware timing values match rtl/soc/soc_pkg.sv. UART_MODE selects the
# runtime-UART image profile; UART_DIVISOR remains an expert override.
SOC_CLOCK_HZ ?= 100000000
UART_BOARD_DIVISOR ?= 868
UART_MODE ?= sim

ifeq ($(UART_MODE),sim)
UART_DIVISOR ?= 8
else ifeq ($(UART_MODE),board)
UART_DIVISOR ?= $(UART_BOARD_DIVISOR)
else
$(error UART_MODE must be sim or board)
endif
