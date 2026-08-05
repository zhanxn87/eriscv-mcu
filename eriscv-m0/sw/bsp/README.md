# eRISCV-M0 Product BSP

This directory owns the M0 product-level software implementation shared by
bare-metal applications and RTOS integrations.

| Area | Owner |
|---|---|
| Public register and feature contract | `../include/` |
| Linker and image layout contract | `../linker/` |
| Reset, `.data` copy and `.bss` clear | `startup/crt0.S` |
| Product UART implementation | `drivers/uart.c` |
| Bare-metal M-mode trap dispatch | `../lib/trap.S`, `../lib/trap.c` |

`startup/crt0.S` installs the product bare-metal trap vector by default.
FreeRTOS builds it with `ERISCV_MCU_BSP_SKIP_TRAP_INIT`, because the FreeRTOS
RISC-V port owns `mtvec`. Zephyr retains its native device-model drivers and
startup path; it consumes the same M0 address, ISA and memory-size contract
from its board/SoC port rather than this freestanding source set.

The M0 bare-metal linker places initialized data and read-only data in DTCM
with their load image in ITCM. RTOS ports must make their own startup/linker
copy semantics explicit before adopting that layout.

## Performance status

The shared-source migration is behavior-preserving: `drivers/uart.c` is the
previous M0 UART implementation moved without an algorithm or register-access
change, and it has no claimed cycle benefit. The existing M0 linker layout is
the applicable software performance configuration: a 1,000-iteration `-O2`
Dhrystone run changed from 850,016 to 819,016 cycles (-3.647%) when readonly
data moved from the IMEM D-bus window to DTCM. That result applies to the
bare-metal and FreeRTOS linker flow, not to Zephyr's standard linker model.

UART submission now has two software fast paths: asynchronous writes send
directly to the hardware TX FIFO while the software queue is empty, and
`eriscv_mcu_uart_puts()` submits a string without a public `putc()` call per
byte. The buffered/interrupt path remains responsible for hardware-FIFO
backpressure. These paths reduce foreground MMIO and queue-management work;
they do not change the UART baud-limited wire throughput. A dedicated UART
submission/IRQ microbenchmark is still required before publishing a cycle
delta.
