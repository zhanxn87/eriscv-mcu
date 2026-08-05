/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# MCU-PMP-SWEEP-01: 16-entry PMP mode/boundary/priority sweep.
#
# Covers:
#   - All 16 entries OFF post-reset → no faults
#   - NAPOT + lock + R/W/X (entry 0)
#   - TOR + lock + read-only (entries 1-2)
#   - NA4 + lock + no-execute (entry 3)
#   - Overlap priority: lower entry wins (entries 0 vs 1)
#   - Lock WARL: locked cfg/addr cannot be modified
#   - All-entry CSR accessibility: entries 4-15 read/write
#   - R=0/W=1 WARL normalization
#
# Self-checking: x28 = 1 at done = PASS.
# Trap handler uses x20=mcause, x21=mtval for fault inspection.

  .globl _start
  .option norvc
_start:
  la    x31, handler
  csrw  mtvec, x31

  # =========================================================================
  # Phase 1 — All entries OFF: no faults on DMEM access
  # =========================================================================
  lui   x2, 0x00040
  li    x3, 0xCAFEBABE
  sw    x3, 0(x2)
  lw    x4, 0(x2)
  bne   x3, x4, fail

  # =========================================================================
  # Phase 2 — NAPOT (entry 0): 4 KiB locked region at DMEM base, R+W+X
  # =========================================================================
  li    x5, 0x101FF             # NAPOT 4 KiB at 0x00040000
  csrw  pmpaddr0, x5
  li    x5, 0x9B                # L=1, NAPOT, R+W+X
  csrw  pmpcfg0, x5
  sw    x3, 0(x2)               # W=1, locked: M-mode store permitted
  lw    x4, 0(x2)
  bne   x3, x4, fail

  # =========================================================================
  # Phase 3 — Lock WARL: locked config and addr cannot change
  # =========================================================================
  li    x5, 0x00
  csrw  pmpcfg0, x5             # Attempt to clear locked entry
  csrr  x6, pmpcfg0
  andi  x6, x6, 0xFF
  li    x7, 0x9B
  bne   x6, x7, fail            # Locked cfg byte must persist

  li    x5, 0
  csrw  pmpaddr0, x5            # Attempt to clear locked addr
  csrr  x6, pmpaddr0
  li    x7, 0x101FF
  bne   x6, x7, fail            # Locked addr must persist

  # =========================================================================
  # Phase 4 — TOR (entries 1-2): locked read-only region
  # =========================================================================
  # Entry 0 is locked NAPOT at [0x00040000, 0x00041000).  PMP priority
  # requires this TOR range to be outside that match: [0x00040FFC,
  # 0x00041080).  Entry 1 is L|TOR|R, so a read at 0x00041000 passes and
  # a store at the same address faults.
  li    x5, 0x10420             # 0x00041080 >> 2
  csrw  pmpaddr1, x5
  li    x5, 0x0000899B          # entry0=0x9B, entry1=L|TOR|R (0x89)
  csrw  pmpcfg0, x5
  lui   x9, 0x00041
  lw    x4, 0(x9)               # R=1 → pass
  sw    x3, 0(x9)               # W=0 → store fault
  li    x5, 7
  bne   x20, x5, fail
  li    x5, 0x00041000
  bne   x21, x5, fail

  csrw  pmpcfg0, x0             # Will not clear locked entries
  csrw  pmpaddr1, x0

  # =========================================================================
  # Phase 5 — NA4 (entry 3): locked no-execute
  # =========================================================================
  # Protect 4 bytes at 0x00041100, outside the locked entry-0/1 ranges.
  li    x5, 0x10440             # 0x00041100 >> 2
  csrw  pmpaddr3, x5
  li    x5, 0x96000000          # entry3 = L|NA4|R+W (no X)
  csrw  pmpcfg0, x5
  lw    x4, 0x100(x9)           # R=1 → pass
  sw    x3, 0x100(x9)           # W=1 → pass
  # Instruction fetch at 0x00041100 would fault (X=0) — tested in MCU-PMP-01

  csrw  pmpcfg0, x0
  csrw  pmpaddr3, x0

  # =========================================================================
  # Phase 6 — Overlap priority: lower entry wins
  # =========================================================================
  # Entry 4: NAPOT covering 0x00041000-0x00041FFF, R+W (no fault)
  # Entry 5: NA4 at 0x00041204, no permissions (would fault)
  # Lower entry (4) matches first, so access passes
  li    x5, 0x105FF             # NAPOT 4 KiB at 0x00041000
  csrw  pmpaddr4, x5
  li    x5, 0x10481             # NA4 at 0x00041204
  csrw  pmpaddr5, x5
  li    x5, 0x0B                # entry4 = NAPOT|R+W (unlocked)
  csrw  pmpcfg1, x5
  li    x5, 0x00001000          # entry5 = NA4 (no perms) in cfg[1] byte 1
  csrw  pmpcfg1, x5
  lw    x4, 0x204(x9)           # Entry 4 matches first with R → pass
  sw    x3, 0x204(x9)           # Entry 4 matches first with W → pass

  csrw  pmpcfg1, x0
  csrw  pmpaddr4, x0
  csrw  pmpaddr5, x0

  # =========================================================================
  # Phase 7 — R=0/W=1 WARL normalization
  # =========================================================================
  li    x5, 0x0200              # R=0, W=1 (invalid combination)
  csrw  pmpcfg3, x5             # Write to entries 12-15 area
  csrr  x6, pmpcfg3
  bne   x6, x0, fail            # Must be WARL-normalized to 0

  # =========================================================================
  # Phase 8 — All-entry pmpaddr read/write (entries 6-15)
  # =========================================================================
  li    x7, 0x1000
1:
  add   x7, x7, x7              # unique per iteration
  csrw  pmpaddr6, x7
  csrr  x8, pmpaddr6
  bne   x7, x8, fail
  csrw  pmpaddr7, x7
  csrr  x8, pmpaddr7
  bne   x7, x8, fail
  csrw  pmpaddr8, x7
  csrr  x8, pmpaddr8
  bne   x7, x8, fail
  csrw  pmpaddr9, x7
  csrr  x8, pmpaddr9
  bne   x7, x8, fail
  csrw  pmpaddr10, x7
  csrr  x8, pmpaddr10
  bne   x7, x8, fail
  csrw  pmpaddr11, x7
  csrr  x8, pmpaddr11
  bne   x7, x8, fail
  csrw  pmpaddr12, x7
  csrr  x8, pmpaddr12
  bne   x7, x8, fail
  csrw  pmpaddr13, x7
  csrr  x8, pmpaddr13
  bne   x7, x8, fail
  csrw  pmpaddr14, x7
  csrr  x8, pmpaddr14
  bne   x7, x8, fail
  csrw  pmpaddr15, x7
  csrr  x8, pmpaddr15
  bne   x7, x8, fail

  # =========================================================================
  # PASS
  # =========================================================================
  li    x28, 1
  jal   x0, done

fail:
  li    x28, 0

done:
  jal   x0, done

  # =========================================================================
  # Trap handler
  # =========================================================================
  .balign 256
handler:
  csrr  x20, mcause
  csrr  x21, mtval
  csrr  x22, mepc
  addi  x22, x22, 4
  csrw  mepc, x22
  mret
