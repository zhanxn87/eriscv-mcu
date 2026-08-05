# eRISCV-M1 Architecture Contract

## Product Claim

`eriscv-m1` is a cacheless MCU for bare-metal and RTOS-oriented firmware. Its
fixed contract is `RV32IMC_Zicsr_Zifencei_Zicntr_Zihpm_Zihintpause`, `ilp32`,
M/U modes, 16 PMP entries, and architectural `WFI`. `WFI` suspends instruction
fetch until a pending interrupt or debug request; it is not a power-gating
claim.

## M1-Specific Architecture

- Implement the complete M extension: `MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`,
  `DIVU`, `REM`, and `REMU`.
- Use an area-balanced multi-cycle multiply/divide unit. The core must stall
  and resume without losing precise trap, interrupt, or debug behavior.
- Implement 16 PMP entries with the full RV32 `pmpaddr` field
  (physical-address bits [33:2]), checking instruction fetch, loads, and
  stores.
- Provide RV32C, Zicsr, Zifencei, M-mode platform services, Debug 1.0 Minimal,
  `mcontrol`/`icount` triggers, and 32-bit DMEM DMI System Bus Access.
- Preserve `Zihintpause`: `pause` is a legal zero-effect hint; this single-hart
  implementation does not promise a delay, sleep state, or power action.

## Counter Contract

eRISCV-M1 uses the shared M-mode counter contract defined by
[HPM v1.0](../../docs/Spec/eriscv-mcu-hpm-spec-v1.0.md): 64-bit `mcycle`/`mcycleh`, `minstret`/`minstreth`,
and four 64-bit programmable HPM counters (`mhpmcounter3`–`mhpmcounter6`) with
high-half CSRs, `mhpmevent3`–`mhpmevent6` selectors, and `mcountinhibit.CY/IR/HPM3–HPM6`.
`time`/`timeh` read the CLINT `MTIME` source. `mcounteren.CY/TM/IR/HPM3..6`
is WARL-writable and gates U-mode reads of the corresponding `cycle`, `time`,
`instret`, and `hpmcounter3`–`hpmcounter6` aliases. The aliases remain
read-only views of the implemented machine counters. In M-mode, unimplemented
`hpmcounter7`–`hpmcounter31` aliases and their high halves read as zero and
reject writes; U-mode access remains blocked by their zero `mcounteren` bits.

Reset defaults, supported event encodings, WARL behavior, and inhibit semantics
are defined by the frozen
[HPM v1.0 specification](../../docs/Spec/eriscv-mcu-hpm-spec-v1.0.md).

## Common SoC Rules

- Provide MSIP, MTIP, and MEIP; MEIP is supplied by the 32-source,
  one-context PLIC v1.0.0 configuration.
- Use the common [PLIC specification](../../docs/Spec/eriscv-mcu-plic-spec-v1.0.md) for
  its register map, source allocation, priority width, reset behavior, and
  claim/complete semantics.
- Provide UART0, GPIO0, TIMER0, SPI0, WDT0, and clock/reset control in their
  fixed 64 KiB APB slots; WDT0 pre-timeout is PLIC source 4.
- Own a standalone memory map, boot/reset path, bus behavior, software, and
  verification setup.
- Remain cacheless. Do not add an instruction cache, data cache, cache
  maintenance, or DMA-coherency behavior.

## Product Address Map

M1 implements the common v2 map: 64 KiB ITCM at `0x1000_0000`, 64 KiB DTCM
at `0x1100_0000`, CLINT at `0x0200_0000`, PLIC at `0x0c00_0000`, and 64 KiB
MMIO slots from UART0 at `0x4000_0000` through clock/reset at `0x4005_0000`.
The XRAM window at `0x1200_0000` is reserved and returns a bus error; M1 makes
no XRAM or executable-data claim.

## Local Memory Contract

M1 implements 64 KiB IMEM as ITCM-like executable local SRAM and 64 KiB DMEM
as DTCM-like non-executable local SRAM. Accepted requests have one-cycle
latency under the documented single-port ownership rules. IMEM arbitration is
`boot writer > CPU DBus > IF`; DMEM Debug SBA ownership can delay a CPU data
transaction. `fence.i` is required after a DBus patch to IMEM. The full
boot-image, PMP/executability, and simulator-preload contract is defined in the common
[Local Memory Architecture Specification v1.0](../../docs/Spec/eriscv-mcu-memory-architecture-spec-v1.0.md).

For one accepted higher-priority local-memory transaction, a continuously
asserted lower-priority request is admitted on the next root clock; its own
fixed one-cycle response then follows. A run of `N` higher-priority
transactions can defer admission by `N` clocks, so the product does not claim
a global bound without constraining the competing request rate.

ACT4 is core-testbench-only. Boot-mode transport, image loading, and `crt0`
data initialization are SoC-testbench-only; ACT4 does not cover boot transport.

## Exclusions

Do not implement B, RV32F/D, Zfa, atomics, supervisor mode, AIA, `Zbc`,
cryptographic extensions, or custom ISA instructions in this product.

PMP enforces U-mode task-access policy. Unlocked entries leave ordinary M-mode
accesses unrestricted; locked entries also provide boot/firmware protection
until reset.

PMP governs CPU instruction and data accesses. The privileged boot/debug IMEM
writer is provisioning logic and outside this PMP contract; this product makes
no secure-boot or debug-lockout claim. Instruction fetch is issued before the
EX-stage PMP result, so a denied fetch traps precisely but is not claimed to
suppress the preceding fetch request.
