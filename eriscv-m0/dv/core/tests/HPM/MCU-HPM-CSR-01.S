/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# MCU-HPM-CSR-01: HPM v1.0 CSR and alias contract.
#
# This test freezes all implemented counters before comparing a machine CSR
# with its URO alias.  It also verifies the mcountinhibit WARL mask, selector
# reserved-bit handling, and the required illegal instruction for mcounteren.

  .section .text
  .globl _start
  .option norvc
_start:
  li    x31, 0x200
  csrw  mtvec, x31

  # All implemented inhibit bits are writable; all other bits are WARL-zero.
  li    x1, -1
  csrw  mcountinhibit, x1
  csrr  x2, mcountinhibit
  li    x3, 0x7d
  bne   x2, x3, fail

  # Freeze mcycle/minstret and compare low/high machine CSRs with URO aliases.
  li    x1, 0x11223344
  csrw  mcycle, x1
  csrr  x2, cycle
  bne   x2, x1, fail
  li    x1, 0x55667788
  csrw  mcycleh, x1
  csrr  x2, cycleh
  bne   x2, x1, fail

  li    x1, 0x99aabbcc
  csrw  minstret, x1
  csrr  x2, instret
  bne   x2, x1, fail
  li    x1, 0xddeeff00
  csrw  minstreth, x1
  csrr  x2, instreth
  bne   x2, x1, fail

  # Disable events before exact HPM CSR/alias comparisons.
  csrw  mhpmevent3, x0
  csrw  mhpmevent4, x0
  csrw  mhpmevent5, x0
  csrw  mhpmevent6, x0

  li    x1, 0x01020304
  csrw  mhpmcounter3, x1
  csrr  x2, hpmcounter3
  bne   x2, x1, fail
  li    x1, 0x11121314
  csrw  mhpmcounter3h, x1
  csrr  x2, hpmcounter3h
  bne   x2, x1, fail

  li    x1, 0x21222324
  csrw  mhpmcounter4, x1
  csrr  x2, hpmcounter4
  bne   x2, x1, fail
  li    x1, 0x31323334
  csrw  mhpmcounter4h, x1
  csrr  x2, hpmcounter4h
  bne   x2, x1, fail

  li    x1, 0x41424344
  csrw  mhpmcounter5, x1
  csrr  x2, hpmcounter5
  bne   x2, x1, fail
  li    x1, 0x51525354
  csrw  mhpmcounter5h, x1
  csrr  x2, hpmcounter5h
  bne   x2, x1, fail

  li    x1, 0x61626364
  csrw  mhpmcounter6, x1
  csrr  x2, hpmcounter6
  bne   x2, x1, fail
  li    x1, 0x71727374
  csrw  mhpmcounter6h, x1
  csrr  x2, hpmcounter6h
  bne   x2, x1, fail

  # Reserved selector bits must read as zero without changing a legal ID.
  li    x1, 0x01000004
  csrw  mhpmevent3, x1
  csrr  x2, mhpmevent3
  li    x3, 0x04
  bne   x2, x3, fail

  # mcounteren is absent in this M-mode-only product and must trap illegally.
  li    x27, 0
  csrr  x10, mcounteren
after_mcounteren:
  li    x3, 1
  bne   x27, x3, fail

  li    x28, 1
  jal   x0, done

fail:
  li    x28, 0
done:
  jal   x0, done

  .org 0x200
illegal_csr_handler:
  csrr  x11, mcause
  li    x12, 2
  bne   x11, x12, handler_bad
  li    x27, 1
  jal   x0, handler_resume
handler_bad:
  li    x27, 0
handler_resume:
  csrr  x11, mepc
  addi  x11, x11, 4
  csrw  mepc, x11
  mret
