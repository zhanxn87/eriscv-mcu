# eRISCV-M0 Zephyr Port

Zephyr RTOS v3.6 LTS board and SoC port for the eRISCV-M0 educational RISC-V MCU.

## Prerequisites

```bash
# Init Zephyr submodule (first time only)
cd edu-mcu
git submodule update --init third_party/zephyr
cd third_party/zephyr
pip3 install west
west init -l .
west update

# Ensure riscv64-unknown-elf-gcc is available on PATH
```

## Build & Run

```bash
make -C eriscv-m0/sw zephyr
make -C eriscv-m0/sw sim-zephyr

# The runner uses the fast ModelSim UART divisor (DUT/TB synchronized).
python3 eriscv-m0/sw/tools/run_zephyr_sim.py

# Tickless WFI + CLK_RST clock-gating and CLINT wake smoke.
python3 eriscv-m0/sw/tools/run_zephyr_sim.py --low-power
```

## Board Configuration

| Parameter | Value |
|---|---|
| Board | `eriscv_mcu` |
| SoC | `eriscv_mcu` |
| Architecture | RV32IC (Zicsr, Zifencei) |
| M-mode | Yes (machine timer via CLINT) |
| M-extension | No (MUL/DIV via libgcc) |
| PMP | Not present |
| ITCM (FLASH) | 64 KB at 0x10000000 |
| DTCM (SRAM) | 64 KB at 0x11000000 |
| System Clock | 100 MHz |
| Tick Rate | 1000 Hz |

## Driver and smoke coverage

- UART polling API plus interrupt-driven TX console (PLIC source 1).
- GPIO output/direction operations and APB timer counter callbacks.
- WDT pretimeout/feed/disable and asynchronous SPI transceive (PLIC source 4).
- Tickless Zephyr WFI with SoC clock gating is covered by the dedicated
  `app_low_power` profile; M0 keeps the M-mode-only CLINT/PMP-free architecture.

## M0 Profile

- `-march=rv32ic_zicsr_zifencei_zicntr_zihpm_zihintpause` (no M-extension)
- No PMP regions
- No U-mode
- Higher cycle counts for division-heavy paths (software div/mod)
- Result magic: `0x6a7b8c9d`

## Memory Budget

| Region | Size | Usage |
|---|---|---|
| Main thread stack | 4096 B | kernel main thread |
| Thread A stack | 1024 B | demo thread |
| Thread B stack | 1024 B | demo thread |
| Idle stack | 1024 B | kernel idle |
| ISR stack | 4096 B | interrupt handlers |

Total DTCM footprint: ~14 KB (of 64 KB available).

## Limitations

- The Zephyr board uses its standard `ROM=IMEM` and `RAM=DMEM` linker model.
  It does not use the freestanding BSP rule that relocates `.rodata` to DTCM;
  adopting that rule requires a Zephyr-specific linker/startup change and
  separate boot validation.
- No M-extension: division/modulo operations use libgcc soft routines.
- Early startup uses the standard polling hook. After kernel startup, `printk`
  TX uses a 256-byte ring buffer drained by UART/PLIC source 1 interrupts.
- No filesystem, networking, or USB support.
- This port is a development-grade smoke test, not a production Zephyr BSP.
