# eRISCV MCU Verification Evidence Snapshot

**Evidence capture:** 2026-08-04. This document owns the current
product-local regression status and retained result counts. It does not own
benchmark measurements, routed PPA figures, or board-debug transcripts.

## Method and boundary

- Verilator is the default regression backend. ModelSim is reserved for focused
  debug and waveform inspection.
- A product `full` target runs its selected core-directed tests, ACT4 profile,
  and SoC-directed regression. ACT4 executes in the core TB; boot transport
  and `crt0` initialization execute in the SoC TB.
- This versioned snapshot is the retained result record. The checked-in product
  runners and test inventories own commands and testcase selection; per-run
  `regression_logs/summary.json` files are ignored generated output.

## Current product-local regression baseline

| Product | Core | SoC | Total | Result |
| --- | ---: | ---: | ---: | --- |
| M0 | 105 | 41 | 146 | PASS — 0 failed |
| M1 | 139 | 42 | 181 | PASS — 0 failed |
| M2 | 221 | 43 | 264 | PASS — 0 failed |

M2 coverage includes RV32F, Zcf, standard B (Zba/Zbb/Zbs), PMP/HPM, System SRAM, generic DMA, and
product-directed SoC behavior. These results supersede the older M1 183/183
and pre-M2-closure snapshots.

## Evidence boundaries

- The [product manual performance page](https://eriscv-mcu-product-manual.zhanxnse.chatgpt.site/performance)
  owns controlled benchmark conditions and results.
- [FPGA Timing and Area Evidence](../Performance/eriscv-mcu-fpga-timing-area-evidence.md)
  owns routed timing, utilization, and board-status provenance. Its latest M2
  routed report still has a small 100 MHz setup violation; full simulation
  PASS is not FPGA timing closure.
- Physical-board evidence is separate from simulation. M0 retains a UART boot
  smoke; M1/M2 board and OpenOCD/GDB closure remain open.

## Update rule

Update this snapshot only after a complete product `full` run. Record its date,
core and SoC totals, backend, and failures from that run's console or generated
summary; do not copy those totals into product architecture contracts or
historical plans.
