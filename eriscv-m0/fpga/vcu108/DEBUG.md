# eRISCV-M0 VCU108 FPGA Debug Record

This is the product-local, append-only engineering record for M0 VCU108
bring-up.  It records constraint reviews, tool observations, board sessions,
and unresolved risks.  Each entry states whether it is static review or
physical-board evidence.
The family-level procedure and archive requirements are in
[`board-jtag-debug`](https://eriscv-mcu-product-manual.zhanxnse.chatgpt.site/board-jtag-debug).

## Record 2026-07-28 — Pre-board interface review

**Scope:** static review of the VCU108 wrapper and constraints.  No board,
cable, UART, or JTAG scan was connected for this record.

| XDC signal | FPGA pin | VCU108 interface | RTL use |
| --- | --- | --- | --- |
| `sys_clk_p/n` | `G31` / `F31` | `SYSCLK1_300_P/N`; 300 MHz differential system clock | MMCM derives the 100 MHz SoC clock. |
| `cpu_reset_i` | `E36` | `CPU_RESET` board push button | Asynchronously resets the MMCM; reset release is synchronized in the SoC clock domain. |
| `uart_rx_i` | `BC24` | USB-UART, CP2105 TX to FPGA RX | Runtime UART RX and UART boot RX. |
| `uart_tx_o` | `BE24` | USB-UART, FPGA TX to CP2105 RX | Runtime UART TX. |
| `boot_mode_i[0:2]` | `BC40` / `L19` / `C37` | GPIO DIP `SW12.4` / `.3` / `.2` | Reset-time boot-source selection. |
| `boot_uart_overrun_led_o` | `AT32` | `GPIO_LED_0`, `DS7.1` | UART boot overrun indication. |
| `boot_uart_protocol_error_led_o` | `AV34` | `GPIO_LED_1`, `DS6.1` | UART boot protocol-error indication. |
| Debug JTAG | no external XDC port | Board configuration JTAG through `BSCANE2` chain 2 | RISC-V Debug 1.0 DTM/DMI. |

### Finding M0-VCU108-E-01 — SYSCLK electrical standard (closed)

`SYSCLK1_300` at `G31/F31` requires `DIFF_SSTL12`, not generic `LVDS`; an
incompatible input termination property must not be applied.  The present
[`vcu108.xdc`](constraints/vcu108.xdc) uses `DIFF_SSTL12` on both pins and the
wrapper disables `IBUFDS.DIFF_TERM`. This is the retained pre-public baseline
configuration. No further edit is required for this finding, but future
constraint changes must preserve this pairing.

### Finding M0-VCU108-B-01 — boot-mode usability (partially closed)

The DIP pin mapping establishes selection inputs but does not itself make a
boot path usable on hardware:

- Mode `3'b000` bypasses the loader.  M0 FPGA SRAM has no persistent program
  image, so this mode cannot execute useful firmware after configuration.
- Mode `3'b001` selects JTAG-DMI boot.  The RTL and simulation trace replay
  are verified, but a physical cable transport for the private boot registers
  (`0x60`--`0x63`) has not yet been qualified.
- Mode `3'b010` selects UART boot at the fixed 115200 baud contract.  The
  CP2105 path and loader are physically demonstrated below.  The precise DIP
  on/off polarity has not yet been recorded.
- Modes `3'b011`--`3'b111` are not current product boot sources and leave
  fetch disabled.

Record the actual switch polarity and label a known-safe physical setting for
JTAG-DMI and UART boot.  Retain the programmed bitstream hash, cable/chain
discovery output, and a UART or DMI load transcript for each board session.

## Record 2026-07-28 — Configuration-JTAG programming attempt

**Inputs:** Vivado 2025.2 Hardware Manager; on-board Digilent JTAG target;
`build/eriscv_m0_vcu108_wrapper.bit`, SHA-256
`cb868276093b4cc3da102d1db26c7cf24f7004e5806fe06e4a8f878649fa23a0`.

| Observation | Result |
| --- | --- |
| Hardware discovery | Connected target and device `xcvu095_0`; IDCODE `0x13842093`; IR length 6. |
| Security/configuration status | No security, IDCODE, or CRC error indicated before programming; device was unconfigured (`DONE=0`). |
| Programming result | Failed: `Labtools 27-3303 Incorrect bitstream assigned to device`; Hardware Manager reports the target revision is compatible with ES2 bitstreams. `END_OF_STARTUP` remained low. |
| Board-preset check | Selecting the standard VCU108 board still selected `xcvu095-ffva2104-2-e`, the same target used to build the rejected image. |
| Version-check waiver | `set_param xicom.use_bitstream_version_check false` followed by `program_hw_devices` completed. A subsequent refresh reported the device programmed. |
| Vivado debug-core discovery | Reported no supported soft debug cores. This is expected for this image: it has no Vivado ILA/VIO core, and the RISC-V DTM is a custom `BSCANE2` user chain. |

**Disposition:** Configuration-JTAG download is conditionally demonstrated
under the session-local version-check waiver.  This is not a silicon-revision
compatibility claim and must be repeated after every tool or bitstream change.
No clock, reset, boot, UART, GPIO, or fabric-JTAG functionality has yet been
observed on hardware.  `M0-VCU108-P-01` remains open for functional bring-up,
but is no longer a blocker to configuration-JTAG experiments.

## Record 2026-07-28 — UART boot functional smoke (pass)

**Setup:** the board was reset after selecting the RTL UART boot value
`3'b010`.  The FPGA UART was the CP2105 Standard port, `COM4`.  The programmed
bitstream is the SHA-256 recorded above.

| Step | Result |
| --- | --- |
| Host serial framing | 115200 baud, 8-N-1, no flow control. |
| Boot image | [`tests/UART-HELLO-115200.mem`](tests/UART-HELLO-115200.mem), 61 words / 310 boot-protocol bytes. The runtime UART divisor is 868 for the 100 MHz SoC clock. |
| Loader transaction | `HOLD`, address reset, auto-incremented little-endian `WRITE32`, then `RELEASE` completed without host error. |
| Observed FPGA UART TX | Exact text: `Hello World`. |

**Disposition:** UART boot is physically demonstrated end-to-end: host TX,
boot-parser reception, instruction-SRAM load, CPU fetch release, execution,
and FPGA UART TX through the CP2105 Standard port.  This does not qualify the
private BSCANE2/RISC-V DMI transport, GPIO, SPI, or any persistent-boot mode.
The original `../../dv/soc/tests/UART-HELLO-01.mem` must remain simulation-only because
its runtime divisor of 8 is approximately 12.5 Mbaud at 100 MHz.

### Follow-up M0-VCU108-B-02 — UART boot/runtime ownership (fixed in RTL)

UART boot and the runtime UART receive path share `uart_rx_i`. The boot parser
must therefore stop receiving immediately after `RELEASE`; otherwise terminal
bytes can be decoded as boot opcodes (notably `0x03` as `HOLD`).
`boot_subsystem.sv` now enables UART boot only while fetch remains unreleased.
The handoff is intentionally one-shot until reset. A future runtime-console
image must drain the residual boot bytes in the runtime RX FIFO before
accepting terminal input.

## Record 2026-07-30 — Post-route implementation after predictor and load-path work (pass)

**Scope:** implementation evidence only; this is not a new board session.
Vivado 2025.2 ran the default VCU108 implementation flow for
`xcvu095-ffva2104-2-e` from a clean product-local build directory.  The run
includes the current M0 BHT/BTFNT predictor, four-entry RAS, and completed-load
bypasses.

| Check | Routed result |
| --- | --- |
| `soc_clk_mmcm` target | 9.999 ns / 100.010 MHz |
| Setup timing | WNS `+0.152 ns`, TNS `0.000 ns`, 0 failing endpoints |
| Routing | 0 routing errors |
| DRC | No reported design-rule violation; no LUT combinational-loop finding |
| Resources | 9,372 CLB LUTs (1.74%), 5,357 registers (0.50%), 32 BRAM tiles (1.85%), 0 DSPs |
| Deliverables | Routed DCP and `build/eriscv_m0_vcu108_wrapper.bit` generated |

**Disposition:** This archived 2026-07-30 build met the 100 MHz FPGA timing
target. The family [FPGA Timing and Area Evidence](../../../docs/Performance/eriscv-mcu-fpga-timing-area-evidence.md)
owns the newer 2026-07-31 M0 routed result and current timing status. The
positive slack in this historical build must not be attributed to any
individual feature without a paired build. This result does not add
physical-board functional evidence.

## Future entries

Append one dated entry per board session with: RTL commit, bitstream SHA-256,
board revision, Vivado/host versions, switch positions, adapter and chain
configuration, exact commands, complete observed output, and disposition of
every failure or deviation.
