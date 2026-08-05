/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# MCU-UMODE-EXT-01: MPRV effective privilege and U-mode counter delegation.

  .section .text
  .globl _start
  .option norvc

_start:
  li    x1, 0x00000100
  csrw  mtvec, x1

  # MPRV=1 with MPP=U makes this M-mode load subject to U-mode PMP rules.
  # No PMP entry is configured yet, so it must fault with load access-fault.
  li    x4, 0x00020000
  li    x1, 0x00020000
  csrw  mstatus, x1
  lw    x5, 0(x4)

after_mprv_fault:
  # PMP entry 0: RX IMEM [0x00000000, 0x00010000).
  # PMP entry 1: RW DMEM [0x00040000, 0x00050000).
  li    x1, 0x00001fff
  csrw  pmpaddr0, x1
  li    x1, 0x00011fff
  csrw  pmpaddr1, x1
  li    x1, 0x00001b1d
  csrw  pmpcfg0, x1

  # Delegate cycle, time, instret, and HPM3..6 counter aliases to U-mode.
  li    x1, 0x7f
  csrw  mcounteren, x1
  li    x1, 0x00000200
  csrw  mepc, x1
  csrw  mstatus, x0             # MPP=U, MPRV=0.
  mret

  .org 0x100
trap_handler:
  csrr  x10, mcause
  li    x11, 5
  beq   x10, x11, mprv_load_fault
  li    x11, 8
  beq   x10, x11, u_ecall
  li    x11, 2
  beq   x10, x11, u_counter_blocked
  jal   x0, fail

mprv_load_fault:
  csrr  x12, mtval
  li    x13, 0x00020000
  bne   x12, x13, fail
  li    x20, 1
  li    x13, 0x00001800
  csrw  mstatus, x13            # Clear MPRV and retain MPP=M before MRET.
  csrr  x12, mepc
  addi  x12, x12, 4
  csrw  mepc, x12
  mret

u_ecall:
  li    x21, 1
  csrw  mcounteren, x0          # Next U-mode counter read must trap.
  li    x12, 0x00000240
  csrw  mepc, x12
  csrw  mstatus, x0             # Return to U-mode.
  mret

u_counter_blocked:
  li    x22, 1
  li    x12, 0x00000300
  csrw  mepc, x12
  li    x13, 0x00001800         # Return to M-mode for final checks.
  csrw  mstatus, x13
  mret

fail:
  li    x24, 0
fail_loop:
  jal   x0, fail_loop

  .org 0x200
user_counter_reads:
  csrr  x6, cycle
  csrr  x7, time
  csrr  x8, instret
  csrr  x9, hpmcounter3
  ecall

  .org 0x240
user_counter_blocked:
  csrr  x14, cycle               # mcounteren.CY=0: illegal instruction.
  jal   x0, fail

  .org 0x300
finish:
  li    x15, 1
  bne   x20, x15, fail
  bne   x21, x15, fail
  bne   x22, x15, fail
  li    x24, 1
done:
  jal   x0, done
