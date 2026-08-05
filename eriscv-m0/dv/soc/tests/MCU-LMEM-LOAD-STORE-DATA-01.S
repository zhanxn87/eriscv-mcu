/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# MCU-LMEM-LOAD-STORE-DATA-01: an accepted DTCM load supplies only the data
# operand of an immediately following store. An address+data dependency must
# retain the normal load-use interlock.

  .section .text
  .globl _start
  .option norvc

_start:
  lui   x1, 0x11000
  li    x4, 0x89abcdef
  sw    x4, 0(x1)
  li    x11, 0x11000010
  sw    x11, 12(x1)
  nop
  nop
  csrw  mhpmevent6, x0
  csrw  mhpmcounter6, x0
  li    x10, 11
  csrw  mhpmevent6, x10
  lw    x3, 0(x1)
  sw    x3, 4(x1)
  nop
  nop
  lb    x6, 0(x1)
  sb    x6, 8(x1)
  nop
  nop
  lhu   x7, 2(x1)
  sh    x7, 10(x1)
  csrw  mhpmevent6, x0
  csrr  x25, mhpmcounter6
  bnez  x25, fail
  lw    x5, 4(x1)
  bne   x5, x4, fail
  lbu   x8, 8(x1)
  li    x10, 0xef
  bne   x8, x10, fail
  lhu   x9, 10(x1)
  li    x10, 0x89ab
  bne   x9, x10, fail
  csrw  mhpmcounter6, x0
  li    x10, 11
  csrw  mhpmevent6, x10
  lw    x12, 12(x1)
  sw    x12, 0(x12)
  csrw  mhpmevent6, x0
  csrr  x26, mhpmcounter6
  beqz  x26, fail
  li    x23, 1
  lw    x13, 16(x1)
  bne   x13, x11, fail
  li    x24, 1
  jal   x0, done
fail:
  li    x23, 0
  li    x24, 0
done:
  jal   x0, done
