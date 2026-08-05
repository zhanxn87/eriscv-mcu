/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# D-side PMP fault must win over younger EX branch/JAL/JALR redirects.

  .section .text
  .globl _start
  .option norvc
_start:
  li    x1, 0x100
  csrw  mtvec, x1
  li    x2, 0x00010000
  li    x3, 0x4000              # Locked NAPOT 8-byte region at 0x00010000.
  csrw  pmpaddr0, x3
  li    x3, 0x98                # L|NAPOT, no R/W/X permissions.
  csrw  pmpcfg0, x3
  nop

  sw    x0, 0(x2)
  beq   x0, x0, branch_target
  addi  x20, x0, 0x11
after_branch:
  sw    x0, 0(x2)
  jal   x0, jal_target
  addi  x21, x0, 0x22
after_jal:
  la    x7, jalr_target
  sw    x0, 0(x2)
  jalr  x0, x7, 0
  addi  x22, x0, 0x33
after_jalr:
  li    x3, 3
  bne   x23, x3, fail
  bne   x20, x0, fail
  bne   x21, x0, fail
  bne   x22, x0, fail
  li    x24, 1
done:
  jal   x0, done

branch_target:
  addi  x20, x0, 0x44
  jal   x0, after_branch
jal_target:
  addi  x21, x0, 0x55
  jal   x0, after_jal
jalr_target:
  addi  x22, x0, 0x66
  jal   x0, after_jalr

fail:
  li    x24, 0
  jal   x0, done

  .org 0x100
handler:
  csrr  x4, mcause
  li    x5, 7
  bne   x4, x5, fail
  csrr  x4, mtval
  bne   x4, x2, fail
  addi  x23, x23, 1
  csrr  x4, mepc
  addi  x4, x4, 12             # Skip faulting store and both younger instructions.
  csrw  mepc, x4
  mret
