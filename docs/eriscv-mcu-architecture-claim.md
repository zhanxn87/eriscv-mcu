# eRISCV MCU Architecture Claim

This is the frozen product-family contract, not a claim of commercial release
readiness. A feature is claimable only when product-local RTL, software,
directed/architectural tests, and reproducible evidence agree. Dated results
and waivers belong to the
[MCU Evidence Snapshot](Verification/eriscv-mcu-simulation-evidence-snapshot.md).

## Product profiles

| Product | ISA / ABI / privilege | Additions over lower profile | Exclusions |
| --- | --- | --- | --- |
| M0 | `RV32IC_Zicsr_Zifencei_Zicntr_Zihpm_Zihintpause`; `ilp32`; M-mode | 32-source PLIC, Debug 1.0 Minimal, freestanding BSP | M, B, PMP, U-mode, caches |
| M1 | `RV32IMC_Zicsr_Zifencei_Zicntr_Zihpm_Zihintpause`; `ilp32`; M/U modes | multi-cycle M/D; 16-entry PMP | B, F/D/Zfa, S-mode/address translation, caches |
| M2 | `RV32IMFC_Zicsr_Zifencei_Zicntr_Zihpm_Zihintpause_Zba_Zbb_Zbs_Zcf`; `ilp32f`; M/U modes | faster core, RV32F, standard B, 128 KiB ITCM/DTCM, 512 KiB System SRAM, generic DMA | D, Zfa, S-mode/address translation, caches, Zbc, XRAM |

M2 is single-precision RV32F only. Its FPU integration pins the selected
CVFPU/FPnew revision and configuration; no deferred floating-point or crypto
extension is implied.

## Common platform

All products provide little-endian RV32 execution, reset/trap/`mret`, CSR
access, `WFI`, and MSIP/MTIP/MEIP. `WFI` stops fetch until a pending interrupt
or debug request; it makes no power-gating claim.

- PLIC: 32 global sources (IDs 1--32; 0 reserved), one hart and one M-mode
  context. Register map and semantics are in the
  [PLIC specification](Spec/eriscv-mcu-plic-spec-v1.0.md).
- Debug: RISC-V Debug 1.0 Minimal over the documented single-hart JTAG DTM/DMI
  interface.
- Counters: 64-bit `cycle`, `time`, `instret`, and HPM3--HPM6 only; details
  are in [HPM v1.0](Spec/eriscv-mcu-hpm-spec-v1.0.md). `pause` is legal and
  side-effect free, with no promised delay or power action.
- Software contract: a versioned boot/reset, memory/peripheral map, bus-error
  behavior, linker/startup code, and BSP/HAL.

## Memory, DMA, and protection

M0/M1 use deterministic cacheless IMEM/DMEM as defined by the
[Local Memory Architecture Specification](Spec/eriscv-mcu-memory-architecture-spec-v1.0.md).
M2 preserves that model and adds arbitrated System SRAM for CPU/DMA buffers.
No product implements an instruction/data cache, cache maintenance, or DMA
coherency mechanism. The generic DMA ABI and System-SRAM-only firewall are in
[the M2 descriptor specification](../eriscv-m2/docs/eriscv-m2-dma-descriptor-spec.md).

M1 and M2 each implement 16 PMP entries with full RV32 `pmpaddr` bits [33:2],
TOR/NA4/NAPOT, R/W/X, and lock. PMP covers fetch, loads, and stores; unlocked
entries do not restrict ordinary M-mode access, while locked entries and U-mode
follow the privileged-specification rules. M0 excludes PMP.

The reusable M1/M2 RTL exposes `ENABLE_PMP_P` and `PMP_ENTRY_COUNT_P` at both
the SoC and core boundaries. Supported counts are 4, 8, and 16; the frozen M1
and M2 product configurations are `ENABLE_PMP_P=1` and
`PMP_ENTRY_COUNT_P=16`. A reduced or disabled configuration is a derivative
implementation choice, not a change to this product claim. In particular,
`ENABLE_PMP_P=0` removes the PMP CSR/check/fault hardware and must not be used
to claim M/U isolation.

## Explicit exclusions and release rule

Secure boot, debug lifecycle control, atomics, supervisor mode, AIA, all
caches, `Zbc`, and cryptographic extensions are outside this freeze. Peripheral
DMA endpoints and Ethernet/Wi-Fi DMA masters are future work; M2 currently
claims only the generic System-SRAM channel.

Unsupported features must remain explicitly unsupported or deferred. Product
architecture and verification contracts take precedence over this family-level
summary when a detail differs.
