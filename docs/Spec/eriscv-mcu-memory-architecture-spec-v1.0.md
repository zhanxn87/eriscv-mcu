# eRISCV MCU Local Memory Architecture Specification v1.0

**Status:** Frozen M0/M1 contract; M2 has focused RTL evidence for populated
memories and generic System-SRAM DMA. Peripheral DMA masters and release
closure remain open.

## 1. Scope

This specification defines local-memory, boot-image, and simulation-harness
semantics. It is a product memory contract, not an ISA extension.

Global CPU-visible window allocation is owned by the
[Address-Space Specification v2.0](eriscv-mcu-address-space-spec-v2.0.md).
This document owns only local-memory behavior within those windows.

**Verification boundary:** ACT4 runs only in the core testbench. Boot-mode,
boot-image, and `crt0` initialization behavior run only in the SoC testbench.
ACT4 does not exercise a product boot transport. The SoC regression entry point
rejects `--act-smoke` and `--act-full`; a core launch rejects non-bypass
`boot_mode` values.

## 2. M0/M1 local TCM contract

M0/M1 implement cacheless IMEM (ITCM-like) and DMEM (DTCM-like) SRAM.

| Region | Range | Size | Product role | IF fetch | CPU data access | Default accepted-request latency |
| --- | --- | ---: | --- | --- | --- | --- |
| IMEM | `0x1000_0000`--`0x1000_ffff` | 64 KiB | ITCM-like code SRAM | yes | read/write through DBus | 1 cycle |
| DMEM | `0x1100_0000`--`0x1100_ffff` | 64 KiB | DTCM-like data SRAM | no | read/write through DBus | 1 cycle |

Both regions use the 1RW byte-write, read-first SRAM boundary.  They have no
instruction cache, data cache, external coherency, or DMA master in M0/M1.
The one-cycle statement applies after the request is accepted; it is not an
unconditional service guarantee.

The deployed M0/M1 IMEM implementation accepts one word-aligned 32-bit IF
request at a time. The IF stage retains a compressed upper halfword; when an
RV32 instruction begins there, `ENABLE_UPPER_32_PREFETCH_P` issues the next
word request in the same response cycle and assembles the instruction from the
two adjacent responses. The option is enabled by default. It does not change
the software-visible memory contract or the DBus and boot-writer arbitration
rules.

### 2.1 IMEM contention and self-modifying code

IMEM logical arbitration is `boot writer > CPU DBus > IF`. An IMEM DBus or
boot transaction stalls instruction fetch until that transaction completes.
DBus writes to IMEM are permitted; software shall
execute `fence.i` before fetching modified code. This is local-memory
self-modifying-code behavior, not a cache-coherency claim.

### 2.2 DMEM contention

DMEM is a local 1RW SRAM.  During normal execution the CPU DBus owns it.  A
Debug System Bus Access transaction may temporarily own the SRAM and stall a
CPU data transaction.  M0/M1 contain no DMA master, so they make no concurrent
DMA/DMEM latency claim.

### 2.3 Executability and PMP

Only IMEM is an executable address-map region.  DMEM is non-executable even if
a PMP entry grants X permission: a fetch is allowed only when both the address
map permits fetch and PMP permits execute access.  PMP can restrict an
executable region; it cannot make DMEM executable.

## 3. Software and boot-image contract

M0 and M1 assign `.text` to IMEM. Their `.rodata`, `.srodata`, `.data`, and
`.sdata` have runtime VMAs in DMEM and initial-value LMAs in IMEM (the unified
`.data > DMEM AT > IMEM` copy region). `crt0` copies that initialized region
from IMEM to DMEM and clears `.bss` before calling `main`.

M0 bare-metal/FreeRTOS and M1 bare-metal/M-mode FreeRTOS use this contract.
M0 FreeRTOS suppresses only standalone `mtvec` installation. Zephyr and M1
U-mode FreeRTOS retain independent linker layouts and require separate
validation before adopting readonly-data relocation.

A UART or DMI boot transport writes the complete IMEM image, including the
M0/M1 initialized-data LMA bytes, then releases instruction fetch. It does not
initialize DMEM directly. `.noinit` is not cleared by `crt0`.

The UART and DMI boot test agents accept `$readmemh` word-address directives
(`@<word-address>`) as well as contiguous word images, preserving sparse IMEM
image semantics across bypass and boot-mode verification.

`tools/sim/elf_to_dmi_boot.py` accepts an ELF32 little-endian image with entry
`0x1000_0000` and emits only DMI boot registers `0x60` (address), `0x61` (word
data), and `0x62` (hold/release). It derives bytes from physical IMEM, includes
the `.data` LMA, and never initializes DMEM directly. The SoC testbench replays
the trace through bit-level JTAG; `MCU-BOOT-DATA-INIT-JTAG-ELF-01` checks normal
`.data`/`.bss` startup.

This converter is not a cable driver and does not establish OpenOCD/GDB or
physical-board interoperability.

`readmemh` is a simulator-only initialization mechanism:

| Simulation mode | IMEM | DMEM |
| --- | --- | --- |
| Bypass/preload regression | TB may preload both images | TB may preload the data image |
| UART/DMI boot fidelity | Boot protocol writes the IMEM image | TB must not preload the data image; `crt0` initializes it |

## 4. ACT executable-data compatibility

Some ACT PMP artifacts jump to data-image payloads, which requires executable
data unavailable in M0/M1. Only manifest-declared `exec_data_mirror: true`
artifacts may use the core-TB-only IMEM mirror. This is harness compatibility,
not an XRAM/DMEM-execution claim; the preferred fix is a dedicated IMEM window.

## 5. M2 direction

M2 enlarges the local TCM contract and adds a separate System SRAM region for
shared buffers, with CPU and DMA access through an arbitrated system path.

| Region | Range | Size | Product role | Access rule |
| --- | --- | ---: | --- | --- |
| ITCM | `0x1000_0000`--`0x1001_ffff` | 128 KiB | M2 code SRAM | `RX`; boot/debug provisioning may write; DBus patch requires `fence.i` |
| DTCM | `0x1100_0000`--`0x1101_ffff` | 128 KiB | M2 local data SRAM | `RW`, non-executable |
| System SRAM | `0x8000_0000`--`0x8007_ffff` | 512 KiB | CPU/DMA shared buffers | `RW`, non-executable by default |

ITCM/DTCM remain local CPU memories and must not traverse DMA arbitration.
M2 uses the same 32-bit IMEM response and retained-halfword assembly mechanism
as M0/M1, with the larger 128 KiB ITCM capacity shown above. This is not an
instruction cache: there is no tag lookup, refill policy, cacheable alias, or
cache-maintenance operation. `fence.i` invalidates retained fetch state before
modified IMEM code is fetched.
System SRAM uses eight 64 KiB interleaved 1RW banks with byte-address bits
`[4:2]` selecting the bank and `[18:5]` selecting the local word. The current
ingress set is CPU DBus plus generic DMA; each accepted request has a
registered one-cycle SRAM response. ECC/error reporting, retention, and
future Ethernet/Wi-Fi/debug masters remain open. CPU PMP governs CPU accesses
to all three regions; it does not automatically constrain DMA.

An independent XRAM (`RWX`) remains deferred.  It is justified only by a
product requirement for runtime-loaded code beyond the IMEM overlay capability,
such as large dynamic modules or JIT-like execution.  DMA alone is not an XRAM
requirement.

M2 generic DMA uses a System-SRAM-only firewall: ITCM, DTCM, IMEM, MMIO,
debug, and external-memory accesses are rejected. Its direct/descriptor ABI is
defined in [Generic DMA Descriptor v1](../../eriscv-m2/docs/eriscv-m2-dma-descriptor-spec.md).

## 6. Contract artifacts

- Product architecture documents own the address map, accepted-request latency,
  arbitration, and boot contract.
- Linker scripts express software placement: IMEM `rx`, DMEM `rw`.
- Core-only `sail.json`/ACT profiles describe their core-testbench regions;
  they are not product address-map artifacts. Product linker/BSP/SoC evidence
  defines the v2 physical regions above.
- UDB describes ISA/privilege capability and does not define this SoC memory
  topology.
