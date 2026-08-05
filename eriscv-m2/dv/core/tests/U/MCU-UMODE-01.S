/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# MCU-UMODE-01: M/U transition, U-mode CSR trap, and PMP task isolation.

  .section .text
  .globl _start
  .option norvc

_start:
  li    x1, 0x00000100
  csrw  mtvec, x1

  # PMP entry 0: RX IMEM [0x00000000, 0x00010000).
  # PMP entry 1: RW DMEM [0x00040000, 0x00050000).
  li    x1, 0x00001fff
  csrw  pmpaddr0, x1
  li    x1, 0x00011fff
  csrw  pmpaddr1, x1
  li    x1, 0x00001b1d
  csrw  pmpcfg0, x1

  li    x1, 0x00000200
  csrw  mepc, x1
  csrw  mstatus, x0             # MPP=U, MIE=0.
  mret

  .org 0x100
trap_handler:
  csrr  x10, mcause
  li    x11, 8
  beq   x10, x11, u_ecall
  li    x11, 2
  beq   x10, x11, u_illegal_csr
  li    x11, 5
  beq   x10, x11, u_load_fault
  li    x11, 1
  beq   x10, x11, u_instruction_fault
  jal   x0, fail

u_ecall:
  li    x20, 1
  jal   x0, resume_user

u_illegal_csr:
  li    x21, 1
  jal   x0, resume_user

resume_user:
  csrr  x12, mepc
  addi  x12, x12, 4
  csrw  mepc, x12
  mret

u_load_fault:
  csrr  x13, mtval
  li    x14, 0x00020000
  bne   x13, x14, fail
  li    x22, 1
  # Remove execute permission from U-mode IMEM, then return to a probe PC.
  # M-mode remains permitted because the entry is unlocked.
  li    x12, 0x00001b19
  csrw  pmpcfg0, x12
  li    x12, 0x00000240
  csrw  mepc, x12
  mret

u_instruction_fault:
  csrr  x13, mtval
  li    x14, 0x00000240
  bne   x13, x14, fail
  li    x25, 1
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
user_entry:
  li    x4, 0x00040000
  li    x5, 0x12345678
  sw    x5, 0(x4)               # Allowed U-mode DMEM store.
  ecall                         # Must trap with cause 8.
  csrr  x6, mstatus             # U-mode M-CSR access must trap with cause 2.
  li    x7, 0x00020000
  lw    x8, 0(x7)               # No PMP match: U-mode load access fault.
user_loop:
  jal   x0, user_loop

  .org 0x240
user_fetch_fault:
  nop                            # Must fault before this instruction executes.

  .org 0x300
finish:
  li    x15, 1
  bne   x20, x15, fail
  bne   x21, x15, fail
  bne   x22, x15, fail
  bne   x25, x15, fail
  lw    x23, 0(x4)
  bne   x23, x5, fail
  li    x24, 1
done:
  jal   x0, done
