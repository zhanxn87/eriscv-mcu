/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# M1 load-response forwarding guard.
#
# A dependent ADD follows LW immediately. HPM6 counts LOAD_USE_STALL_CYCLES.
# The exact overlap with an I-side wait is implementation-dependent; the
# response bypass must nevertheless prevent a third load-use bubble. x29 is
# nonzero only when the observed count exceeds the two-cycle budget, while x4
# proves that the dependent result was forwarded correctly.

  .section .text
  .globl _start
  .option norvc

_start:
  lui   x1, 0x11000             # DTCM base; do not exercise DBus-to-IMEM arbitration
  li    x2, 0x2a
  sw    x2, 0(x1)

  csrw  mhpmevent6, x0
  csrw  mhpmcounter6, x0
  li    x5, 11                  # HPM_EVENT_LOAD_USE_STALL_CYCLES
  csrw  mhpmevent6, x5

  lw    x3, 0(x1)
  add   x4, x3, x2              # immediate dependent consumer

  csrw  mhpmevent6, x0
  csrr  x30, mhpmcounter6
  li    x5, 2
  sltu  x29, x5, x30
  li    x5, 84
  sub   x28, x4, x5

done:
  jal   x0, done
