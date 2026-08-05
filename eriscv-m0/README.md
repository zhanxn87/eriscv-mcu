# eRISCV-M0

`eriscv-m0` is the lowest-area M-mode MCU product. Its frozen contract is
`RV32IC_Zicsr_Zifencei_Zicntr_Zihpm_Zihintpause` in M-mode, with machine
software/timer/external interrupts, a 32-source PLIC v1.0.0 platform, four
64-bit HPM counters, and RISC-V Debug Specification 1.0 Minimal external
debug.

It excludes M, B, PMP, U-mode, atomics, supervisor mode, and every cache
mechanism.

## Start Here

- [Architecture contract](docs/eriscv-m0-architecture.md)
- [Verification contract](docs/eriscv-m0-verification.md)
- [Family product manual](../docs/product-manual/products/eriscv-m0.html)
- [Family evidence snapshot](../docs/Verification/eriscv-mcu-simulation-evidence-snapshot.md)
- [Design verification inventory](dv/README.md)
- [ACT4 profile](compliance/riscv-arch-test/README.md)
- [BSP and examples](sw/README.md)
- [FreeRTOS M-mode profile](sw/rtos/freertos/README.md)
- [Microbench](sw/benchmarks/microbench/README.md)
- [OpenOCD/GDB board-smoke scaffold](dv/soc/openocd-gdb/README.md)

Run `make eriscv-m0-full` from the repository root for the product-level
regression entry point. FPGA implementation and physical-board status are
separate evidence; see [the family documentation map](../docs/README.md).
