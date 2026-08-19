# eRISCV MCU Address-Space Specification v2.0

**Status:** Current family address-allocation contract. M2 populated-memory
and DMA-control evidence is focused RTL evidence, not peripheral-DMA or release
closure. Dated results are in the
[MCU Evidence Snapshot](../Verification/eriscv-mcu-simulation-evidence-snapshot.md).

This document owns global CPU-visible address allocation only. IMEM/DMEM
access semantics, boot arbitration, and executable permissions are owned by
the [Local Memory Architecture Specification](eriscv-mcu-memory-architecture-spec-v1.0.md).

## 1. Goals

v2 defines one sparse grouped 32-bit physical address space. Fixed windows
allow capacity growth without linker or ABI changes; unimplemented addresses
bus-fault and ROM, Flash, ITCM, DTCM, XRAM, and System SRAM never alias.
CLINT/PLIC retain conventional bases and system memory starts at `0x8000_0000`.

## 2. Top-level groups

| Range | Group | Purpose |
| --- | --- | --- |
| `0x0000_0000`--`0x0fff_ffff` | Platform | boot, interrupt control, platform debug/control |
| `0x1000_0000`--`0x1fff_ffff` | Local memory | tightly coupled memories local to the hart |
| `0x2000_0000`--`0x2fff_ffff` | Non-volatile images | internal and external Flash XIP windows |
| `0x3000_0000`--`0x3fff_ffff` | External boot/storage | reserved external boot-storage or memory-controller windows |
| `0x4000_0000`--`0x4fff_ffff` | Low-speed MMIO | APB peripherals and system configuration |
| `0x5000_0000`--`0x5fff_ffff` | High-speed MMIO | DMA and bandwidth-sensitive peripherals |
| `0x6000_0000`--`0x7fff_ffff` | External devices | reserved expansion windows |
| `0x8000_0000`--`0xbfff_ffff` | System memory | shared SRAM, PSRAM, or DDR |
| `0xc000_0000`--`0xffff_ffff` | Vendor extension | accelerators and product-specific expansion |

## 3. Platform group

| Range | Region | Access / role |
| --- | --- | --- |
| `0x0000_0000`--`0x0000_ffff` | Guard page | unmapped; catches null-pointer accesses |
| `0x0001_0000`--`0x0001_ffff` | Boot ROM | `RX`; reset vector for ROM boot |
| `0x0002_0000`--`0x00ff_ffff` | Boot/platform reserve | future ROM growth, lifecycle/OTP views; unmapped initially |
| `0x0200_0000`--`0x0200_ffff` | CLINT | MSIP, MTIP, `mtime`, `mtimecmp` |
| `0x0201_0000`--`0x02ff_ffff` | Interrupt-control reserve | future AIA or timer expansion |
| `0x0c00_0000`--`0x0cff_ffff` | PLIC | machine external interrupts |
| `0x0d00_0000`--`0x0dff_ffff` | Platform trace/control reserve | no M0/M1 implementation |

JTAG DMI is not CPU MMIO; any CPU-visible debug control block needs a separate
documented window.

## 4. Local-memory group

Each local-memory class owns a 16 MiB architectural window. Addresses outside
the populated capacity are unmapped and fault rather than aliasing SRAM.

| Range | Region | Product attributes | Initial capacity |
| --- | --- | --- | ---: |
| `0x1000_0000`--`0x10ff_ffff` | ITCM | `RX`; boot/debug provisioning may write; CPU DBus patch requires `fence.i` | 32 KiB M0; 64 KiB M1; 128 KiB M2 |
| `0x1100_0000`--`0x11ff_ffff` | DTCM | `RW`, non-executable | 32 KiB M0; 64 KiB M1; 128 KiB M2 |
| `0x1200_0000`--`0x12ff_ffff` | XRAM | `RWX`; true IF + LSU access, PMP restrictable | reserved; unimplemented |
| `0x1300_0000`--`0x1fff_ffff` | Local-memory reserve | trace RAM, additional banks, or future scratchpads | none |

XRAM, when implemented, is distinct dual-port SRAM rather than a DTCM alias or
testbench IMEM preload. Software executes `fence.i` after writing code; PMP
may restrict XRAM but never makes DTCM executable.

## 5. Non-volatile and external-memory groups

| Range | Region | Initial status |
| --- | --- | --- |
| `0x2000_0000`--`0x27ff_ffff` | Internal Flash XIP | future |
| `0x2800_0000`--`0x2fff_ffff` | QSPI/external Flash XIP | future |
| `0x3000_0000`--`0x3fff_ffff` | External boot-storage/controller windows | reserved |
| `0x8000_0000`--`0x8007_ffff` | M2 System SRAM | 512 KiB, `RW`, non-executable, CPU/DMA shared buffers |
| `0x8008_0000`--`0xbfff_ffff` | Future system memory | PSRAM/DDR or additional System SRAM; unmapped until product integration |

Flash XIP and boot ROM are separate, non-aliased views. A future ROM boot flow
may execute XIP or copy to local memory; direct UART/DMI boot preloads ITCM at
`0x1000_0000` and is not ROM boot.

## 6. MMIO allocation

The low-speed MMIO group uses 16 MiB functional subgroups and 64 KiB device
slots.  A device may occupy fewer bytes, but its slot is reserved permanently.

| Base | Slot | Initial assignment |
| --- | --- | --- |
| `0x4000_0000` | `+0x0000_0000` | UART0 |
| `0x4001_0000` | `+0x0001_0000` | GPIO0 |
| `0x4002_0000` | `+0x0002_0000` | timer block |
| `0x4003_0000` | `+0x0003_0000` | SPI0 |
| `0x4004_0000` | `+0x0004_0000` | watchdog |
| `0x4005_0000` | `+0x0005_0000` | clock/reset/power control |
| `0x4006_0000`--`0x40ff_ffff` | 64 KiB slots | future APB devices |
| `0x4100_0000`--`0x41ff_ffff` | system-control subgroup | pinmux, pads, security/OTP controls |
| `0x5000_0000`--`0x5000_ffff` | DMA control | M2 DMA registers |
| `0x5001_0000`--`0x50ff_ffff` | high-speed subgroup | future high-bandwidth IP |

## 7. Product applicability

- **M0:** ITCM and DTCM only; no XRAM or DMA claim.
- **M1:** inherits M0 ITCM/DTCM. XRAM is reserved but unimplemented; this
  migration makes no executable-data or XRAM claim.
- **M2:** implements 128 KiB ITCM at `0x1000_0000`, 128 KiB DTCM at
  `0x1100_0000`, 512 KiB System SRAM at `0x8000_0000`, and DMA control at
  `0x5000_0000`. The generic channel supports direct and linked-descriptor
  System SRAM copies; `CTRL`/`STATUS`/`SRC`/`DST`/`LEN`/`DESC_HEAD` occupy
  offsets `0x00`--`0x14`. CPU PMP does not automatically constrain DMA; the
  generic channel firewall permits only System SRAM. The detailed ABI is in
  [the M2 descriptor specification](../../eriscv-m2/docs/eriscv-m2-dma-descriptor-spec.md).

## 8. Migration closure requirements

A product may claim v2 only after one atomic migration updates:

1. `soc_pkg.sv` address constants, decode helpers, local-memory wrappers, and
   unmapped-access error behavior;
2. instruction-fetch routing, DBus/SBA routing, boot control, and debug
   address behavior;
3. linker scripts, startup code, BSP headers, examples, and boot image tools;
4. applicable Sail memory regions, ACT linker/profile artifacts, and generated
   manifests; core-only ACT maps remain core evidence and are not relabelled as
   product address-map evidence;
5. product architecture, verification, memory, and claim documents; and
6. directed tests for populated regions, decode boundaries, boot selection,
   and PMP permissions; add XRAM execution/`fence.i` only with XRAM RTL.

M0/M1 v1 artifacts must not be silently relabelled as v2 evidence.
