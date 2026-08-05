/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# M0 compressed-control prediction guard.
#
# C.BEQZ/C.BNEZ enter the same BTFNT predictor after decompression. C.J and
# C.JAL are direct jumps and redirect in ID; C.JALR remains intentionally out
# of scope because it is indirect.

  .option rvc
  .globl _start
_start:
  c.li    x8, 2
c_back_taken:
  c.addi  x8, -1
  c.bnez  x8, c_back_taken        # backward taken, then backward not-taken

  c.li    x9, 0
  c.li    x8, 1
c_back_not_taken_target:
  c.addi  x9, 1
  c.beqz  x8, c_back_not_taken_target # backward not-taken

  c.li    x8, 0
  c.beqz  x8, c_forward_taken_target  # forward taken
  c.li    x10, 1                       # wrong path
c_forward_taken_target:
  c.li    x10, 2

  c.bnez  x8, c_forward_not_taken_target # forward not-taken
  c.li    x11, 3
  c.j     c_after_forward
c_forward_not_taken_target:
  c.li    x11, 4                         # wrong path

c_after_forward:
  c.j     c_j_target
  c.li    x12, 1                          # wrong path
c_j_target:
  c.li    x12, 2
  c.jal   c_jal_target
  c.li    x13, 1                          # wrong path
c_jal_target:
  c.li    x13, 2
done:
  c.j     done
