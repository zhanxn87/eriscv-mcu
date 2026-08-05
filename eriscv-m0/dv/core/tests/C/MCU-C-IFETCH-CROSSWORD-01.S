/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# RV32C IF throughput guard.
#
# A word-aligned C16 followed by raw 32-bit instructions places every raw
# instruction at PC[1]=1.  The correct IF path must retain the unused upper
# halfword of the compose response; otherwise it re-reads every word.
#
# x10/x11 = functional checksums (8)
# x30 = aligned raw-32 delta; x31 = crossword raw-32 delta
# x29 = crossword penalty; x28 = pass only when the penalty is below 4 cycles
# The second half deliberately traps from an upper-halfword RV32 ECALL.  It
# exercises redirect/old-response discard while the IF compose state is live.

  .section .text
  .globl _start
  .option rvc

_start:
  # Control: all raw instructions are word aligned.
  .p2align 2
  .option push
  .option norvc
  csrr x5, mcycle
  addi x10, x0, 1
  addi x10, x10, 1
  addi x10, x10, 1
  addi x10, x10, 1
  addi x10, x10, 1
  addi x10, x10, 1
  addi x10, x10, 1
  addi x10, x10, 1
  csrr x6, mcycle
  .option pop
  sub x30, x6, x5

  # DUT: force c.nop onto the low halfword of an instruction-memory word.
  .p2align 2
crossword_start:
  c.nop

  # Every instruction in this block starts at PC[1]=1.
  .option push
  .option norvc
  csrr x7, mcycle
  addi x11, x0, 1
  addi x11, x11, 1
  addi x11, x11, 1
  addi x11, x11, 1
  addi x11, x11, 1
  addi x11, x11, 1
  addi x11, x11, 1
  addi x11, x11, 1
  csrr x8, mcycle
  .option pop

  sub x31, x8, x7
  sub x29, x31, x30
  li x9, 4
  sltu x28, x29, x9

  # Redirect throughput guard: compare a backward branch to a word-aligned
  # RV32 target with an otherwise-identical target in a word's upper half.
  # The latter must not pay one IF bubble per taken branch.
  .p2align 2
  .option push
  .option norvc
  csrr x14, mcycle
  addi x12, x0, 8
branch_aligned_target:
  addi x12, x12, -1
  bnez x12, branch_aligned_target
  csrr x15, mcycle
  .option pop
  sub x16, x15, x14

  .p2align 2
  c.nop
  .option push
  .option norvc
  csrr x17, mcycle
  addi x12, x0, 8
branch_upper_target:
  addi x12, x12, -1
  bnez x12, branch_upper_target
  csrr x18, mcycle
  .option pop
  sub x19, x18, x17
  sub x20, x19, x16
  li x21, 16
  sltu x25, x20, x21

  # Trap-path guard: ECALL starts at PC[1]=1.  The handler must see its
  # halfword-aligned MEPC, skip the adjacent wrong-path addi, and return.
  la x5, crossword_trap_handler
  csrw mtvec, x5
  addi x13, x0, 0
  .p2align 2
crossword_trap:
  c.nop
  .option push
  .option norvc
  ecall
  addi x13, x0, 13            # must be flushed, then skipped by MRET
  .option pop
after_crossword_trap:
  bne x13, x0, trap_main_fail
  li x26, 1
  j done

trap_main_fail:
  li x26, 0
  li x28, 0

done:
  j done

  .org 0x200
crossword_trap_handler:
  csrr x6, mcause
  li x7, 11                   # ECALL from M-mode
  bne x6, x7, trap_handler_bad
  csrr x6, mepc
  la x7, crossword_trap
  addi x7, x7, 2              # ECALL is the upper-halfword instruction
  bne x6, x7, trap_handler_bad
  li x27, 1
  j trap_handler_resume

trap_handler_bad:
  li x27, 0

trap_handler_resume:
  csrr x6, mepc
  addi x6, x6, 8              # ECALL + skipped wrong-path addi
  csrw mepc, x6
  mret
