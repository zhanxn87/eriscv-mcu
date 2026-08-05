# eRISCV MCU OpenOCD/GDB Board-Smoke Contract

This common board-level scaffold defines external-debugger interoperability
evidence for M0/M1/M2. RTL JTAG/DMI tests are separate pre-silicon evidence.

## Checks

- OpenOCD discovery through the configured JTAG adapter.
- Halt attach through `monitor halt` or `monitor reset halt`.
- GPR read/write through GDB register access.
- Transcript captured under the product-local `logs/` directory.

## Inputs

`ADAPTER_CFG` is required. `FIRMWARE_ELF` is reserved for a future load/run
smoke: Debug 1.0 Minimal has no claimed program-buffer or SBA ELF-load path.
`OPENOCD`, `GDB`, `GDB_PORT`, `TCL_PORT`, and `TELNET_PORT` retain their
product-local script defaults.

## FPGA requirements

The wrapper exposes `jtag_tck_i`, `jtag_tms_i`, `jtag_tdi_i`, `jtag_tdo_o`,
and `jtag_trst_n_i` (or documents a reset default). The expected TAP has
IR length 5 and IDCODE `0x135711db`. Adapter speed, reset wiring, and cable
type belong in `ADAPTER_CFG`; qualify `adapter speed 10000` separately.
