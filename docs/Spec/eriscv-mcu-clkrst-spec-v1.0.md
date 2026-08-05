# eRISCV MCU Clock & Reset Controller Specification v1.0

**Status:** Frozen family contract, implemented in M0/M1 and integrated by M2
RTL/BSP. Section 12 defines the remaining product-local evidence requirements.

## 1. Scope and design rules

This document defines peripheral clock/reset control, RUN/SLEEP, wake sources,
and reset-cause reporting. v1.0 implements RUN and SLEEP only; DEEP_SLEEP,
power domains, clock switching, and frequency scaling are deferred.

`clk_sys`, APB, CLINT, PLIC, debug, and this controller remain active in
SLEEP; no low-speed always-on domain exists. Software clock bits are logical
enables, mapped through ASIC ICG, FPGA clock-enable, or vendor-clock wrappers;
fabric latch-and-AND gates are forbidden. The core clock stops only after
retired WFI asserts `cpu_wfi_i`, never directly from an APB write. System reset
restores safe defaults except `RST_CAUSE`; WDT0 stays clocked while enabled.

## 2. Fixed configuration

| Item | Value |
| --- | --- |
| APB slot | `0x4005_0000`-`0x4005_00FF` |
| Implemented registers | offsets `0x00`-`0x1C` |
| Gated domains | UART0, SPI0, TIMER0, GPIO0, WDT0 |
| Root-clock domains | controller, APB, CLINT, PLIC, debug |
| Power states | RUN, SLEEP; DEEP_SLEEP reserved |
| Wake inputs | UART RX, GPIO[7:0], CLINT MTIP, WDT pre-timeout |
| Peripheral reset pulse | 16 `clk_sys` cycles, then two release cycles |
| System reset pulse | at least 16 `clk_sys` cycles |

The APB slot follows UART0 (`0x4000_0000`), GPIO0 (`0x4001_0000`), TIMER0
(`0x4002_0000`), SPI0 (`0x4003_0000`), and WDT0 (`0x4004_0000`). Addresses in
the slot outside the implemented register offsets return `PSLVERR=1`.

## 3. Clock-control architecture

### 3.1 Logical enables

`peri_clk_en_o[4:0]` uses `{wdt, gpio, timer, spi, uart}`.

| Bit | Domain | Reset | Effective-enable rule |
| --- | --- | --- | --- |
| 0 | UART0 | on | `CLK_EN[0]` or reset-release override |
| 1 | SPI0 | on | `CLK_EN[1]` or reset-release override |
| 2 | TIMER0 | on | `CLK_EN[2]` or reset-release override |
| 3 | GPIO0 | on | `CLK_EN[3]` or reset-release override |
| 4 | WDT0 | on | `CLK_EN[4]` or `wdt_enabled_i` or reset-release override |

TIMER0 is the APB timer; CLINT MTIME is never gated. `CLK_STATUS` reports
effective enables, including overrides. Software must idle UART/SPI/TIMER
before disabling a clock: v1.0 has no busy veto or automatic gating, and an
active peripheral freezes if disabled. WDT0 remains clocked while enabled.

### 3.2 Technology mapping

The controller produces enables, not combinationally gated clocks. ASIC uses a
characterized ICG through a wrapper; FPGA normally uses synchronous peripheral
clock-enables and only uses vendor global-clock control when required;
simulation preserves the same register/reset behavior.

### 3.3 APB access to a stopped domain

When a selected peripheral clock is off or reset is active, the interconnect
suppresses that peripheral's `PSEL` and returns `PREADY=1`, `PRDATA=0`,
`PSLVERR=0`. Software must re-enable before access.

## 4. Reset architecture

### 4.1 Reset sources and priority

Accepted reset events use this fixed priority:

1. power-on reset (`por_n_i`),
2. external reset (`ext_rst_n_i`),
3. watchdog reset (`wdt_rst_n_i`),
4. software reset (`SOFT_RST.SYSRST`).

`por_n_i` and `ext_rst_n_i` may be asynchronous; outputs assert
asynchronously and deassert synchronously. WDT/software requests are sampled
on `clk_sys`; non-POR resets are at least 16 cycles, and a held request is one
accepted event. The controller records the highest-priority cause before
asserting `sys_rst_n_o`; lower simultaneous causes are discarded. System reset
covers CPU, memory control, PLIC, CLINT, and peripherals, not debug. Warm-reset
memory retention is implementation-defined.

### 4.2 Controller reset classes

| State | POR | EXT/WDT/SW reset | SLEEP wake |
| --- | --- | --- | --- |
| `CLK_EN` | `0x1F` | `0x1F` | retain |
| `SLEEP_CTRL` | `0` | `0` | request bit consumed |
| `WAKE_EN` | `0` | `0` | retain |
| `WAKE_STATUS` | `0` | `0` | latch wake event |
| `RST_CAUSE` | `POR` | selected latest cause | retain |
| pulse/state-machine state | clear | clear | return to RUN |

This policy guarantees that warm-reset boot code starts with all peripheral
clocks available. `RST_CAUSE` is implemented in the root-clock reset-capture
logic and is not cleared by `sys_rst_n_o`.

### 4.3 Per-peripheral reset

`PERI_RST[4:0]` matches `CLK_EN[4:0]`. A write of `1` starts a 16-cycle reset
pulse; write `0` has no effect; reads return zero. Multiple bits may be started
together. A request for WDT0 is ignored while `wdt_locked_i=1`.

For each requested domain, force its clock on, assert `peri_rst_n_o` for 16
cycles, deassert synchronously, retain the override for two cycles, then return
to `CLK_EN` and other overrides.

`peri_rst_n_o` is the effective peripheral reset after combining system and
software reset. It does not reset the CPU, memories, CLINT, PLIC, debug, or the
controller.

## 5. Reset-cause encoding

`RST_CAUSE[4:0]` records exactly one most recent system-reset cause.

| Bit | Name | Meaning |
| --- | --- | --- |
| 0 | `POR` | power-on reset |
| 1 | `EXT` | external reset |
| 2 | `WDT` | watchdog final timeout |
| 3 | `SW` | software system reset |
| 4 | reserved | future DEEP_SLEEP reset wake |

After POR the value is `0x1`. Each accepted non-POR event overwrites bits [4:0]
with its one-hot cause. Reserved bits read zero.

## 6. SLEEP architecture

### 6.1 Core handshake

`cpu_wfi_i` means WFI retired, younger work discarded, and no outstanding
memory transaction. Software arms sleep and wake sources; after `cpu_wfi_i`,
the controller rechecks wake levels, then gates `core_clk_en_o` or cancels
entry with `cpu_wake_o`. An enabled event, debug halt, or reset re-enables the
clock and pulses `cpu_wake_o`; execution resumes at WFI+4 or takes the pending
trap. Reset and debug halt are non-maskable wake conditions and do not set
`WAKE_STATUS`.

### 6.2 SLEEP_CTRL policy

- `SLEEP_REQ` is W1T. It arms the next WFI for SoC SLEEP and is consumed on
  entry, cancellation, or reset.
- `WFI_SLEEP_EN` is persistent. When set, every core WFI may enter SoC SLEEP
  without writing `SLEEP_REQ`.
- With both clear, WFI remains a core-local execution hold and the SoC stays in
  RUN. This preserves the existing `wfi_tickless` behavior.
- `DEEPSLEEP` writes are ignored and read zero in v1.0.

## 7. Wake sources

UART and GPIO inputs pass through two-flop synchronizers in the root-clock
domain before falling-edge detection. CLINT MTIP and WDT pre-timeout are
synchronous level sources. The corrected, non-overlapping bitmap is:

| Bit | Source | Hardware condition |
| --- | --- | --- |
| 0 | `UART_RX` | synchronized falling edge on `uart_rx_i` |
| 1 | `GPIO0` | synchronized falling edge on `gpio_i[0]` |
| 2 | `GPIO1` | synchronized falling edge on `gpio_i[1]` |
| 3 | `GPIO2` | synchronized falling edge on `gpio_i[2]` |
| 4 | `GPIO3` | synchronized falling edge on `gpio_i[3]` |
| 5 | `GPIO4` | synchronized falling edge on `gpio_i[4]` |
| 6 | `GPIO5` | synchronized falling edge on `gpio_i[5]` |
| 7 | `GPIO6` | synchronized falling edge on `gpio_i[6]` |
| 8 | `GPIO7` | synchronized falling edge on `gpio_i[7]` |
| 9 | `MTIP` | `clint_mtip_i=1` |
| 10 | `WDT_PRETIMEOUT` | `wdt_pretimeout_i=1` |
| 31:11 | reserved | zero |

GPIO wake is raw pad-edge detection; configure the pin as input. UART/GPIO wake
does not require its peripheral clock. WDT pre-timeout requires a valid enabled
pre-timeout; final expiry is reset, not wake. `WAKE_EN` affects SoC SLEEP only;
`WAKE_STATUS` records enabled entry/SLEEP events until RW1C or system reset. A
level already high cancels entry and is recorded; clear both source and status
before retrying.

## 8. APB register map

Registers are 32-bit little-endian words. Misaligned accesses and unimplemented
offsets return `PSLVERR=1`. `PREADY=1` in the APB access phase. Reserved bits
read zero and ignore writes. Writes act only on bytes selected by `PSTRB`; all
defined control bits are in byte lane 0.

| Off | Register | Access | Reset | Function |
| --- | --- | --- | --- | --- |
| `0x00` | `CLK_EN` | R/W | `0x0000_001F` | requested peripheral enables [4:0] |
| `0x04` | `CLK_STATUS` | RO | live | effective peripheral enables [4:0] |
| `0x08` | `PERI_RST` | W1T | read 0 | trigger peripheral reset [4:0] |
| `0x0C` | `RST_CAUSE` | RO | `0x1` after POR | one-hot latest cause [4:0] |
| `0x10` | `SLEEP_CTRL` | R/W | `0` | [0] SLEEP_REQ W1T, [1] reserved DEEPSLEEP, [2] WFI_SLEEP_EN |
| `0x14` | `WAKE_EN` | R/W | `0` | wake enables [10:0] |
| `0x18` | `WAKE_STATUS` | RW1C | `0` | wake status [10:0] |
| `0x1C` | `SOFT_RST` | W1T | read 0 | [0] SYSRST |

Access types: R/W = read/write, RO = read-only, W1T = write-one-trigger, and
RW1C = readable/write-one-to-clear.

## 9. Integration contract

<details>
<summary>Controller ports and SoC integration reference</summary>

### 9.1 Controller ports

| Port | Dir | Description |
| --- | --- | --- |
| `clk_sys`, `por_n_i` | in | root clock and power-on reset |
| APB slave | in/out | PSEL through PSLVERR; APB reset derives from POR |
| `ext_rst_n_i` | in | asynchronous external reset request |
| `wdt_rst_n_i` | in | WDT final-timeout reset request |
| `wdt_pretimeout_i` | in | WDT early-warning level |
| `wdt_enabled_i`, `wdt_locked_i` | in | WDT clock/reset overrides |
| `uart_rx_i`, `gpio_i[7:0]` | in | asynchronous wake inputs |
| `clint_mtip_i` | in | synchronous CLINT wake level |
| `cpu_wfi_i` | in | core WFI-complete handshake |
| `cpu_irq_pending_i` | in | non-maskable wake for other core interrupts |
| `debug_halt_req_i` | in | non-maskable debug wake |
| `cpu_wake_o` | out | synchronous core WFI-release pulse |
| `core_clk_en_o` | out | logical core clock enable |
| `peri_clk_en_o[4:0]` | out | effective peripheral clock enables |
| `peri_rst_n_o[4:0]` | out | effective peripheral resets |
| `sys_rst_n_o` | out | effective system reset |
| `sleep_flag_o` | out | high only while core clock is stopped |

### 9.2 Required SoC/core changes

Decode `0x1000_0500` with the Section 3.3 response, aggregate WDT final timeout
at system reset, route WDT status and core WFI/wake handshakes, and keep
technology-specific clock control at SoC integration rather than peripheral RTL.

</details>

## 10. BSP contract

The BSP provides clock masks and wake masks matching Sections 3 and 7, plus:

```c
void     clk_enable(uint32_t mask);
void     clk_disable(uint32_t mask);
uint32_t clk_status(void);
void     peri_sw_reset(uint32_t mask);
uint32_t get_reset_cause(void);
void     wfi_sleep_enable(int en);
void     enter_sleep(void);
void     wake_enable(uint32_t mask);
void     wake_disable(uint32_t mask);
uint32_t wake_status(void);
void     wake_status_clear(uint32_t mask);
void     soft_sys_reset(void);
```

`enter_sleep()` must clear stale wake status/device conditions as requested by
the caller, write `SLEEP_REQ`, execute an I/O/compiler barrier, then execute
WFI. `enter_deepsleep()` is not provided in v1.0.

## 11. Non-goals for v1.0

DEEP_SLEEP; power isolation or retention; independent low-speed always-on
clock; oscillator/PLL switching; dynamic frequency scaling; automatic idle
detection; CLINT gating; CPU-state crash dump; debug reset control;
configurable GPIO wake polarity.

## 12. Verification and freeze criteria

| Test | Required coverage |
| --- | --- |
| `MCU-CLKRST-01` | SoC POR defaults, clock request/status, stopped-domain APB response, reset while gated, byte-store behavior |
| `clk_rst_ctrl_tb` | block reset timing, WDT override, SLEEP/MTIP wake, software reset and safe defaults |
| `MCU-CLKRST-02` | peripheral reset while gated, 16+2 cycle timing, locked WDT rejection |
| `MCU-CLKRST-03` | POR/EXT/WDT/SW cause and simultaneous-source priority |
| `MCU-CLKRST-04` | WFI handshake, pending-at-entry cancellation, MTIP wake |
| `MCU-CLKRST-05` | UART/GPIO edge wake with peripheral clocks off |
| `MCU-CLKRST-06` | WDT pre-timeout wake followed by feed; final timeout reset |
| `MCU-CLKRST-07` | debug halt and reset during SLEEP |

RTL path: `rtl/peripherals/clk_rst/clk_rst_ctrl.sv`.
Integration paths: `rtl/soc/soc.sv`, `rtl/soc/bus/apb_interconnect.sv`, and
`rtl/soc/soc_pkg.sv`. The frozen interface still requires the listed directed
evidence for each integrated product; RTL presence alone is not closure.

Dated results are owned by the [MCU Evidence Snapshot](../Verification/eriscv-mcu-simulation-evidence-snapshot.md).
The remaining Section 12 cases are release-closure criteria, not evidence implied
by RTL presence.

## 13. Revision history

| Version | Date | Changes |
| --- | --- | --- |
| v1.0 review 2 | 2026-07-18 | Added safe clock technology mapping, WFI handshake, non-overlapping 11-bit wake map, WDT pre-timeout, reset priority, safe warm-reset defaults, and reset-release clock override. |
| v1.0 review 1 | 2026-07-17 | Initial RUN/SLEEP programming model; superseded. |
