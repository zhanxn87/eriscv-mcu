/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# eRISCV MCU PMP directed test.
# Covers 16-entry CSR reachability, WARL normalization, locked M-mode NAPOT,
# TOR, and NA4 protection, plus store/load/instruction access faults.

  .section .text
  .globl _start
  .option norvc
_start:
  li    x1, 0x00010000
  li    x3, 0x11223344
  sw    x3, 0(x1)              # Seed NAPOT data before PMP is enabled.

  li    x2, 0x100
  csrw  mtvec, x2
  li    x5, 0x4fff             # NAPOT 32 KiB region at 0x00010000.
  csrw  pmpaddr0, x5
  li    x5, 0x80               # NA4 instruction-fault probe at 0x00000200.
  csrw  pmpaddr1, x5
  li    x5, 0x00009099         # entry0=L|NAPOT|R; entry1=L|NA4|---.
  csrw  pmpcfg0, x5

  li    x4, 0x55667788
  sw    x4, 0(x1)              # Locked NAPOT store fault; handler resumes below.
  lw    x15, 0(x1)             # Locked NAPOT read remains permitted.

  li    x2, 0x00018000
  li    x6, 0x01020304
  sw    x6, 0(x2)              # Seed future TOR data while it is unprotected.
  li    x5, 0x6000
  csrw  pmpaddr2, x5           # TOR lower bound: 0x00018000.
  li    x5, 0x6008
  csrw  pmpaddr3, x5           # TOR upper bound: 0x00018020.
  li    x5, 0x89009099         # entry3=L|TOR|R; preserve locked entries 0/1.
  csrw  pmpcfg0, x5
  li    x5, 0
  csrw  pmpaddr2, x5           # Locked TOR entry locks its preceding address.
  csrr  x29, pmpaddr2
  sw    x4, 0(x2)              # Locked TOR store fault.

  li    x2, 0x0001c000
  li    x6, 0x0a0b0c0d
  sw    x6, 0(x2)              # Seed future NA4 no-read location.
  li    x5, 0x7000
  csrw  pmpaddr4, x5           # NA4 region at 0x0001c000.
  li    x5, 0x90               # entry4=L|NA4|---.
  csrw  pmpcfg1, x5
  lw    x6, 0(x2)              # Locked NA4 load fault.

  li    x5, 0
  csrw  pmpaddr0, x5           # Locked address must remain unchanged.
  csrr  x16, pmpaddr0
  csrw  pmpcfg0, x5            # Locked configuration bytes remain unchanged.
  csrr  x17, pmpcfg0

  li    x18, -1
  csrw  pmpaddr15, x18         # Full RV32 pmpaddr field (physical [33:2]).
  csrr  x18, pmpaddr15
  li    x5, 0x00000200         # entry13: R=0/W=1 is WARL-normalized to zero.
  csrw  pmpcfg3, x5
  csrr  x14, pmpcfg3

  li    x19, 0x200
  jalr  x0, x19, 0             # Locked NA4 target has no execute permission.

  .org 0x100
handler:
  csrr  x20, mcause
  csrr  x21, mtval
  li    x22, 7
  bne   x20, x22, check_load_fault
  li    x22, 0x00010000
  beq   x21, x22, napot_store_fault
  li    x22, 0x00018000
  beq   x21, x22, tor_store_fault
  jal   x0, trap_return

check_load_fault:
  li    x22, 5
  beq   x20, x22, load_fault
  li    x22, 1
  beq   x20, x22, instruction_fault
  jal   x0, trap_return

napot_store_fault:
  addi  x10, x20, 0
  addi  x11, x21, 0
  jal   x0, trap_return

tor_store_fault:
  addi  x25, x20, 0
  addi  x26, x21, 0
  jal   x0, trap_return

load_fault:
  addi  x27, x20, 0
  addi  x28, x21, 0
  jal   x0, trap_return

instruction_fault:
  addi  x12, x20, 0
  addi  x13, x21, 0

trap_return:
  csrr  x23, mepc
  addi  x23, x23, 4
  csrw  mepc, x23
  mret

  .org 0x200
instruction_fault_probe:
  nop

pmp_pass:
  addi  x24, x0, 1
pmp_done:
  jal   x0, pmp_done
