# eRISCV MCU Hardware Performance Monitoring Specification v1.0

**Status:** Frozen family contract for `eriscv-m0`, `eriscv-m1`, and
`eriscv-m2`. All provide four 64-bit programmable counters HPM3--HPM6, their
high halves, `mhpmevent3..6`, `mcountinhibit.HPM3..HPM6`, and documented
read-only aliases. Incompatible software-visible changes require a major
version update.

Current product evidence is owned by the
[MCU Evidence Snapshot](../Verification/eriscv-mcu-simulation-evidence-snapshot.md).

## 1. Implemented product configuration

| Product | Zicntr | Zihpm | Implemented counters | Programmable HPM counters |
| --- | --- | --- | --- | ---: |
| eRISCV-M0 | Yes | Yes | `mcycle`, `minstret`, `time`, `mhpmcounter3`-`mhpmcounter6` | 4 |
| eRISCV-M1 | Yes | Yes | `mcycle`, `minstret`, `time`, `mhpmcounter3`-`mhpmcounter6` | 4 |
| eRISCV-M2 | Yes | Yes | `mcycle`, `minstret`, `time`, `mhpmcounter3`-`mhpmcounter6` | 4 |

> **Implemented Zihpm subset:** all three products implement only HPM3-HPM6.
> In M-mode, unimplemented HPM7-HPM31 user-counter aliases (including high
> halves) read as zero and reject writes as illegal. In M1/M2 U-mode, those
> aliases remain blocked because their `mcounteren` bits are unimplemented and
> read as zero.

## 2. Counter width and CSR model

- All counters are 64 bits wide.
- On RV32, upper halves are exposed through the corresponding high-half CSRs.
- Counters wrap modulo 2^64.
- Counter-overflow interrupts and Sscofpmf are not implemented in v1.0.
- `time`/`timeh` read the platform time source; the preferred source is
  ACLINT/MTIMER `mtime`.
- The documented `mtime` tick frequency is independent of the active core clock
  used by `mcycle` and must be published in each product integration manual.

## 3. `mhpmeventN` format

```text
mhpmeventN[7:0]   = eRISCV event ID
mhpmeventN[31:8]  = reserved, reads as zero
```

- Event ID `0x00` disables counting.
- Unsupported event IDs are WARL-converted to `EVENT_NONE`.
- Each counter counts one selected event.
- No multi-event OR mask, chaining, threshold event, or sampling mode is defined in v1.0.

## 4. Unified event IDs

| Event ID | Name | Definition |
| --- | --- | --- |
| `0x00` | `EVENT_NONE` | Counter disabled |
| `0x01` | `LOAD_RETIRED` | Retired load instructions |
| `0x02` | `STORE_RETIRED` | Retired store instructions |
| `0x03` | `BRANCH_RETIRED` | Retired conditional branches |
| `0x04` | `BRANCH_TAKEN` | Taken conditional branches |
| `0x05` | `CONTROL_TRANSFER_RETIRED` | Retired JAL, JALR, MRET, and other implemented control-transfer instructions |
| `0x06` | `EXCEPTION_TAKEN` | Trap entry caused by a synchronous exception |
| `0x07` | `INTERRUPT_TAKEN` | Trap entry caused by an accepted interrupt |
| `0x08` | `IFETCH_WAIT_CYCLES` | Cycles stalled while waiting for instruction fetch completion |
| `0x09` | `DATA_WAIT_CYCLES` | Cycles stalled while waiting for data load/store completion |
| `0x0A` | `PIPELINE_STALL_CYCLES` | Cycles in which a valid instruction is blocked and the pipeline cannot advance normally |
| `0x0B` | `LOAD_USE_STALL_CYCLES` | Cycles stalled due to a load-use dependency |
| `0x0C` | `MUL_BUSY_CYCLES` | Cycles during which the multiplier is processing a valid request |
| `0x0D` | `DIV_BUSY_CYCLES` | Cycles during which the divider is processing a valid request |
| `0x0E` | `WFI_CYCLES` | Cycles spent in the architectural WFI wait state while the counter clock is running |
| `0x0F` | `BUS_ERROR` | Accepted instruction-bus or data-bus error events |
| `0x10` | `COMPRESSED_RETIRED` | Retired 16-bit compressed instructions |
| `0x11` | `PMP_DENY` | Instruction, load, or store accesses denied by PMP |
| `0x12` | `DEBUG_ENTRY` | Entries into Debug Mode |
| `0x13` | `IRQ_PENDING_CYCLES` | Cycles in which at least one interrupt is pending and observable by the hart |
| `0x14` | `PREFETCH_WAIT_CYCLES` | Cycles stalled because the instruction prefetch or line buffer has no valid data |
| `0x15` | `DMA_CONTENTION_CYCLES` | Cycles in which CPU progress is blocked by generic-DMA System SRAM contention; no aggregate Ethernet/Wi-Fi DMA interpretation exists until those masters are implemented |
| `0x16`-`0x3F` | `RESERVED` | Reserved for future stable eRISCV architecture events |
| `0x40`-`0x7F` | `SOC_EVENTS` | Platform-specific SoC event encodings |
| `0x80`-`0xFF` | `EXPERIMENTAL` | Experimental events; not part of the stable software ABI |

Events may overlap: each selected counter independently counts its qualifying
condition. For example, an instruction-fetch wait cycle may also be a pipeline
stall cycle.

## 5. Default event assignment

### eRISCV-M0 and eRISCV-M1 reset defaults

| Counter | Default event |
| --- | --- |
| HPM3 | `IFETCH_WAIT_CYCLES` |
| HPM4 | `DATA_WAIT_CYCLES` |
| HPM5 | `BRANCH_TAKEN` |
| HPM6 | `INTERRUPT_TAKEN` |

### eRISCV-M2 reset defaults

| Counter | Default event |
| --- | --- |
| HPM3 | `IFETCH_WAIT_CYCLES` |
| HPM4 | `DATA_WAIT_CYCLES` |
| HPM5 | `PIPELINE_STALL_CYCLES` |
| HPM6 | `BRANCH_TAKEN` |

Software may reprogram all implemented HPM counters.

## 6. `mcountinhibit`

| Product | Implemented bits |
| --- | --- |
| eRISCV-M0 | CY, IR, HPM3-HPM6 |
| eRISCV-M1 | CY, IR, HPM3-HPM6 |
| eRISCV-M2 | CY, IR, HPM3-HPM6 |

`0` enables counting. `1` inhibits counting. Unimplemented bits read as zero.

## 7. `mcounteren`

- eRISCV-M0: not implemented; M0 has no lower privilege mode.
- eRISCV-M1: implemented. Bits CY, TM, IR, and HPM3..6 are WARL-writable and
  gate U-mode reads of the corresponding counter aliases.
- eRISCV-M2: inherits the M1 U-mode behavior. Bits CY, TM, IR, and HPM3..6
  are WARL-writable and gate U-mode reads of the corresponding counter aliases.
  HPM7..31 are unimplemented and must not be advertised.
- Reset value is zero. M-mode firmware must explicitly authorize lower-privilege access.

## 8. Behavioral definitions

- `mcycle`: increments once per active core clock cycle unless inhibited. It
  stops during debug halt. Behavior during true clock-gated WFI follows the
  available clock source and must be documented.
- `minstret`: increments only for successfully retired instructions. Flushed or
  faulting instructions do not count.
- `INTERRUPT_TAKEN`: increments when the core commits to interrupt trap entry,
  not merely when an interrupt is pending.
- `EXCEPTION_TAKEN`: increments when a synchronous exception is selected and
  trap entry occurs.
- `PIPELINE_STALL_CYCLES`: excludes reset, debug halt, and WFI wait; it counts
  cycles in which a valid instruction is blocked and normal pipeline progress
  is prevented.
- `WFI_CYCLES`: counts only while the HPM counter clock remains active.
- `BUS_ERROR`: increments once when an instruction- or data-bus error is
  accepted by the hart, not once per stalled response cycle.

## 9. Compatibility and freeze rules

- Existing event IDs shall never be reassigned.
- New stable events may only be added in currently reserved ranges.
- Future products may implement fewer counters only if they retain the same
  event IDs and deterministic CSR semantics.
- Unsupported counters and events shall have deterministic architectural behavior.
- Any incompatible software-visible change requires a major specification version update.

## 10. Evidence

This specification defines the stable HPM programming contract. Dated product
evidence and known deviations are in the
[MCU Evidence Snapshot](../Verification/eriscv-mcu-simulation-evidence-snapshot.md).
