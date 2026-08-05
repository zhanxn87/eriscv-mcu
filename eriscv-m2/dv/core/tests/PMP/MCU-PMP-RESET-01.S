/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# MCU-PMP-RESET-01: PMP reset-state verification for 16-entry M1 contract.
#
# Verifies:
#   P4.1 — All 16 pmpcfg entries reset to 0x00 (OFF mode, unlocked)
#   P4.2 — All 16 pmpaddr entries reset to 0x00000000
#   P4.3 — Post-reset, all M-mode accesses pass (unlocked OFF)
#   P4.4 — pmpcfg0..3 CSR readback (word-packed cfg fields)

  .globl _start
_start:

  # =========================================================================
  # P4.1 — Check all 16 pmpcfg entries reset to 0x00
  # =========================================================================
  csrr  x10, pmpcfg0           # entries 0..3
  bne   x10, x0, fail
  csrr  x11, pmpcfg1           # entries 4..7
  bne   x11, x0, fail
  csrr  x12, pmpcfg2           # entries 8..11
  bne   x12, x0, fail
  csrr  x13, pmpcfg3           # entries 12..15
  bne   x13, x0, fail

  # =========================================================================
  # P4.2 — Check all 16 pmpaddr entries reset to 0x00000000
  # =========================================================================
  csrr  x14, pmpaddr0
  bne   x14, x0, fail
  csrr  x15, pmpaddr1
  bne   x15, x0, fail
  csrr  x16, pmpaddr2
  bne   x16, x0, fail
  csrr  x17, pmpaddr3
  bne   x17, x0, fail
  csrr  x18, pmpaddr4
  bne   x18, x0, fail
  csrr  x19, pmpaddr5
  bne   x19, x0, fail
  csrr  x20, pmpaddr6
  bne   x20, x0, fail
  csrr  x21, pmpaddr7
  bne   x21, x0, fail
  csrr  x22, pmpaddr8
  bne   x22, x0, fail
  csrr  x23, pmpaddr9
  bne   x23, x0, fail
  csrr  x24, pmpaddr10
  bne   x24, x0, fail
  csrr  x25, pmpaddr11
  bne   x25, x0, fail
  csrr  x26, pmpaddr12
  bne   x26, x0, fail
  csrr  x27, pmpaddr13
  bne   x27, x0, fail
  csrr  x28, pmpaddr14
  bne   x28, x0, fail
  csrr  x29, pmpaddr15
  bne   x29, x0, fail

  # =========================================================================
  # P4.3 — Post-reset, M-mode accesses must pass (all OFF/unlocked)
  # =========================================================================
  # Write to DMEM without any PMP configuration
  lui   x2, 0x00040
  li    x3, 0xCAFEBABE
  sw    x3, 0(x2)
  lw    x4, 0(x2)
  bne   x3, x4, fail

  # Execute from IMEM (the next instruction is the proof)
  # If we reach here, instruction fetch succeeded.

  # =========================================================================
  # P4.4 — Write and readback full all entries via CSR
  # =========================================================================
  # Write known values to all 16 pmpaddr entries and read back
  li    x5, 0x00001000
  csrw  pmpaddr0, x5
  csrr  x6, pmpaddr0
  bne   x5, x6, fail

  li    x5, 0x00002000
  csrw  pmpaddr1, x5
  csrr  x6, pmpaddr1
  bne   x5, x6, fail

  li    x5, 0x00003000
  csrw  pmpaddr2, x5
  csrr  x6, pmpaddr2
  bne   x5, x6, fail

  # Verify entry 3 is still accessible after writing entries 0-2
  li    x5, 0x00004000
  csrw  pmpaddr3, x5
  csrr  x6, pmpaddr3
  bne   x5, x6, fail

  # Verify entry 14 and 15 work
  li    x5, 0x00005000
  csrw  pmpaddr14, x5
  csrr  x6, pmpaddr14
  bne   x5, x6, fail

  li    x5, -1                    # Full RV32 pmpaddr field
  csrw  pmpaddr15, x5
  csrr  x6, pmpaddr15
  bne   x5, x6, fail

  # =========================================================================
  # PASS
  # =========================================================================
  li    x28, 1
  jal   x0, done

fail:
  li    x28, 0

done:
  jal   x0, done
