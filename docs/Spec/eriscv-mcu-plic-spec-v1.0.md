# eRISCV MCU PLIC Specification v1.0

**Status:** Frozen common-platform interface for `eriscv-m0`, `eriscv-m1`, and
`eriscv-m2`.

## 1. Scope

This is the family software-visible PLIC contract: one hart, one M-mode
context, 32 global sources, and a RISC-V PLIC v1.0.0-compatible layout. ID 0
is reserved; the selected interrupt is `MEIP` (cause 11). CLINT `MSIP`/`MTIP`
remain local interrupts. This document owns layout, priority width, source IDs,
reset, and claim/complete behavior; source additions require a new version.

## 2. Fixed configuration

| Item | Value |
| --- | --- |
| PLIC base address | `0x0C00_0000` |
| Implemented window | `0x0C00_0000`–`0x0C20_0FFF` (`0x0020_1000` bytes) |
| Harts / contexts | one hart / one M-mode context |
| Sources | IDs 1–32; ID 0 reserved |
| Priority width | 3 bits; values 0–7 |
| Interrupt input type | level-high |
| Target interrupt | machine external interrupt only (`MEIP`) |

All priority, pending, enable, in-service, and threshold state resets to zero;
therefore `MEIP` is low. Priority zero is stored but never eligible.

## 3. Source allocation and integration

This source-number ABI applies to M0, M1, and M2. Unimplemented sources stay
low; reserved IDs are never reassigned.

| ID | Fixed integration source | SoC integration |
| --- | --- | --- |
| 0 | Reserved; no interrupt | None |
| 1 | UART0 aggregated interrupt | Internal peripheral signal |
| 2 | TIMER0 expiry interrupt | Internal peripheral signal |
| 3 | SPI0 transfer-done interrupt | Internal peripheral signal |
| 4 | Watchdog pre-timeout interrupt | Internal peripheral signal |
| 5 | Generic DMA completion/error | Wired on M2; reserved and tied low on M0/M1 |
| 6–16 | Named future device slots | Reserved and tied low |
| 17–32 | Board and external expansion slots | `ext_irq_i[0]`–`ext_irq_i[15]`, synchronized to `clk` before PLIC sampling; baseline FPGA wrappers tie them low |

`ext_irq_i` is the only product-level external input and maps only IDs 17--32;
each line is two-flop synchronized before level-sensitive PLIC sampling. No
unlisted peripheral may consume a reserved ID without updating this table and
the BSP. M2 DMA source 5 remains high until software clears its W1C status,
then completes the claim.

## 4. Register map

All registers are 32-bit little-endian DBus words.  Priority and threshold
registers implement only bits `[2:0]`; reads return zero in higher bits and
writes retain only those three bits.  Byte enables apply to writable words.

| Offset | Address | Register | Access | Defined contents |
| --- | --- | --- | --- |
| `0x0000` | `0x0C00_0000` | priority 0 | Reserved | Invalid access; source 0 has no priority |
| `0x0004`–`0x0080` | `0x0C00_0004`–`0x0C00_0080` | priority 1–32 | R/W | Bits `[2:0]` priority of matching source |
| `0x1000` | `0x0C00_1000` | pending word 0 | R | Bits 1–31 are pending IDs 1–31; bit 0 is zero |
| `0x1004` | `0x0C00_1004` | pending word 1 | R | Bit 0 is pending ID 32; bits 1–31 are zero |
| `0x2000` | `0x0C00_2000` | enable word 0 | R/W | Bits 1–31 enable IDs 1–31; bit 0 is zero |
| `0x2004` | `0x0C00_2004` | enable word 1 | R/W | Bit 0 enables ID 32; bits 1–31 are zero |
| `0x20_0000` | `0x0C20_0000` | threshold | R/W | Bits `[2:0]` target threshold |
| `0x20_0004` | `0x0C20_0004` | claim / complete | R / W | Read claims an ID; write completes an ID |

Pending registers are read-only: writes receive a normal response but do not
change pending state.  The PLIC responds to every DBus access within its
implemented window.  A word-aligned access to an unlisted offset, a priority-0
access, or an unaligned access returns a DBus error; it has no PLIC state side
effect.  A completion write of zero or an ID above 32 is accepted with no state
change and no DBus error.

## 5. Arbitration and delivery

An ID is eligible when all of these are true:

1. Its input has set its pending bit.
2. Its enable bit is one.
3. It is not in service.
4. Its priority is strictly greater than the target threshold.

`MEIP` is asserted whenever at least one ID is eligible.  The claimed ID is the
eligible source with the numerically greatest priority.  If priorities tie, the
numerically lowest source ID wins.  This tie rule is part of the ABI.

Reading claim/complete returns the current selected ID, or zero if none is
eligible.  A nonzero claim read atomically clears that ID's pending bit and
marks it in service.  Software completes it by writing the claimed nonzero ID
to the same address, which clears its in-service state.  Completing a different
valid ID only clears that ID's in-service state; software must therefore write
back exactly the ID it claimed.

Inputs are level-sensitive.  A high source becomes pending until it is claimed.
If it remains high after completion, it becomes pending again on a subsequent
cycle.  Interrupt handlers should clear the underlying device condition before
completion when a single service instance is intended.

## 6. Software sequence

For source `N`, machine firmware shall:

1. Set `priority[N]` to 1–7.
2. Set enable bit `N` in the appropriate enable word.
3. Set threshold to a value lower than the source priority (normally zero).
4. Enable `mie.MEIE` and global `mstatus.MIE` as required.
5. On machine-external interrupt, read claim/complete, service the returned
   nonzero source, clear its device condition, and write the same ID to complete.

The PLIC does not configure device-local interrupt enables or clear device
status.  Firmware owns those operations at the UART0, TIMER0, SPI0, or future
source peripheral register block.

## 7. Verification and implementation traceability

M0/M1 implement `rtl/soc/plic.sv` and use `dv/soc/tb/tb_plic_agent.sv`.
Required evidence covers MMIO, MEIP, claim/complete, applicable external IDs,
threshold filtering, priority ordering, and the lower-ID tie rule. M2 uses the
same interface with DMA source 5; dated results are in the
[MCU Evidence Snapshot](../Verification/eriscv-mcu-simulation-evidence-snapshot.md).
