/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# M0 UART RX-to-TX directed test.
#
# The TB injects one serial byte. The program waits for RXDATA, reads it into
# x5, then waits for TX-ready and sends that same byte back through uart_tx_o.

.globl _start
_start:

lui  x1, 0x40000
addi x2, x0, 8
sw   x2, 12(x1)
addi x2, x0, 3
sw   x2, 16(x1)

poll_rx:
lw   x3, 8(x1)
andi x3, x3, 2
beq  x3, x0, poll_rx
lw   x5, 4(x1)

poll_tx:
lw   x3, 8(x1)
andi x3, x3, 1
beq  x3, x0, poll_tx
sw   x5, 0(x1)

done:
jal  x0, done
