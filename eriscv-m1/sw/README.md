# eRISCV-M1 BSP & Example Suite

Freestanding bare-metal BSP for eRISCV-M1 v0.1.0 (`rv32imc_zicsr_zifencei_zicntr_zihpm_zihintpause`,
`ilp32`). No libc, startup library, or vendor SDK required. The frozen examples
define the supported simulation suite; dated results are in the
[MCU Evidence Snapshot](../../docs/Verification/eriscv-mcu-simulation-evidence-snapshot.md).

## Software Inventory

| Layer | Files | M1 Notes |
|---|---|---|
| Startup | `lib/crt0.S` | Same as M0 |
| Linker | `linker/eriscv_mcu.ld` | Text in ITCM; readonly/initialized runtime data in DTCM with an ITCM load image |
| Trap | `lib/trap.S` + `lib/trap.c` | M-mode trap entry; dispatches MEI/MTI/MSI |
| UART | `lib/uart.c` | Polling and asynchronous drivers use the published UART0 base |
| BSP header | `include/eriscv_mcu.h` | Same API; `ERISCV_MCU_HAS_M_EXT=1` enables hardware M |
| Config | `include/eriscv_mcu_config.h` | M1 address map, `ERISCV_MCU_BOOT_ADDR`, M_EXT=1, PMP=1 |
| RTOS M-mode profile | `rtos/freertos/` | Four static M-mode tasks, timeout, queue/notification ISR handoff, and fail-stop checks |
| RTOS U-mode smoke | `rtos/freertos_umode/` | Four static U tasks, task-indexed PMP templates, and M-mode ECALL dispatch |
| Dhrystone | `benchmarks/dhrystone/` | Self-contained Dhrystone 2.1, mcycle timing, DMIPS/MHz reporting |
| Zephyr | `rtos/zephyr/` | Zephyr RTOS board port, multi-thread semaphore handoff demo |
| Tools | `tools/elf_to_mem.py`, `tools/run_hello_uart_sim.py`, `tools/run_mcu_ci.py` | Image generation and frozen-suite ModelSim checks |

Bare-metal and M-mode FreeRTOS images place `.rodata`, `.srodata`, `.data`,
and `.sdata` in the initialized-DTCM copy region. `crt0` copies that region
from its ITCM load image before calling `main`. Zephyr and the U-mode FreeRTOS
profile retain their own linker layouts.

## Driver API Summary

Same as M0 plus M1-specific:
- Hardware multiply/divide (M extension) — division uses native `div`/`rem`, no libgcc
- PMP CSR helpers available (16-entry); the FreeRTOS U-mode smoke exercises
  task-indexed PMP templates, while the BSP examples remain M-mode

## Examples

Build any example: `make -C eriscv-m1/sw EXAMPLE=<name> images`

| # | Example | Description | IRQs |
|---|---|---|---|
| 1 | `hello_uart` | Polling UART "hello" + GPIO pass flag | none |
| 2 | `timer_apb_poll` | APB Timer0 three-stage countdown | none |
| 3 | `timer_clint` | CLINT MTIMECMP periodic interrupt + GPIO blink | MTI |
| 4 | `wfi_tickless` | WFI idle + timer wake + wake counter | MTI |
| 5 | `irq_timer_uart` | Multi-source: timer blink + UART RX echo | MTI + MEI |
| 6 | `wdt_smoke` | Feed watchdog three times, then verify reset path | WDT |

`async_uart` remains an experimental example; it is not included in the frozen
v0.1.0 compatibility suite.

The runner defaults to Verilator. Use `--backend modelsim` with the configured
ModelSim wrapper for focused single-case debugging or waveform inspection.
It derives `boot_addr` from the linked ELF entry point, so no separate BSP
simulation address setting exists.

## Build

```bash
make -C eriscv-m1/sw                    # hello_uart (default)
make -C eriscv-m1/sw EXAMPLE=timer_clint images
make -C eriscv-m1/sw images-all          # frozen six-example build
make -C eriscv-m1/sw ci                  # frozen six-example ModelSim CI
make -C eriscv-m1/sw sim                # run hello_uart sim
make -C eriscv-m1/sw sim-coremark       # CoreMark v1.01 ModelSim smoke
make -C eriscv-m1/sw sim-embench        # Embench-IoT matmult-int ModelSim smoke
make -C eriscv-m1/sw sim-dhrystone      # Dhrystone 2.1 ModelSim smoke
make -C eriscv-m1/sw sim-zephyr         # Zephyr RTOS multi-thread demo
make -C eriscv-m1/sw sim-freertos       # FreeRTOS M-mode timing profile
make -C eriscv-m1/sw sim-freertos-umode # FreeRTOS U-mode/PMP smoke
```

`isa.mk` is the product build contract. Bare-metal images default to the
fast simulation UART divisor (`UART_MODE=sim`); build a 100 MHz / 115200-baud
board image with `UART_MODE=board`. `UART_DIVISOR=<n>` remains available for
focused experiments.

## CoreMark Simulation Smoke

The M1 CoreMark adapter uses the pinned upstream v1.01 submodule, one context,
2,000-byte static DTCM data, fixed validation seeds, and `mcycle` timing. The
default smoke runs one iteration through ModelSim and reports its cycle count.
It validates the CoreMark CRC path but is intentionally shorter than the
upstream 10-second reporting rule; it is not an official CoreMark or
CoreMark/MHz result.

## Dhrystone Simulation Smoke

The M1 Dhrystone adapter is a self-contained Dhrystone 2.1 implementation with
`mcycle` timing and UART output. The default smoke runs 100,000 iterations
through ModelSim and reports cycle count and DMIPS/MHz. It validates the
Dhrystone result word but is not an official Dhrystone or DMIPS rating.

Every successful runner invocation appends one row to
[`benchmarks/dhrystone/dmips_runs.csv`](benchmarks/dhrystone/dmips_runs.csv).
The default TB profile records code/image sizes, raw cycle count, compressed
and upper-halfword cross-word retirement, IMEM response/latency/contention,
stalls, redirects, forwarding, and early-DTCM-load activity. Use
`--no-perf-profile` only for focused simulator diagnosis; its CSV row marks TB
diagnostics unavailable.

## Scope & Limitations

- M1 adds M-extension and PMP over M0 baseline.
- PMP is exercised by the controlled FreeRTOS U-mode smoke; the frozen BSP
  examples remain M-mode.
- U-mode is available for product software; supervisor mode is not implemented.
- The FreeRTOS U-mode smoke validates four static task contexts plus `yield` and
  `exit` ECALLs. It is not a production RTOS port.
- Board boot, flash/XIP, and production image format are not defined.
- The public API is frozen at `ERISCV_MCU_BSP_VERSION_STRING` `0.1.0`.
- [toolchain.md](docs/toolchain.md) is the normative build and image contract.
