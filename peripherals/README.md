# eRISCV Shared APB Peripherals

This directory is the single implementation source for the eRISCV MCU product
line's standard APB peripherals: clock/reset control, GPIO, SPI, timer, UART,
and watchdog. Product address maps, clock wiring, interrupt allocation, and
optional DMA endpoint connections remain in each product's `rtl/soc/`
integration layer.

The common [peripheral integration contract]
(../docs/eriscv-mcu-peripheral-integration.md) defines the APB behavior.
