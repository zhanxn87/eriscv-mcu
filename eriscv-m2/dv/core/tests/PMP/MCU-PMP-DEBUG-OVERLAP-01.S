/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# TB asserts an external Debug halt exactly when the D-side PMP verdict appears.
# PMP must commit first; Debug may halt only after the fault packet is resolved.

  .section .text
  .globl _start
  .option norvc
_start:
  li    x1, 0x100
  csrw  mtvec, x1
  li    x2, 0x00010000
  li    x3, 0x4000
  csrw  pmpaddr0, x3
  li    x3, 0x98
  csrw  pmpcfg0, x3
  nop

  sw    x0, 0(x2)
  addi  x20, x0, 1
after_fault:
  li    x3, 1
  bne   x23, x3, fail
  bne   x20, x0, fail
  li    x24, 1
done:
  jal   x0, done

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
  addi  x4, x4, 8              # Skip faulting store and younger addi.
  csrw  mepc, x4
  mret
