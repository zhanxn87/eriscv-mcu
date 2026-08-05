# eRISCV MCU Debug 1.0 Minimal Target

This document freezes the external debug target for `eriscv-m0`, `eriscv-m1`,
and `eriscv-m2`:

`RISC-V Debug Specification 1.0 Minimal, single-hart, JTAG DTM/DMI target`.

It replaces earlier informal `full Debug v0.13` wording. It is not a full
debugger ecosystem or commercial signoff claim.

## Target Scope

| Area | Family target |
| --- | --- |
| Standard | RISC-V Debug Specification 1.0 Minimal |
| Harts | one hart, hart ID 0 |
| Transport | JTAG DTM with DMI |
| Debug Module | single Debug Module |
| Run control | `dmactive`, `haltreq`, `resumereq`, halted/running status |
| Required abstract access | all integer GPRs, `dcsr`, and `dpc` |
| Debug CSRs | `dcsr`, `dpc`, `dscratch0`; `dscratch1` may remain implementation-defined |
| Access mechanism | Abstract Command register access |
| Reset behavior | documented `dmactive`, hart reset visibility, and sticky reset status |

## Explicit Non-Goals

The minimal target does not require:

| Feature | Status |
| --- | --- |
| Multiple harts | deferred |
| Hart array masks | deferred |
| Halt groups / resume groups | deferred |
| System Bus Access | implemented for 32-bit DMEM accesses through DMI; broader system-bus access remains deferred |
| Program Buffer | deferred |
| Full CSR/FPR/vector abstract access | deferred |
| Trigger module | `mcontrol` and `icount` implemented; broader trigger types deferred |
| Trace | deferred |
| Debug security lifecycle / authentication policy | deferred |

## Verification boundary

Required RTL and directed coverage is defined by the product verification
contracts and test inventories. Dated results and release gaps are in the
[MCU Evidence Snapshot](../Verification/eriscv-mcu-simulation-evidence-snapshot.md).

RTL JTAG/DMI evidence does not establish OpenOCD/GDB interoperability. That
requires the separate
[OpenOCD/GDB board-smoke contract](../Verification/eriscv-mcu-openocd-gdb-smoke.md) on FPGA
or compatible JTAG hardware.
