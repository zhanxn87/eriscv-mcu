# FreeRTOS M-mode profile (M0 port)

This static-allocation M0 demo uses the upstream FreeRTOS-Kernel V11.3.0
RISC-V port, built with `-march=rv32ic_zicsr_zifencei_zicntr_zihpm_zihintpause` (no M-extension).
It creates four static application tasks: two equal-priority yield/time-slice
tasks, a timer trigger, and a higher-priority consumer. CLINT `mtime` drives
the scheduler tick.

Dynamic allocation (`configSUPPORT_DYNAMIC_ALLOCATION=1`, `heap_4.c`, 8 KiB
heap) is also available and verified in ModelSim. All tasks remain in M-mode.

Build images with `make -C eriscv-m0/sw/rtos/freertos images`.
Run the ModelSim timing profile once with:

```sh
python3 eriscv-m0/sw/tools/run_freertos_sim.py
```

Run the qualification evidence with:

```sh
python3 eriscv-m0/sw/tools/run_freertos_sim.py --runs 3 --failstops
```

The default runner executes only the normal profile. `--failstops` adds the
injected assertion and stack-overflow fail-stop images.

The runner extracts the ten-word `eriscv_freertos_timing_report` ABI and
combines it with a TB-observed APB-timer PLIC-source assertion.

## Driver layout

FreeRTOS-specific BSP drivers live under `drivers/`, one pair per peripheral:
`uart.{c,h}`, `clk_rst.{c,h}`, `gpio.{c,h}`, `timer.{c,h}`, `plic.{c,h}`,
`wdt.{c,h}`, and `spi.{c,h}`. `drivers.h` only aggregates those public headers; the shared
`sw/include/eriscv_mcu.h` remains the low-level MMIO compatibility layer.

The SPI driver supports all four chip-selects, mode-0/1/2/3 and LSB-first
configuration, repeated 8-bit frames under one chip-select, polling transfers,
and PLIC-backed asynchronous transfers. The asynchronous completion callback
runs in interrupt context.
