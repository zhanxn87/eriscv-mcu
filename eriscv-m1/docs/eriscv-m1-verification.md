# eRISCV-M1 Verification Contract

This contract defines the verification method, required coverage, and evidence
boundaries for the M1 architecture claim. Dated results, pass counts, commands,
and waivers belong in the
[MCU Evidence Snapshot](../../docs/Verification/eriscv-mcu-simulation-evidence-snapshot.md).

## Evidence Method

- Verilator product-directed core/SoC regression is the default path. ModelSim
  is used explicitly for focused single-test debugging and waveform inspection.
- ACT4 runs only in the core TB. Boot transport, boot-image loading, and `crt0`
  initialization run only in the SoC TB.
- Exact runnable tests, inputs, and runners are owned by the
  [design-verification inventory](../dv/README.md) and
  [ACT4 profile](../compliance/riscv-arch-test/README.md).
- Product-local RTL, DV, software, compliance, and FPGA artifacts are required;
  evidence from another product does not close an M1 requirement.

## Required Coverage

| Area | Required coverage |
| --- | --- |
| ISA and M extension | Architectural tests plus directed multiply/divide operations, corner cases, dependencies, interrupts, traps, reset, and debug boundaries |
| Privilege and PMP | M/U transitions, traps, MPRV, `mcounteren`, PMP CSR/WARL/lock behavior, fetch/load/store permissions, and precise fault state |
| HPM and WFI | Counter/alias/inhibit behavior, supported events, wait/stall/debug/interrupt observability, and timer correlation |
| SoC platform | v2 map, boot, local-memory ownership, bus errors, CLINT, PLIC, Debug 1.0 Minimal, and peripherals |
| Software | `rv32imc_zicsr_zifencei_zicntr_zihpm_zihintpause` / `ilp32` startup, linker, HAL, BSP examples, and declared RTOS smoke |
| Release | Dated regression snapshot, tool versions, routed FPGA evidence, performance/area data, physical-board status, and known-deviation list |

## Evidence Boundaries

- ACT executable-data payloads may use manifest-declared `exec_data_mirror` in
  the core TB only; this is not a product unified-memory claim.
- PMP is a CPU-access contract. Privileged boot/debug IMEM programming and
  pre-EX instruction-fetch issuance are outside the CPU PMP claim.
- A halt request received while an RV32M operation is active is accepted only
  at a retirement boundary. The M/D result retires before the halt, and the
  reported debug PC is the following instruction. Partial iterative state is
  not architecturally observable.
- Product-local M/D interrupt, reset, trap, and debug-boundary tests are
  required; M0 results are not substitute evidence.
