/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# eRISCV MCU DBus unmapped error test.
# The first word beyond M0 DTCM and an unimplemented APB slot must each return
# one DBus error. A failed load must not write its destination register.

  .section .text
  .globl _start
  .option norvc
_start:
  lui  x1, 0x11008             # first byte beyond 32 KiB M0 DTCM
  li   x5, 0x11223344          # failed-load destination sentinel
  lw   x5, 0(x1)               # unmapped DTCM: DBus error
  lui  x1, 0x40060             # reserved v2 MMIO slot at 0x4006_0000
  li   x6, 0x55667788          # second failed-load destination sentinel
  lw   x6, 0x600(x1)           # unimplemented APB slot: DBus error
  li   x7, 1                   # execution must continue after both responses
  add  x24, x5, x0
  add  x25, x6, x0
  add  x26, x7, x0

done:
  jal  x0, done
