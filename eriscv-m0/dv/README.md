# eRISCV-M0 Design Verification

This directory is the verification root for eRISCV-M0. Directed test collateral
is grouped with its core or SoC testbench.

This README is the maintained test inventory, including design intent,
execution flow, and oracle ownership. The dated full-regression totals are
owned by the [family evidence snapshot](../../docs/Verification/eriscv-mcu-simulation-evidence-snapshot.md).

| Directory | Content | Primary runner |
| --- | --- | --- |
| [`core/tests/`](core/tests/) | Core-directed product and inherited-baseline tests | `make -C eriscv-m0/dv/core/sim verilator` |
| [`soc/tests/`](soc/tests/) | MCU product integration, peripheral, interrupt, and debug tests | `make -C eriscv-m0/dv/soc/sim verilator` |
| ACT4 runtime cache (generated locally; see [`../compliance/riscv-arch-test/README.md`](../compliance/riscv-arch-test/README.md)) | Generated `.mem`, `.data.mem`, and `.act.json` collateral | `make act-generate-m0`, then `make -C eriscv-m0/dv/core/sim verilator TESTS=--act-full` |

## `core/tests/`

### MCU product tests

- `C/`: `MCU-C-01`, `MCU-C-DEBUG-STEP-SWEEP-01`, `MCU-C-DPC-01`,
  `MCU-C-IFETCH-CROSSWORD-01`, `MCU-C-IRQ-MEPC-01`, `MCU-C-LS-01`,
  `MCU-C-MIXED-PC-01`, `MCU-C-SP-01`.
- `BTFNT/`: `MCU-BTFNT-ID-01` covers native backward/forward prediction and
  both EX correction paths. `MCU-BTFNT-C-01` covers `C.BEQZ`/`C.BNEZ`, `C.J`,
  and `C.JAL`; `C.JALR` remains intentionally EX-resolved.
- `HPM/`: `MCU-COUNTER-CSR-01` verifies the `mcountinhibit` mask, mcycle
  freeze/resume, and 64-bit programmable HPM3 CSR/event access.
  `MCU-HPM-01` covers selector reset defaults, basic event-selection isolation,
  per-counter inhibit isolation, and 64-bit carry using explicitly programmed
  selectors. `MCU-HPM-CSR-01` covers the full `mcountinhibit` WARL mask,
  machine/URO low-and-high alias equality for mcycle/minstret/HPM3-HPM6,
  selector reserved-bit behavior, and the illegal `mcounteren` access required
  by the M-mode-only contract. `MCU-HPM-TRAP-01` proves exact single-event
  counts for `BRANCH_TAKEN` and `EXCEPTION_TAKEN`; `MCU-HPM-IRQ-01` proves an
  exact `INTERRUPT_TAKEN` count using software-generated MSIP (no cycle-timed
  testbench IRQ). `MCU-HPM-WAIT-01` uses configured fetch/data latency to
  prove nonzero `IFETCH_WAIT_CYCLES`, `DATA_WAIT_CYCLES`,
  `PIPELINE_STALL_CYCLES`, and `LOAD_USE_STALL_CYCLES`, without constraining
  implementation-specific totals. `MCU-HPM-DEBUG-01` proves `DEBUG_ENTRY`
  through EBREAK/DRET; `MCU-HPM-PENDING-01` proves nonzero
  `IRQ_PENDING_CYCLES` while MIE remains disabled, isolating it from trap
  acceptance. They replace the retired `P8-HPM-01`, which assumed an obsolete
  fixed event mapping.
- `WFI/`: `MCU-WFI-01` verifies that WFI holds younger execution until a machine
  external interrupt wakes the core, and that HPM6 configured for
  `WFI_CYCLES` observes a nonzero wait interval without assuming its cycle
  count.
- `Zifencei/`: `MCU-ZIFENCEI-01`, `MCU-ZIFENCEI-SELF-MODIFY-01`.
- `Zihintpause/`: `MCU-ZIHINTPAUSE-01`.

These product images are run in the SoC regression because they verify the
delivered MCU integration, even though their source location is `dv/core/tests/`.

### Legacy phased core tests

- `legacy/phase1/`: `P1-ALU-01`.
- `legacy/phase2/`: `P2-CFLOW-01`.
- `legacy/phase4/`: `P4-FWD-01`, `P4-LDST-01`.
- `legacy/phase5/`: `P5-CSR-TRAP-01`.
- `legacy/phase7/`: `P7-CSR-DEP-01`, `P7-CTRL-KILL-01`, `P7-FWD-STRESS-01`,
  `P7-LDST-STRESS-01`.
- `legacy/phase8/`: `P8-COUNTER-01`, `P8-HPM-01`.
- `legacy/phase9/`: `P9-IRQ-01`.
- `legacy/phase10/`: `P10-MEMWAIT-01`.
- `legacy/phase11/`: `P11-EBREAK-DRET-01`, `P11-EXT-HALT-01`, `P11-STEP-01`.

## `soc/tests/`

| Class | Testcases | Use |
| --- | --- | --- |
| `product` | `MCU-BUS-UNMAPPED-01`, `MCU-STORE-FAST-01`, `MCU-CLKRST-01`, `MCU-LP-WFI-TIMER-01`, `MCU-CLINT-01`, `MCU-TIME-CSR-01`, `MCU-CLINT-MSIP-IRQ-01`, `MCU-CLINT-MTIP-IRQ-01`, `MCU-PLIC-01`, `MCU-PLIC-IRQ-01`, `MCU-PLIC-PENDING-PRIORITY-01`, `MCU-PLIC-SOURCE-SWEEP-01`, `MCU-DEBUG-ABSTRACT-01`, `MCU-DEBUG-GPR-SWEEP-01`, `MCU-DEBUG-COMPLETE-01`, `MCU-DEBUG-JTAG-01`, `MCU-DEBUG-JTAG-STRESS-01`, `MCU-DEBUG-OPENOCD-LIKE-01` | Product-owned eRISCV-M0 evidence. |
| `legacy-adapted` | `UART-LOOPBACK-01`, `UART-HELLO-01`, `UART-ECHO-01`, `GPIO-BASIC-01`, `TIMER-POLL-01`, `SPI-BASIC-01` | Imported old-SoC collateral adapted to eRISCV-M0 agents. |

The superseded JTAG/DMI reference collateral was removed after its coverage,
including invalid-DMI error responses, was absorbed by the Debug 1.0 product
scenarios.

## Optional SoC Performance Profile

`+perf_profile=1` enables an observational testbench profile. It does not alter
RTL, software-visible HPM events, or the testcase result. Run it against an
already-built Verilator SoC binary, for example:

```bash
cd eriscv-m0/dv/soc/sim
./obj_dir/Vsoc_tb +tc=MCU-BUS-UNMAPPED-01 \
  +instr_mem_file=../tests/MCU-BUS-UNMAPPED-01.mem \
  +expected_regs_file=../tests/MCU-BUS-UNMAPPED-01.expected_regs \
  +perf_profile=1
```

The `TB PERF` summary reports architectural `mcycle`/`minstret`, core-enabled
cycles, retired instruction classes, individual and de-duplicated pipeline
hold cycles, split ID/EX and EX/MEM-response-wait load-use stalls,
WFI/debug-halted cycles, conditional-branch versus jump redirects (including
backward/forward taken branches), instruction-fetch request latency,
and D-bus request latency. D-bus counts are also split by read/write and DTCM, instruction
memory, CLINT, PLIC, APB, or unmapped target. Latency is measured from the
request edge to its response edge: same-cycle response is `hist0`, one later
clock is `hist1`, and all longer responses are `hist2plus`.

This is a performance-analysis aid, not an architectural counter contract;
use the HPM directed tests above for HPM ABI verification.

## `../compliance/`

After `make act-generate-m0`, `../compliance/riscv-arch-test/generated/`
contains the `.mem`, `.data.mem`, and `.act.json` cache used by `--act-full`.
It is not source-controlled.

Use `make -C eriscv-m0/dv/core/sim list` or
`make -C eriscv-m0/dv/soc/sim list` to inspect the exact runnable set in
the current checkout. When an imported testcase becomes product evidence,
update this inventory and the product verification contract in the same change.

## Contributing a Test

1. **Source**: Write an assembly source (`.S`) following the product test
   conventions (use `dv/core/tests/C/MCU-C-01.S` or `dv/soc/tests/MCU-CLINT-01.S` as
   a template).
2. **Build**: Compile with the product GCC toolchain to produce `.elf`, `.bin`,
   and `.mem` images. The Make flow under `dv/core/sim` or `dv/soc/sim`
   typically handles this; consult the simulation Makefile for the exact
   recipe.
3. **Oracle**: Provide an `.expected_regs` file (GPR dump oracle) and, for
   SoC tests, add any required TB agent configuration (interrupt injection,
   peripheral stimulus, debug DMI sequences).
4. **Register**: Add the testcase name to the appropriate test list in the
   simulation regression script (`dv/core/sim/run_regression.py` or
   `dv/soc/sim/run_regression.py`).
5. **Document**: Add the testcase to this inventory with purpose, execution
   flow, and oracle details.
6. **Verify**: Run the regression locally before submitting:

   ```bash
   # Core test
   make -C eriscv-m0/dv/core/sim modelsim TESTS=MY-NEW-TEST
   # SoC test
   make -C eriscv-m0/dv/soc/sim modelsim TESTS=MY-NEW-TEST
   ```
