/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# External debug halt/resume smoke test.
#
# The testbench asserts debug_halt_req_i while this program is running,
# waits for debug_halted_o, then resumes execution through debug_resume_req_i.
# It subsequently enters Debug Mode through EBREAK, proving the resumed
# external session does not leave the hart permanently halted.

  addi x1, x0, 1
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  lui   x5, 0x8
  csrrw x0, dcsr, x5
  ebreak
  addi  x2, x0, 2
  csrrs x6, dscratch0, x0
done:
  jal  x0, done

  .org 0x100
debug_handler:
  addi  x3, x0, 3
  csrrs x4, dpc, x0
  addi  x7, x0, 7
  csrrw x0, dscratch0, x7
  dret
