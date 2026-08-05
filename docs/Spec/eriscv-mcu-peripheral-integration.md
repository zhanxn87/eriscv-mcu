# eRISCV MCU Peripheral Integration Contract

This document is the common M0/M1/M2 APB-peripheral integration contract.
Product architecture manuals own address applicability and product-specific
extensions.

PLIC source numbering, priority, and claim/complete behavior are owned by the
[PLIC Specification](eriscv-mcu-plic-spec-v1.0.md); this document owns only
the peripheral-to-PLIC integration boundary.

## Baseline peripherals

- `uart/`: APB-controlled 8N1 TX/RX with RX interrupt output.
- `gpio/`: APB digital input/output with output-enable direction bits.
- `timer/`: APB counter, compare, status, and optional interrupt output.
- `spi/`: APB 8-bit master with SCLK/MOSI/MISO/SS and transfer-done interrupt.

## Interrupt and debug boundary

UART0 RX, TIMER0 expiry, and SPI0 completion are PLIC sources 1, 2, and 3.
Additional product inputs enter through `plic_src_i`; CLINT supplies MSIP/MTIP
outside the PLIC. JTAG DTM/DMI and the Debug Module are not APB peripherals
and connect to the hart debug interface outside the CPU DBus/APB path.

## Extension rule

Keep device logic in its own subdirectory behind an APB-facing wrapper. Any
new register map, PLIC source, reset, clock, BSP, and verification change must
be synchronized with the applicable product architecture and verification
contracts.
