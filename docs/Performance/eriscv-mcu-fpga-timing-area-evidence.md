# eRISCV MCU FPGA Timing and Area Evidence

This document owns the retained routed VCU108 timing and utilization evidence.
It is FPGA implementation evidence, not an ASIC PPA estimate, external-I/O
sign-off, guaranteed frequency, or board qualification.

## Current routed results

Target: AMD Virtex UltraScale+ VCU108 (`xcvu095-ffva2104-2-e`), Vivado 2025.2,
`soc_clk_mmcm` at 100.010 MHz (9.999 ns). Values below are taken from each
product-local `fpga/vcu108/build/{timing_summary_routed,utilization_routed}.rpt`.

| Product | Routed report | Setup result | CLB LUTs | Registers | BRAM tiles | DSPs |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| M0 | 2026-07-31 | PASS: WNS +0.425 ns, TNS 0, 0 failing endpoints | 9,266 (1.72%) | 5,339 (0.50%) | 32 (1.85%) | 0 |
| M1 | 2026-08-04 | PASS: WNS +0.107 ns, TNS 0, 0 failing endpoints | 16,141 (3.00%) | 6,758 (0.63%) | 32 (1.85%) | 4 (0.52%) |
| M2 | 2026-08-04 | **Not closed:** WNS -0.050 ns, TNS -0.838 ns, 37 failing endpoints | 25,116 (4.67%) | 9,850 (0.92%) | 192 (11.11%) | 6 (0.78%) |

M2 is fully routed and has no reported routing error, but its latest retained
report does not meet the 100 MHz setup target. Do not describe M2 timing as
closed until a newer passing routed report is captured here.

## Interpretation boundary

- M0 and M1 meet the internal 100 MHz setup target with the frozen RTL used by
  their retained reports.
- M2 resource growth reflects RV32F plus 128 KiB ITCM, 128 KiB DTCM, and the
  512 KiB eight-bank System SRAM. The report does not prove an ASIC area or
  frequency result.
- Positive internal setup slack does not validate board I/O timing, reset
  sequencing, bitstream programming, UART, or JTAG behavior.
- M0 has a dated UART-boot-to-`Hello World` board smoke in
  [`eriscv-m0/fpga/vcu108/DEBUG.md`](../../eriscv-m0/fpga/vcu108/DEBUG.md).
  M1 and M2 board/debug closure remain separate work.

## Cross-references

[Verification Evidence Snapshot](../Verification/eriscv-mcu-simulation-evidence-snapshot.md)
owns regression totals. The [product manual FPGA page](../product-manual/fpga-evaluation.html)
is the reader-facing summary and must match this table.
