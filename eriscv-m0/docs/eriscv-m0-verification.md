# eRISCV-M0 Verification Contract

This contract defines the verification method, required coverage, and evidence
boundaries for the M0 architecture claim. Dated results, pass counts, commands,
and waivers belong in the
[MCU Evidence Snapshot](../../docs/Verification/eriscv-mcu-simulation-evidence-snapshot.md).

## Evidence Method

- Verilator product-directed core/SoC regression is the default path. ModelSim
  is used explicitly for focused single-test debugging and waveform inspection.
- ACT4 is the architectural-test flow and runs only at the core-TB boundary.
- Exact runnable tests, inputs, and runners are owned by the
  [design-verification inventory](../dv/README.md) and
  [ACT4 profile](../compliance/riscv-arch-test/README.md).
- Product-local RTL, DV, software, compliance, and FPGA artifacts are required;
  evidence from another product does not close an M0 requirement.

## Required Coverage

| Area | Required coverage |
| --- | --- |
| ISA | RV32I/C, Zicsr, Zifencei, Zicntr, Zihpm, and Zihintpause architectural tests; illegal encodings, alignment, and self-modifying IMEM behavior |
| Privilege and traps | Reset, CSR access, exception priority, `mret`, MSIP, MTIP, and MEIP directed tests |
| Platform | v2 map, boot, local-memory ownership, bus errors, CLINT, PLIC, Debug 1.0 Minimal, and peripheral integration |
| Software | `rv32ic_zicsr_zifencei_zicntr_zihpm_zihintpause` / `ilp32` product BSP startup/linker/UART, bare-metal examples, FreeRTOS integration, Zephyr board build, and declared boot paths |
| Release | Dated regression snapshot, tool versions, routed FPGA evidence, physical-board status, and known-deviation list |

The product BSP evidence specifically includes the normal bare-metal trap-vector
path and the FreeRTOS `ERISCV_MCU_BSP_SKIP_TRAP_INIT` path. UART/DMI boot-data
initialization cases must show that the complete initialized-DMEM load image is
copied from IMEM before `main`; Zephyr is separately validated under its native
`ROM=IMEM`, `RAM=DMEM` linker contract.

## Evidence Boundaries

- ACT4 does not cover boot transport, image loading, `crt0` initialization, or
  APB integration; those are SoC-TB responsibilities.
- RTL establishes the documented JTAG DTM/DMI, run-control, and
  abstract-register scope. OpenOCD/GDB interoperability requires FPGA or
  compatible JTAG hardware; its inputs and procedure are in the
  [board-smoke scaffold](../dv/soc/openocd-gdb/README.md).
- Standard OpenOCD ELF loading is not a Debug 1.0 Minimal product claim without
  a program buffer or supported SBA loading flow.
