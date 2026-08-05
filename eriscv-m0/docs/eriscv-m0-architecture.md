# eRISCV-M0 Architecture

## 1. Purpose and Claim

`eriscv-m0` is the smallest eRISCV MCU product target. It is a
deterministic, cacheless, single-hart bare-metal MCU for control firmware.
The frozen architectural contract is:

- ISA: `RV32IC_Zicsr_Zifencei_Zicntr_Zihpm_Zihintpause`, `ilp32`, `IALIGN=16`.
- Privilege: M-mode only; `WFI` suspends instruction fetch until a pending interrupt or debug request.
- Interrupts: machine software, timer, and external interrupts through CLINT
  and a 32-source PLIC v1.0.0 implementation.
- Debug: RISC-V Debug Specification 1.0 Minimal, single hart, JTAG DTM/DMI.
- Memory: local executable and data RAM; no instruction, data, or shared cache.

This document describes the RTL architecture and software contract. The
verification status is owned by [eriscv-m0-verification.md](eriscv-m0-verification.md): an
implemented block with open evidence is not a release claim.

## 2. Product Boundary

| Area | Contract | Boundary |
| --- | --- | --- |
| Core | RV32IC + `Zicsr` + `Zifencei` + `Zicntr` + `Zihpm` + `Zihintpause`, M-mode | Product-local core RTL |
| Local memory | 64 KiB IMEM + 64 KiB DMEM | Fixed one-cycle local TCM contract |
| Interrupt platform | CLINT plus 32-source PLIC | Machine-local and PLIC interrupt paths |
| Debug | Debug 1.0 Minimal over JTAG DTM/DMI | Board interoperability is a separate hardware claim |
| BSP | Freestanding startup, linker, MMIO definitions | Product-local software contract |
| Boot transport | Bypass, JTAG/DMI, UART, SPI slave loaders | Board transport qualification is separate from TB boot evidence |

Explicitly out of scope: M, B, PMP, U-mode, atomics, supervisor mode, AIA,
cryptographic extensions, `Zbc`, secure boot, caches, flash/XIP, and a
production image format.

## 3. Top-Level Architecture

```text
                     JTAG pins
                        |
                 +------+------+
                 | sys_ctrl    |
                 | DTM/DMI +   |
                 | Debug Module|
                 | boot mux    |
                 +--+-------+--+
                    |       |
             halt/resume    +--> IMEM boot writer
                    |                 ^
                    v                 |
+---------+  I-bus +-------------------+    DBus
| RV32IC  |------->| shared single-port |<---------+
| 5-stage |        | IMEM, 64 KiB       |          |
| core    |        +-------------------+          |
+----+----+                                         |
     |                                              |
     +-------------------+--------------------------+
                         |
                 +-------v--------+
                 | DBus           |
                 | interconnect   |
                 +--+---+---+--+--+
                    |   |   |  |
                 DMEM CLINT PLIC APB bridge
                 64KiB  |    |     |
                         |    |  UART0 GPIO0 TIMER0 SPI0
                         |    |
                       MSIP/MTIP MEIP
                         \    /
                          v  v
                         core IRQs
```

`eriscv_m0` is the delivery top level. The core has separate instruction and
data request paths; the SoC owns address decode, local-memory arbitration,
peripheral access, interrupt composition, debug transport, and boot loading.

## 4. Core Microarchitecture

### 4.1 Pipeline

The core is an in-order five-stage design:

| Stage | Function |
| --- | --- |
| IF | Word-aligned IMEM fetch, 16-bit/32-bit instruction assembly, compressed-halfword buffering, redirect handling |
| ID | Decode, immediate generation, register read, compressed decompression, CSR/system decode |
| EX | ALU, branch/jump resolution, trap/interrupt arbitration, forwarding, debug entry/return |
| MEM | DBus load/store issue and response wait |
| WB | Register writeback and architectural retirement |

The front end fetches 32-bit IMEM words. For `C`, it can retire two 16-bit
instructions from one word and composes a 32-bit instruction that begins in an
upper halfword from two adjacent words. PC alignment is therefore 16 bits, not
32 bits.

### 4.2 Hazards, Ordering, and Exceptions

- The pipeline implements forwarding and load-use stalls.
- Memory responses stall in-order progress; the core has no speculative cache
  or reorder machinery.
- `pause` is a legal `Zihintpause` hint with no required delay; this cacheless
  single-hart implementation retires it with zero architectural side effects.
- Redirects cover branch/jump, `fence.i`, synchronous traps, interrupt traps,
  debug entry, and debug resume.
- `fence.i` redirects fetch after the older store has completed, discarding any
  prefetched instruction state.
- The supported machine control path includes reset, exceptions, machine
  interrupts, `mret`, `mstatus`, `mie`, `mip`, `mtvec`, `mepc`, `mcause`, and
  `mtval`, implemented counters, and debug CSRs. The frozen product counter
  contract is `mcycle`/`mcycleh`, `minstret`/`minstreth`, and
  `mcountinhibit.CY/IR/HPM3-HPM6`, and four 64-bit programmable HPM counters
  (`mhpmcounter3`-`mhpmcounter6`) selected through `mhpmevent3`-`mhpmevent6`.
  `time`/`timeh` read the CLINT `MTIME` source. For counter observation, a
  non-trapping EX completion is M0's retirement point; GPR writes still
  commit at WB.

`mcounteren` remains absent in this M-mode-only profile. The `cycle`, `time`,
`instret`, and `hpmcounter3`-`hpmcounter6` aliases are read-only views of the
implemented machine counters. The unimplemented `hpmcounter7`-`hpmcounter31`
aliases (including their high halves) are read-only zero and do not trap on reads.

### 4.3 Debug Core Interface

External debug requests halt only after the pipeline drains. While halted, the
Debug Module can access integer GPRs `x0` through `x31` and `dcsr`, `dpc`,
`dscratch0`, and `dscratch1`. Resume redirects fetch to `dpc`. The complete
Debug 1.0 Minimal contract is in [eRISCV MCU Debug 1.0 Minimal Target](../../docs/Spec/eriscv-mcu-debug-1.0-minimal.md).

## 5. Memory System and DBus

### 5.1 Address Map

| Region | Base | End | Size | Access |
| --- | --- | --- | --- | --- |
| ITCM (IMEM) | `0x1000_0000` | `0x1000_FFFF` | 64 KiB | Instruction fetch; DBus read/write |
| DTCM (DMEM) | `0x1100_0000` | `0x1100_FFFF` | 64 KiB | DBus read/write; BSP data and stack; non-executable |
| CLINT | `0x0200_0000` | `0x0200_BFFF` | 48 KiB window | DBus read/write |
| PLIC | `0x0C00_0000` | `0x0C20_0FFF` | `0x0020_1000` | DBus read/write |
| APB window | `0x4000_0000` | `0x40FF_FFFF` | 16 MiB | DBus through APB bridge |
| UART0 | `0x4000_0000` | `0x4000_FFFF` | 64 KiB slot | APB |
| GPIO0 | `0x4001_0000` | `0x4001_FFFF` | 64 KiB slot | APB |
| TIMER0 | `0x4002_0000` | `0x4002_FFFF` | 64 KiB slot | APB |
| SPI0 | `0x4003_0000` | `0x4003_FFFF` | 64 KiB slot | APB |
| WDT0 | `0x4004_0000` | `0x4004_FFFF` | 64 KiB slot | APB |
| Clock/reset control | `0x4005_0000` | `0x4005_FFFF` | 64 KiB slot | APB |

The DMI boot window is private to `sys_ctrl`; it is not CPU DBus addressable.
The common PLIC register map, source allocation, priority, and claim/complete
rules are defined by the product-line
[PLIC specification](../../docs/Spec/eriscv-mcu-plic-spec-v1.0.md).

### 5.2 Local Memories

IMEM and DMEM are cacheless, locally coupled SRAM blocks with ITCM-like and
DTCM-like product roles. Their address widths select 16K 32-bit words each.
The M0 product contract fixes accepted IMEM and DMEM requests at one cycle.
Both use the portable
`mem/sram_1rw.sv` 1RW boundary: the default behavioral array infers FPGA block
RAM, while an ASIC flow may replace that module with a memory-compiler wrapper
preserving its byte-write, read-first, registered-read contract. SRAM contents
are not reset; reset only clears response bookkeeping. The common
[Address-Space Specification v2.0](../../docs/Spec/eriscv-mcu-address-space-spec-v2.0.md)
defines the product address allocation, executable-region, boot, and testbench
semantics.

IMEM is single port and shared by boot programming, DBus access, and fetch in
that priority order. Fetch waits during a higher-priority access. Firmware may
patch executable IMEM through DBus only when it subsequently executes
`fence.i`. DMEM is non-executable; Debug SBA access may temporarily delay a
CPU DMEM transaction. These are defined local-memory arbitration behaviors,
not a general cache-coherency protocol.

For one accepted higher-priority local-memory transaction, a continuously
asserted lower-priority request is admitted on the next root clock; its own
fixed one-cycle response then follows. A run of `N` higher-priority
transactions can defer admission by `N` clocks, so the product does not claim
a global bound without constraining the competing request rate.

### 5.3 Transactions and Errors

`dbus_interconnect` decodes each request to IMEM, DMEM, CLINT, PLIC, or the APB
bridge. Unmapped DBus requests return a response with an error indication and
do not alias local memory. The APB bridge uses IDLE/SETUP/ACCESS phases and a
one-entry request queue; all current APB peripherals return `PREADY=1`.
Invalid APB register offsets return `PSLVERR`, which propagates as a DBus error.

## 6. Peripheral Register Summary

All peripheral registers are 32-bit and little-endian. Exact software symbols
are maintained in [`sw/include/eriscv_mcu.h`](../sw/include/eriscv_mcu.h).

### 6.1 UART0 (`0x4000_0000`)

| Offset | Register | Behavior |
| --- | --- | --- |
| `0x00` | `TXDATA` | Write byte enqueues when `STATUS.TX_READY` is set |
| `0x04` | `RXDATA` | Read and dequeue next received byte; returns zero when empty |
| `0x08` | `STATUS` | Bit 0 TX FIFO has space, bit 1 RX FIFO is non-empty, bit 2 TX engine/FIFO busy, bit 3 sticky RX FIFO overrun |
| `0x0C` | `BAUDDIV` | Baud divisor |
| `0x10` | `CTRL` | Bit 0 TX enable, bit 1 RX enable, bit 2 RX IRQ enable |

UART0 implements 8N1 TX/RX with parameterized FIFOs: TX defaults to 32 bytes
and RX defaults to 64 bytes. `TXDATA` enqueues and the transmitter drains TX
FIFO automatically; `RXDATA` dequeues. The BSP provides polling and
interrupt-driven async TX; RX FIFO non-empty with `CTRL[2]` asserted is PLIC
source 1. FIFO watermarks, TX/error interrupts, and RTS/CTS remain deferred
commercial-UART enhancements. M0 has no DMA requirement and exposes no UART
DMA request interface.

### 6.2 GPIO0 (`0x4001_0000`)

| Offset | Register | Behavior |
| --- | --- | --- |
| `0x00` | `OUT` | Output data register |
| `0x04` | `IN` | Samples `gpio_i` |
| `0x08` | `DIR` | Output-enable bits (`1` is output) |

### 6.3 TIMER0 (`0x4002_0000`)

| Offset | Register | Behavior |
| --- | --- | --- |
| `0x00` | `CTRL` | Bit 0 enable, bit 1 IRQ enable |
| `0x04` | `COUNT` | 32-bit counter, readable and writable |
| `0x08` | `COMPARE` | Expiry comparison value; zero disables expiry |
| `0x0C` | `STATUS` | Bit 0 expiry; write one to clear |

When enabled, `COUNT` increments each SoC clock. Expiry with IRQ enabled drives
PLIC source 2.

### 6.4 SPI0 (`0x4003_0000`)

| Offset | Register | Behavior |
| --- | --- | --- |
| `0x00` | `TXDATA` | Write byte starts an idle enabled transfer |
| `0x04` | `RXDATA` | Completed receive byte |
| `0x08` | `STATUS` | Ready, busy, and done status |
| `0x0C` | `CLKDIV` | Serial clock divider; zero writes become one |
| `0x10` | `CTRL` | Enable, done IRQ enable, CPOL, CPHA, done clear, and bit-order controls |
| `0x14` | `SS` | Four active-low slave-select outputs |

SPI0 transfers one byte at a time. Done with IRQ enabled drives PLIC source 3.

### 6.5 WDT0 (`0x4004_0000`)

| Offset | Register | Behavior |
| --- | --- | --- |
| `0x00` | `CTRL` | Enable, feed-window, and pre-timeout IRQ enable |
| `0x04` | `TIMEOUT` | Countdown reload value in SoC clocks |
| `0x08` | `WINDOW` | Feed-window opening threshold; zero disables the window |
| `0x0C` | `FEED` | Write `0xACCE55ED` to reload an eligible watchdog |
| `0x10` | `STATUS` | Expiry/reset-cause/lock/pre-timeout status; expiry and pre-timeout are W1C |
| `0x14` | `LOCK` | Write one to lock configuration until reset |
| `0x18` | `PRETIMEOUT` | Remaining-count early-warning threshold; zero disables it |

WDT0 pauses while the hart is halted. An enabled pre-timeout drives PLIC source
4; expiry asserts the watchdog reset request.

### 6.6 Clock and Reset Control (`0x4005_0000`)

| Offset | Register | Behavior |
| --- | --- | --- |
| `0x00` / `0x04` | `CLK_EN` / `CLK_STATUS` | Peripheral clock control and effective enable state |
| `0x08` | `PERI_RST` | Pulse reset for selected peripheral domains |
| `0x0C` | `RST_CAUSE` | Power-on, external, watchdog, or software reset cause |
| `0x10` | `SLEEP_CTRL` | Explicit sleep request and WFI-sleep enable |
| `0x14` / `0x18` | `WAKE_EN` / `WAKE_STATUS` | Wake-source enable and W1C status |
| `0x1C` | `SOFT_RST` | Write one to request a warm software reset |

The controller owns peripheral clock/reset control and optional WFI sleep. Its
wake sources are UART RX, GPIO falling edges, MTIP, watchdog pre-timeout,
pending CPU interrupts, and debug-halt requests.

## 7. Interrupt Architecture

### 7.1 CLINT

CLINT is DBus-mapped and provides the local machine interrupt sources.

| Offset from `0x0200_0000` | Register | Notes |
| --- | --- | --- |
| `0x0000` | `MSIP` | Bit 0 software-interrupt pending |
| `0x4000` / `0x4004` | `MTIMECMP` low/high | 64-bit compare |
| `0xBFF8` / `0xBFFC` | `MTIME` low/high | 64-bit free-running counter; writable for testability |

`MSIP` drives `mip.MSIP` / interrupt bit 3. `MTIP` is asserted when
`MTIME >= MTIMECMP` and drives interrupt bit 7. Reset initializes `MTIME` to
zero and `MTIMECMP` to all ones.

### 7.2 PLIC

The PLIC has 32 global sources, source ID 0 reserved, one M-mode context, and
3-bit priorities. It implements level-sensitive pending state, enables,
threshold, claim, completion, and in-service tracking.

| Offset from `0x0C00_0000` | Register block |
| --- | --- |
| `0x0004 + 4*source` | Source priority, sources 1-32 |
| `0x1000` | Pending bitmap |
| `0x2000` | Enable bitmap for the M-mode context |
| `0x200000` | M-mode threshold |
| `0x200004` | M-mode claim/complete |

A claim read selects the highest-priority eligible source. Equal priority uses
the lower source ID because selection scans IDs in ascending order and replaces
the current winner only for a strictly higher priority. Completing a source
removes it from in-service; a source held high becomes pending again. PLIC
output is the sole SoC producer of `MEIP` / interrupt bit 11.

Source assignments are UART RX = 1, TIMER0 expiry = 2, SPI0 done = 3, and WDT0
pre-timeout = 4. Source 5 is the family DMA slot and sources 6-16 are future
device slots; M0 ties all of them low. `ext_irq_i[0]` maps to source 17 and
extends through source 32. Other top-level `irq_i` bits remain platform inputs
except the SoC-owned MSIP, MTIP, and MEIP bits.

## 8. Debug and System Control

The debug path is outside the CPU DBus/APB fabric:

```text
JTAG TAP -> DTM -> DMI CDC -> DMI router -> Debug Module -> core debug interface
                                      \-> boot DMI window when selected
```

The Debug Module is a fixed single-hart target (hart 0). It supports `dmactive`,
halt/resume requests, halted/running status, abstract 32-bit register access,
`data0`/`data1`, `cmderr`, sticky `havereset`, and the specified debug CSRs.
In addition to that Debug 1.0 Minimal baseline, the implemented debug path
provides exact-match `mcontrol` execution/load/store-address and store-data
triggers, an `icount` trigger, and DMI System Bus Access for 32-bit DMEM
reads/writes. Program buffer, trace, broader system-bus access, multi-hart
selection, and debug authentication/lifecycle policy remain unsupported.

Simulation verifies the DMI path, JTAG scan path, x0-x31 GPR sweep, Debug CSR
access, reset status, single step, and OpenOCD-like command sequence. A real
OpenOCD/GDB transcript remains a board-level task; see
[`dv/soc/openocd-gdb`](../dv/soc/openocd-gdb/README.md).

The SoC TB defaults to a 10 MHz TCK against a 100 MHz SoC clock. On a board,
the adapter drives TCK; begin qualification at a conservative adapter speed
and qualify `adapter speed 10000` separately. The expected TAP has IR length
5 and IDCODE `0x135711db`. Attach, halt, and abstract GPR access are the
supported OpenOCD smoke scope. Standard ELF loading is not claimed because the
target has no program buffer or qualified OpenOCD SBA loading flow.

## 9. Reset, Boot, and Firmware Images

`rst_n` is the active-low SoC reset. Core reset starts fetch at `boot_addr_i`
when `fetch_enable_i` permits it. `sys_ctrl` accepts four boot-mode values:

| Mode | Value | Intended behavior |
| --- | --- | --- |
| Bypass | `0` | Core fetches the existing IMEM image |
| JTAG/DMI | `1` | DMI boot registers write IMEM |
| UART | `2` | UART boot decoder writes IMEM, then relinquishes the shared RX pin after `RELEASE` until reset |
| SPI flash (reserved) | `3` | Reserved for a future SPI flash reader; no current boot path |

The JTAG/DMI and UART loaders share a command arbiter and IMEM boot writer.
`eriscv_m0` gates `fetch_enable_i` with `boot_fetch_enable_o`, so a non-bypass
boot mode holds the core until its loader explicitly releases fetch. ACT4 is
core-TB-only; boot transport, image loading, and data initialization are
SoC-TB responsibilities. A future SPI-flash boot design may use the reserved
mode after its flash reader and board pins are specified.

The product BSP lives in [`../sw/bsp`](../sw/bsp/README.md).  Bare-metal and
FreeRTOS reuse its reset implementation and UART driver; FreeRTOS suppresses
the standalone `mtvec` write because its kernel port owns the trap vector.
Zephyr retains a native device-model adapter and startup/linker flow.

- The bare-metal and FreeRTOS linker places `.text` in IMEM; `.rodata`, `.srodata`, `.data`, and `.sdata`
  run from DMEM with their combined load image in IMEM; `.bss` plus the stack
  remain in DMEM.
- The product `crt0.S` sets the stack, copies the complete initialized DMEM region, clears `.bss`, installs `mtvec`
  for bare-metal, and calls `main`.
- Zephyr intentionally retains its standard `ROM=IMEM`, `RAM=DMEM` layout;
  it does not inherit the freestanding `.rodata` relocation rule.

The freestanding build flow in [`../sw`](../sw/README.md) defines image
generation, build commands, and software integration tests. Verification method
and release evidence are defined by
[eriscv-m0-verification.md](eriscv-m0-verification.md) and the family
[MCU Evidence Snapshot](../../docs/Verification/eriscv-mcu-simulation-evidence-snapshot.md).

## 10. Product Ownership

`eriscv-m0` owns its core, SoC RTL, verification, tests, and BSP. Product RTL
must not import core or SoC RTL from another eRISCV MCU product. Product-local
evidence is required for every architecture claim.
