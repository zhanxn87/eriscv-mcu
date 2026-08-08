# eRISCV MCU FPGA and Sky130 Timing and Area Evidence

This document owns the retained routed VCU108 evidence and local Sky130
OpenROAD implementation estimates. FPGA resources and ASIC standard-cell area
are different units and must not be compared as a common area metric. Neither
table is external-I/O sign-off, a guaranteed frequency, or board qualification.

## FPGA: current routed results

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

## Sky130: current local OpenROAD estimate

Target: SkyWater Sky130 HD (`sky130_fd_sc_hd`, `tt_025C_1v80`), local
OpenROAD `bazel-nostamp`, 20 ns (50 MHz) system clock, current dirty worktree
based on `e84e737`. The flow uses actual Sky130 integrated clock gates,
floorplanning, placement, high-fanout repair, CTS, and global-routing RC.
SRAM remains a black box: its macro area, timing, LEF, and routing are absent.

| Product | Run date | Target | Setup result | Pre-P&R standard-cell area | Post-P&R area | Hold result | Status |
| --- | --- | --- | --- | ---: | ---: | --- | --- |
| M0 | 2026-08-06 | 20 ns (50 MHz) | **Not closed:** WNS -1.249 ns, 39 endpoints after setup repair | 297,141 µm² | — | — | OpenROAD stopped at 65% utilization before final reporting; initial RTL optimization baseline only |
| M1 | — | — | Not run | — | — | — | Pending |
| M2 | — | — | Not run | — | — | — | Pending |

The M0 setup value is the last OpenROAD resizer result after global-routing RC,
not a signoff report: final detailed routing, SPEF extraction, hold repair,
PDN, IR/EM, and SRAM integration have not run. The observed worst path is the
CSR/HPM next-state path into `mhpmcounter6_q[63]`, not the integer ALU path.

### Update rule

Keep this table as the current implementation baseline. Update a product row
only after preserving the generated local log and recording the target period,
PDK/library, tool version, area stage, setup and hold status. Do not replace a
failed result with an extrapolated Fmax, and do not combine FPGA resource data
with Sky130 area in a single numeric comparison.

## Interpretation boundary

- M0 and M1 meet the internal 100 MHz setup target with the frozen RTL used by
  their retained FPGA reports; this does not imply Sky130 closure.
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
owns regression totals. The [product manual FPGA page](https://eriscv-mcu-product-manual.zhanxnse.chatgpt.site/fpga-evaluation)
is the reader-facing summary of the FPGA table and must match its FPGA rows.
