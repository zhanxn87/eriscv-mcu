# eRISCV-M1

`eriscv-m1` is the mainstream cacheless MCU target. Its frozen contract is
`RV32IMC_Zicsr_Zifencei_Zicntr_Zihpm_Zihintpause` with M/U modes, Zicntr/Zihpm, the common 32-source PLIC
v1.0.0, Debug 1.0 Minimal, four 64-bit HPM counters, and a 16-entry PMP
platform.

It uses the common family platform and adds an area-balanced multi-cycle M
extension implementation plus a 16-entry PMP target. It excludes B, RV32F/D,
Zfa, S-mode/address translation, and all cache mechanisms. PMP protects locked
boot/firmware regions and enforces U-mode access policy.

## Start Here

- [Architecture contract](docs/eriscv-m1-architecture.md)
- [Verification contract](docs/eriscv-m1-verification.md)
- [Family product manual](https://eriscv-mcu-product-manual.zhanxnse.chatgpt.site/products/eriscv-m1)
- [Family evidence snapshot](../docs/Verification/eriscv-mcu-simulation-evidence-snapshot.md)
- [Design verification inventory](dv/README.md)
- [ACT4 profile](compliance/riscv-arch-test/README.md)
- [BSP and examples](sw/README.md)
- [FreeRTOS M-mode profile](sw/rtos/freertos/README.md)
- [FreeRTOS U-mode smoke](sw/rtos/freertos_umode/README.md)
- [CoreMark smoke](sw/benchmarks/coremark/README.md)
- [Embench-IoT adapter](sw/benchmarks/embench/README.md)
- [Microbench](sw/benchmarks/microbench/README.md)

Run `make eriscv-m1-full` from the repository root for the product-level
regression entry point. FPGA implementation and physical-board status are
separate evidence; see [the family documentation map](../docs/README.md).
