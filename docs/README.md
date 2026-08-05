# eRISCV MCU Documentation

This directory separates current contracts and dated evidence. A fact has one
current owner.

Read a product's `README.md` first for its local contract and entry points.
Use this index only to locate family-wide documents and result owners.

## Command entry point

From the repository root, run `make help` first. It is the maintained command
index for lint, native/Docker ACT4 generation, standard regression, focused
ModelSim diagnostics, software workloads, board debug, and cleanup. See the
[root Quick start](../README.md#quick-start) for installation prerequisites and
the recommended first checks.

## Current contracts

| Topic | Owner | Scope |
| --- | --- | --- |
| Portfolio boundary | [MCU Architecture Claim](eriscv-mcu-architecture-claim.md) | Product profiles, exclusions, and claim rules. |
| Address allocation | [Address-Space Specification v2.0](Spec/eriscv-mcu-address-space-spec-v2.0.md) | CPU-visible global windows and product applicability. |
| Local-memory semantics | [Local Memory Architecture Specification](Spec/eriscv-mcu-memory-architecture-spec-v1.0.md) | IMEM/DMEM behavior, boot, arbitration, and fetch permissions. |
| Peripheral integration | [Peripheral Integration Contract](Spec/eriscv-mcu-peripheral-integration.md) | APB-to-PLIC boundary and common peripheral rules. |
| Testbench performance profiling | [TB Performance-Profile Specification](Spec/eriscv-mcu-tb-performance-profile-spec-v1.0.md) | Diagnostic metric definitions, causal boundaries, and required profile verification. |
| Subsystem specifications | [Specification map](Spec/RISC-V%20Official%20Specification%20Map.html), [PLIC](Spec/eriscv-mcu-plic-spec-v1.0.md), [clock/reset](Spec/eriscv-mcu-clkrst-spec-v1.0.md), [HPM](Spec/eriscv-mcu-hpm-spec-v1.0.md), [Debug](Spec/eriscv-mcu-debug-1.0-minimal.md), and [M1 U-mode](Spec/eriscv-mcu-u-mode-spec.md) | Normative subsystem behavior and architecture coverage. |

## Current evidence and engineering records

| Topic | Owner | Scope |
| --- | --- | --- |
| Dated verification evidence | [MCU Evidence Snapshot](Verification/eriscv-mcu-simulation-evidence-snapshot.md) | Regression results, commands, tool versions, and waivers. |
| FPGA timing and area | [FPGA Timing and Area Evidence](Performance/eriscv-mcu-fpga-timing-area-evidence.md) | Routed report provenance and current M0/M1/M2 figures. |
| Performance dashboard and method | [Product Manual: Performance](product-manual/performance.html) | Current measurement boundaries plus reader-facing M0/M1/M2 trends and workload snapshots. |
| Implemented performance work | [MCU Performance Optimization Ledger](Performance/eriscv-mcu-performance-optimization-ledger.md) | Product-by-product optimization ledger, evidence status, and PPA caveats. |
| External debug smoke contract | [OpenOCD/GDB Board-Smoke Contract](Verification/eriscv-mcu-openocd-gdb-smoke.md) | Required hardware-debug interoperability evidence. |

## Reader-facing documentation

- [HTML product manual](product-manual/index.html) is the English reader-facing
  family guide. It summarizes contracts and evidence but does not replace them.

When updating a result, update only its owner and link to it from other
documents. Do not duplicate pass counts, PPA figures, benchmark measurements,
or release state.
