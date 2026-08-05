# eRISCV-M0 BSP & Example Suite

Freestanding bare-metal BSP for eRISCV-M0 v0.1.0 (`rv32ic_zicsr_zifencei_zicntr_zihpm_zihintpause`, `ilp32`).
No libc, startup library, or vendor SDK required. The six frozen examples define
the supported simulation suite; dated results are in the
[MCU Evidence Snapshot](../../docs/Verification/eriscv-mcu-simulation-evidence-snapshot.md).

## Software Inventory

| Layer | Files | Purpose |
|---|---|---|
| Product BSP | `bsp/` | Shared reset implementation and UART driver; contract and RTOS ownership rules |
| Startup | `bsp/startup/crt0.S` | Reset entry, stack/gp init, `.data` copy, `.bss` zero, bare-metal trap vector install |
| Linker | `linker/eriscv_mcu.ld` | Published ITCM/DTCM bounds and boot-entry symbols |
| Trap | `lib/trap.S` + `lib/trap.c` | M-mode trap entry; dispatches MEI (PLIC), MTI (timer), MSI (software) |
| UART | `bsp/drivers/uart.c` | Polling TX/RX + async interrupt-driven FIFO (128B TX, 128B RX) |
| BSP header | `include/eriscv_mcu.h` | MMIO helpers, register maps for CLINT/PLIC/UART/GPIO/Timer/SPI |
| Config | `include/eriscv_mcu_config.h` | M0 address map, `ERISCV_MCU_BOOT_ADDR`, PLIC source count, feature flags |
| RTOS M-mode | `rtos/freertos/` | Four static M-mode tasks, dynamic allocation, CLINT tick, PLIC ISR handoff |
| Microbench | `benchmarks/microbench/` | ALU/branch/MUL/DIV/LS/ECALL/CLINT/PLIC microbenchmark |
| Dhrystone | `benchmarks/dhrystone/` | Self-contained Dhrystone 2.1, `mcycle` timing, DMIPS/MHz reporting |
| Zephyr | `rtos/zephyr/` | Zephyr RTOS M0 board port and multi-thread semaphore handoff demo |
| Tools | `tools/elf_to_mem.py`, `tools/run_hello_uart_sim.py`, `tools/run_mcu_ci.py` | ELF-to-IMEM/DMEM image conversion, simulation helpers, and ModelSim CI wrapper |

## Driver API Summary

| Peripheral | Key Functions |
|---|---|
| UART (polling) | `eriscv_mcu_uart_init()`, `_putc()`, `_getc()`, `_puts()` |
| UART (async) | `eriscv_mcu_uart_async_init()`, `_async_write()`, `_async_getc()`, `_async_tx_pending()` |
| GPIO | `eriscv_mcu_gpio_set_direction()`, `_gpio_write()` |
| CLINT | `eriscv_mcu_clint_set_mtimecmp()`, `_set_msip()`, `_read_mtime()` |
| PLIC | `eriscv_mcu_plic_set_priority()`, `_set_enabled()`, `_set_threshold()`, `_claim()`, `_complete()` |
| APB Timer | `eriscv_mcu_timer_start()`, `_timer_expired()` |
| IRQ control | `eriscv_mcu_enable_machine_irqs()`, `_disable_machine_irqs()` |

Trap handler dispatch (weak, overridable):
- `eriscv_mcu_trap_handler(mcause, mepc, mtval)` → dispatches MEI/MTI/MSI
- `eriscv_mcu_timer_irq_handler()` — weak, override for custom timer ISR
- `eriscv_mcu_software_irq_handler()` — weak, clears MSIP by default
- `eriscv_mcu_machine_external_irq_handler()` — dispatches PLIC sources

## Examples

Build any example: `make -C eriscv-m0/sw EXAMPLE=<name> images`

| # | Example | Description | IRQs | Sim oracle |
|---|---|---|---|---|
| 1 | `hello_uart` | Polling UART "hello" + GPIO pass flag | none | UART bytes + GPIO OUT=1 |
| 2 | `timer_apb_poll` | APB Timer0 three-stage countdown, GPIO toggle | none | UART bytes + GPIO OUT=1 |
| 3 | `timer_clint` | CLINT MTIMECMP periodic interrupt, GPIO blink | MTI | GPIO OUT=1 |
| 4 | `wfi_tickless` | WFI idle loop, timer wake, wake counter | MTI | GPIO OUT=1 |
| 5 | `irq_timer_uart` | Multi-source: timer GPIO blink + UART RX echo | MTI + MEI (UART) | GPIO OUT=1 |
| 6 | `wdt_smoke` | Feed watchdog three times, then verify reset path | WDT | GPIO OUT=1 |

`async_uart` remains an experimental example; it is not included in the frozen
v0.1.0 compatibility suite.

Run any example sim:
```bash
python3 eriscv-m0/sw/tools/run_hello_uart_sim.py \
  --example timer_clint --tc BSP-TIMER-CLINT \
  --expected-gpio-out 1 --max-cycles 800000
```

The runner defaults to Verilator. Use `--backend modelsim` with the configured
ModelSim wrapper for focused single-case debugging or waveform inspection.
It derives `boot_addr` from the linked ELF entry point, so no separate BSP
simulation address setting exists.

## Build

```bash
make -C eriscv-m0/sw                    # hello_uart (default)
make -C eriscv-m0/sw EXAMPLE=timer_clint images
make -C eriscv-m0/sw images-all            # frozen six-example build
make -C eriscv-m0/sw ci                    # frozen six-example ModelSim CI
make -C eriscv-m0/sw sim                # run hello_uart sim
make -C eriscv-m0/sw sim-async          # run async_uart sim
```

`isa.mk` is the product build contract. Bare-metal images default to the
fast simulation UART divisor (`UART_MODE=sim`); build a 100 MHz / 115200-baud
board image with `UART_MODE=board`. `UART_DIVISOR=<n>` remains available for
focused experiments.

## FreeRTOS and Benchmarks

M0 includes a FreeRTOS M-mode profile, benchmarks, and Zephyr RTOS port — all
built with `-march=rv32ic_zicsr_zifencei_zicntr_zihpm_zihintpause` (no M-extension). Verified in
ModelSim.

Bare-metal and FreeRTOS build through the product [`bsp/`](bsp/README.md): the
same reset/data-init and UART implementation is used in both. FreeRTOS retains
ownership of `mtvec` through its RISC-V port. Zephyr keeps its native driver
and linker integration; its standard `ROM=IMEM`, `RAM=DMEM` image layout is
deliberately distinct from the freestanding DTCM-read-only-data layout.

The DTCM readonly-data layout is a measured M0 software configuration, not a
UART-driver optimization: the retained 1,000-iteration `-O2` Dhrystone A/B is
850,016 to 819,016 cycles (-3.647%). The BSP source consolidation itself has
no separate cycle claim.

```bash
# FreeRTOS M-mode (four static tasks + dynamic allocation)
make -C eriscv-m0/sw freertos
make -C eriscv-m0/sw sim-freertos

# CoreMark v1.01 smoke
make -C eriscv-m0/sw coremark
make -C eriscv-m0/sw sim-coremark

# Embench-IoT selected workloads
make -C eriscv-m0/sw embench
make -C eriscv-m0/sw sim-embench

# Dhrystone 2.1
make -C eriscv-m0/sw dhrystone
make -C eriscv-m0/sw sim-dhrystone
# Standard Verilator measurement path (1,000 O2 iterations)
python3 eriscv-m0/sw/tools/run_dhrystone_sim.py --backend verilator --iterations 1000

# Zephyr RTOS multi-thread demo
make -C eriscv-m0/sw zephyr
make -C eriscv-m0/sw sim-zephyr

# Microbench (ALU, branch, load/store, MUL/DIV via libgcc, ECALL, CLINT, PLIC)
make -C eriscv-m0/sw microbench
make -C eriscv-m0/sw sim-microbench
```

Every successful Dhrystone runner invocation appends one row to
[`benchmarks/dhrystone/dmips_runs.csv`](benchmarks/dhrystone/dmips_runs.csv).
The row records ISA, Git state, `.text` and image sizes, raw cycle count,
DMIPS/MHz, and default TB diagnostics: compressed/32-bit retirement,
upper-halfword cross-word instructions, IMEM response/latency/contention,
stalls, redirects, and forwarding. `--no-perf-profile` is for focused simulator
diagnosis only and marks those fields unavailable.

Current timing methodology and published results are summarized in the
[family performance manual](../../docs/product-manual/performance.html).

## Scope & Limitations

- M0 is M-mode only (no U-mode, no PMP, no M-extension).
- Software division relies on libgcc (`-lgcc` linked).
- Board boot, flash/XIP, and production image format are not defined.
- The public API is frozen at `ERISCV_MCU_BSP_VERSION_STRING` `0.1.0`.
- [toolchain.md](docs/toolchain.md) is the normative build and image contract.
