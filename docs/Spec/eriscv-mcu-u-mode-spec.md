# eRISCV-M1 U-mode Specification v1.0

## 1. Scope

This is the implemented M/U-only RV32IMC contract for `eriscv-m1`, inherited
by M2; M0 remains M-mode-only. It provides PMP-based isolation for a small
M-mode kernel and U-mode tasks, not S-mode, virtual memory, or Linux support.
Directed and ACT evidence covers transitions, PMP, MPRV, and `mcounteren`; dated
results are in the
[MCU Evidence Snapshot](../Verification/eriscv-mcu-simulation-evidence-snapshot.md).

## 2. Architectural profile

| Item | Contract |
| --- | --- |
| ISA | `RV32IMC_Zicsr_Zifencei_Zicntr_Zihpm` plus U-mode privilege support |
| Implemented modes | M and U only; reset enters M-mode |
| Trap target | M-mode only, through `mtvec` |
| Address translation | None; physical addresses only |
| PMP | Existing 16-entry PMP, mandatory for all U-mode instruction/data accesses |
| MPRV | `mstatus.MPRV` applies `MPP` as the effective privilege for M-mode loads and stores only |
| Counter delegation | `mcounteren.CY/TM/IR/HPM3..6` gates U-mode reads of the corresponding counter aliases |
| Interrupts | Existing MSIP/MTIP/MEIP; all enter M-mode; no delegation |
| Supervisor/virtualization | Not implemented (`S`, `H`, `satp`, delegation CSRs, paging) |
| User ABI | Freestanding `ilp32`; no Linux ABI or system-call ABI claim |

## 3. Privilege state and trap transitions

`current_privilege` is explicit architectural state. It resets to M-mode.

| Event | `current_privilege` after event | Required state update |
| --- | --- | --- |
| Any synchronous exception or enabled interrupt | M | `mepc`, `mcause`, `mtval` record the event; `MPP` receives the prior mode; `MPIE <- MIE`; `MIE <- 0` |
| `MRET` executed in M-mode | `mstatus.MPP` | `MIE <- MPIE`; `MPIE <- 1`; `MPP <- U` (the least privileged implemented mode); PC redirects to `mepc` |
| `MRET` executed in U-mode | U until trap | Illegal-instruction exception |
| Reset | M | Existing reset CSR values apply |

`mstatus.MPP` supports only `00` (U) and `11` (M). Unsupported encodings are
WARL-canonicalized to `11` (M). This is deliberately fail-safe: software must
write `00` explicitly before using `MRET` to enter a task.

## 4. U-mode instruction and CSR rules

| Operation in U-mode | Required result |
| --- | --- |
| Ordinary RV32IMC instruction | Executes, subject to PMP |
| `ECALL` | Trap to M-mode with exception code 8 (`environment call from U-mode`) |
| `EBREAK` | Breakpoint exception (code 3); no U-mode debug-entry claim in v0.1 |
| `MRET`, `DRET` | Illegal-instruction exception |
| `WFI` | Executes normally when `mstatus.TW=0`; when `TW=1`, U-mode WFI raises an illegal-instruction exception (the implementation time limit is zero) |
| CSR access to any M/debug/PMP CSR | Illegal-instruction exception |
| User counter aliases (`cycle`, `time`, `instret`, `hpmcounter3`–`hpmcounter6`) | Read-only when the corresponding `mcounteren` bit is 1; otherwise illegal-instruction exception |

No U-mode CSR is exposed: `scounteren`, `ustatus`, `uie`, `utvec`, user traps,
and user interrupts are outside scope. `mcounteren` remains M-mode-only.

`mcounteren` is an M-mode CSR. Bits CY, TM, IR, and HPM3..6 are WARL-writable;
all higher HPM bits are read-only zero. The enabled aliases are read-only in
U-mode and continue to expose the same counters as their M-mode aliases.

`mstatus.MPRV` is WARL-writable in M-mode. When MPRV=1 and the current mode is
M, loads and stores use `mstatus.MPP` as their effective privilege for PMP
checks. Instruction fetch, trap entry, and accesses executed while already in
U-mode retain the current privilege. MRET to U-mode clears MPRV.

## 5. PMP enforcement

The current M1 PMP CSR format, priority ordering, TOR/NA4/NAPOT matching, and
multi-byte boundary checks are retained. U-mode changes the enforcement rule:

1. Every U-mode instruction fetch, load, and store must match a PMP entry.
2. The lowest-numbered matching entry decides R/W/X permission, regardless of
   its lock bit.
3. A no-match access faults in U-mode.
4. A partially matched multi-byte access faults.
5. In M-mode, existing locked-entry behavior is preserved. Unlocked entries do
   not restrict ordinary M-mode access.
6. M-mode loads and stores execute with U-mode PMP enforcement when MPRV=1 and
   MPP=U; instruction fetch is never affected by MPRV.

PMP faults use the existing access-fault exception causes: instruction=1,
load=5, store/AMO=7. `mtval` records the faulting byte address. Enforcement is
required at instruction fetch and at data access; it must not depend solely on
the architectural instruction decode path.

### Build-time PMP configuration

`soc` and `riscv_core` both expose the same compile-time parameters:

| Parameter | Supported values | Frozen M1/M2 product value |
| --- | --- | --- |
| `ENABLE_PMP_P` | `0`, `1` | `1` |
| `PMP_ENTRY_COUNT_P` | `4`, `8`, `16` | `16` |

When enabled, the visible PMP CSR window is exactly the selected prefix:
`pmpcfg0` through `pmpcfg(N/4-1)` and `pmpaddr0` through `pmpaddr(N-1)`.
All higher PMP CSR addresses are unimplemented and therefore trap as illegal
CSR accesses. `ENABLE_PMP_P=0` elaborates no PMP CSR state, checker, D-side
fault packet, or PMP-CSR pipeline barrier; all PMP CSRs are unimplemented.
That configuration retains the generic M/U machinery but provides no hardware
PMP enforcement, so it is not valid for this M/U isolation contract.

## 6. Interrupts, debug, and observability

All implemented interrupts are machine interrupts and trap to M-mode. While
executing U-mode they are globally eligible regardless of `mstatus.MIE`; while
executing M-mode they retain the existing `MIE` gate. The trap state update in
section 3 preserves the M-mode interrupt-enable state for `MRET`.

Existing external Debug Module halt/resume and abstract-register access remain
supported for a halted U-mode task. Resume continues in the halted task's
architectural privilege mode. Trigger matching applies to U-mode instruction
and data accesses. `dcsr.ebreaku` and user-mode single-step semantics are
deferred; U-mode `EBREAK` is required to take the normal breakpoint trap.

## 7. Software contract

The M-mode kernel is responsible for:

1. configuring PMP regions for user text, user data/stack, and kernel-only
   memory;
2. writing a U-mode entry address to `mepc`, writing `MPP=U`, then issuing
   `MRET`;
3. saving task context in M-mode on a trap and selecting the next task;
4. validating ECALL arguments before touching user pointers.

The M1 FreeRTOS U-mode smoke applies this contract to two static tasks.
`MCU-UMODE-01` and `MCU-UMODE-EXT-01` provide the directed architectural
coverage for ECALL/trap, PMP faulting, MPRV, and counter delegation.

## 8. Verification exit criteria

### Directed evidence

- `MCU-UMODE-01`: M/U transition, U-mode M-CSR trap, and PMP load/fetch denial;
- `MCU-UMODE-EXT-01`: MPRV effective privilege and `mcounteren` delegation and
  revocation.

### Required directed coverage

- reset to M; M-mode sets `MPP=U`; `MRET` enters U at `mepc`;
- U-mode `ECALL`, `EBREAK`, `MRET`, `WFI`, and M-CSR access produce the required
  causes and trap state, including both `TW=0` and `TW=1` WFI behavior;
- M-mode, U-mode, and interrupted U-mode `MRET` state restoration;
- U-mode PMP allow/deny coverage for fetch, load, store, no-match, boundary,
  TOR, NA4, and NAPOT;
- MPRV M-mode load/store checks with MPP=U, including no-match denial;
- `mcounteren` WARL behavior plus U-mode counter-alias delegation and revocation;
- machine timer and external interrupts arriving in U-mode;
- debug halt/resume from U-mode and trigger/PMP interaction;
- BSP context-switch/isolation example.

### Regression and compliance

- The U-mode ACT subset, including PMPU MPRV and `ZicntrU`, is generated and
  tracked. Its result belongs in the [MCU Evidence Snapshot](../Verification/eriscv-mcu-simulation-evidence-snapshot.md).
- Verilator is the default regression backend; ModelSim is reserved for focused
  debug and waveform inspection.

## 9. Explicit exclusions

This contract does not add S-mode, paging, delegation, user interrupt CSRs,
atomics, or a secure-boot claim.
