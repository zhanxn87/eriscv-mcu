/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# MCU-PMP-SOC-01: product-path PMP integration evidence.
#
# The test first proves reset leaves PMP unconfigured by accessing DMEM and
# GPIO APB. It then locks DMEM, GPIO APB, and an IMEM firmware word and proves
# store/load/fetch faults have precise mcause/mtval values. The SoC TB confirms
# no protected DBus request reaches the corresponding target window.

  .section .text
  .globl _start
  .option norvc

_start:
  li    x1, 0x10000200
  csrw  mtvec, x1
  li    x20, 0

  # Reset contract: before PMP configuration, M-mode may access DMEM and APB.
  li    x1, 0x11000000
  li    x2, 0x11223344
  sw    x2, 0(x1)
  lw    x3, 0(x1)
  bne   x2, x3, fail

  li    x4, 0x40010000
  sw    x2, 0(x4)

  # Lock a 4 KiB DMEM NAPOT region with no permissions (entry 0), lock GPIO
  # OUT as NA4 with no permissions (entry 1), lock the pmp_pass firmware
  # instruction as
  # R/X but not W (entry 2), and lock an IMEM fetch payload with no execute
  # permission (entry 3).
  li    x5, 0x044001ff
  csrw  pmpaddr0, x5
  li    x5, 0x10004000
  csrw  pmpaddr1, x5
  li    x5, 0x04000101
  csrw  pmpaddr2, x5
  li    x5, 0x04000100
  csrw  pmpaddr3, x5
  li    x5, 0x90959098
  csrw  pmpcfg0, x5

  # Locked DMEM store and load are both denied before DMEM sees a request.
  li    x1, 0x11000000
  li    x2, 0x55667788
  sw    x2, 0(x1)
  lw    x3, 0(x1)

  # Locked GPIO APB store and load are both denied before the APB bridge.
  li    x4, 0x40010000
  sw    x2, 0(x4)
  lw    x3, 0(x4)

  # PMP leaves an unmatched address available to M-mode. It must retain the
  # normal unmapped-APB DBus-error behavior after PMP is enabled.
  li    x23, 0x11223344
  li    x4, 0x40060000
  lw    x23, 0(x4)

  # A locked firmware instruction cannot be changed through the DBus IMEM
  # window. The fetch payload returns into pmp_pass below, proving the
  # instruction was preserved.
  li    x5, 0x10000404
  sw    x2, 0(x5)

  # The payload itself is in executable IMEM, but PMP denies its fetch.
  li    x6, 0x10000400
  jalr  x0, x6, 0

fail:
  addi  x24, x0, 0
pmp_done:
  jal   x0, pmp_done

  .org 0x200
handler:
  csrr  x5, mcause
  csrr  x6, mtval
  beq   x20, x0, record_dmem_store
  li    x7, 1
  beq   x20, x7, record_dmem_load
  li    x7, 2
  beq   x20, x7, record_apb_store
  li    x7, 3
  beq   x20, x7, record_apb_load
  li    x7, 4
  beq   x20, x7, record_imem_store
  li    x7, 5
  beq   x20, x7, record_imem_fetch
  jal   x0, fail

record_dmem_store:
  addi  x10, x5, 0
  addi  x11, x6, 0
  jal   x0, return_from_fault
record_dmem_load:
  addi  x12, x5, 0
  addi  x13, x6, 0
  jal   x0, return_from_fault
record_apb_store:
  addi  x14, x5, 0
  addi  x15, x6, 0
  jal   x0, return_from_fault
record_apb_load:
  addi  x16, x5, 0
  addi  x17, x6, 0
  jal   x0, return_from_fault
record_imem_store:
  addi  x18, x5, 0
  addi  x19, x6, 0
  jal   x0, return_from_fault
record_imem_fetch:
  addi  x21, x5, 0
  addi  x22, x6, 0

return_from_fault:
  addi  x20, x20, 1
  csrr  x7, mepc
  addi  x7, x7, 4
  csrw  mepc, x7
  mret

  .org 0x400
fetch_denied_payload:
  nop

  .org 0x404
pmp_pass:
  li    x5, 6
  bne   x20, x5, fail
  li    x24, 1
  jal   x0, pmp_done
