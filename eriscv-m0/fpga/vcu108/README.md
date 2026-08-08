# eRISCV-M0 VCU108 Vivado Project

Independent VCU108 project for the M0 product (`RV32IC`, no PMP). It resolves
the product-local `rtl/soc/filelist.f` at project-creation time, so an M0 RTL
change is picked up without copying a source list from M1.

## Target

- Board: Xilinx VCU108 (`xcvu095-ffva2104-2-e`)
- Top: `eriscv_m0_vcu108_wrapper`
- SoC clock: 100 MHz, generated from `sysclk1_300`
- Debug: Debug 1.0 DTM through `BSCANE2` JTAG chain 2
- Timing: closed at 100 MHz (Vivado 2025.2, default impl strategy)

The wrapper connects the USB UART and boot-mode DIP switches. GPIO, SPI MISO,
and external PLIC IRQ inputs are tied inactive until a specific expansion
connector is selected. The two user LEDs report UART boot overrun and protocol
error. The on-chip SRAM has no fixed FPGA image: use boot mode 1 (JTAG DMI) or
2 (UART) to load IMEM; mode 0 only bypasses the boot loader.

Board interface review findings and subsequent board-session evidence are kept
in [DEBUG.md](DEBUG.md).
The detailed build-to-observed-output explanation is in the product manual:
[M0 UART Boot Hello World](https://eriscv-mcu-product-manual.zhanxnse.chatgpt.site/m0-uart-boot-hello-world).

## Browser UART console (recommended)

Double-click [`tools/open_uart_console.cmd`](tools/open_uart_console.cmd) in
Windows Explorer. It starts a loopback-only local server and opens
`uart_console.html` in the default browser. Use current Chrome or Edge:

1. Select UART boot (`3'b010`) and press `CPU_RESET`.
2. Click **Connect port**, then select the CP2105 **Standard** UART (`COM4` in
   the recorded session).
3. Keep 115200 baud and select `tests/UART-HELLO-115200.mem`.
4. Click **Boot image**. The terminal displays `Hello World`; download the
   captured log if needed.

The page requires an explicit browser port-selection grant and cannot control
the board DIP switches or physical reset. `RELEASE` disables UART boot until
the next reset, so disconnect/reconnect after pressing `CPU_RESET` before
loading another image. It is intentionally local-only; do not publish it as a
general product-manual page.

## PowerShell UART boot fallback

The VCU108 Standard CP2105 port is the FPGA UART.  It appeared as `COM4` in
the recorded session; identify its port name on the current host before use.
The Enhanced port is the board system controller. With the DIP inputs set to
the RTL UART-boot value `3'b010`, press `CPU_RESET` and send an image at the
fixed 115200 baud, 8-N-1 setting:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\m0_uart.ps1 `
  -Mode Boot `
  -Port <COM_PORT> `
  -Image .\tests\UART-HELLO-115200.mem
```

`m0_uart.ps1` implements the product UART boot protocol (`HOLD`, reset address,
auto-increment, little-endian `WRITE32`, `RELEASE`) directly; it does not
preload FPGA memory. Use `-DryRun` to validate the selected image without
opening the serial port. `send_uart_boot.ps1` remains a compatible Boot-mode
wrapper for earlier commands.

## Runtime serial terminal

Use the same tool with a compatible runtime monitor image for later interactive
demos. It prints runtime UART RX bytes and sends typed keys immediately; Enter
sends carriage return (`0x0d`). Keep only one program attached to the selected
port at a time.

```powershell
# Attach to already-running firmware. Ctrl+C exits.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\m0_uart.ps1 `
  -Mode Terminal -Port <COM_PORT> -LogPath .\logs\demo-uart.log

# Load an image, then remain attached to its runtime UART.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\m0_uart.ps1 `
  -Mode BootTerminal -Port <COM_PORT> `
  -Image .\tests\UART-HELLO-115200.mem `
  -LogPath .\logs\hello-world.log
```

For non-interactive capture, add `-NoInput -TerminalSeconds 10`. The terminal
has no line discipline, escape parser, or local echo: those belong to the demo
firmware or to a full terminal emulator, not the board transport tool.

`UART-HELLO-115200.mem` is a board-only smoke image with UART divisor 868
(100 MHz / 115200).  Do not substitute the regression image
`../../dv/soc/tests/UART-HELLO-01.mem`: its divisor is 8 solely to keep simulation
short.

The repository does not currently bundle an interactive monitor image. A
monitor intended for the browser console must use the 868 divisor and drain the
boot-protocol bytes from the runtime RX FIFO before accepting terminal input,
because UART boot and runtime UART share the FPGA RX pin. The Verilator-tested
one-byte echo behavior is available as `../../dv/soc/tests/UART-ECHO-01`.

## Run from Windows PowerShell

```powershell
# From the repository root:
cd .\eriscv-m0\fpga\vcu108
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run_vivado.ps1 -Flow gui
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run_vivado.ps1 -Flow synth
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run_vivado.ps1 -Flow impl
```

The command uses a process-local `Bypass` policy and does not change the
machine or user execution policy. `run_vivado.cmd -Flow gui` is an equivalent
unsigned-script-safe entry point.

`synth` writes utilization, timing, and clock reports under `build/`. `impl`
stops after routed implementation, writes DRC/methodology reports and a DCP,
and generates `build/eriscv_m0_vcu108_wrapper.bit`. Board validation remains P14 work.
