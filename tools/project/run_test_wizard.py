#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Interactively select and run eRISCV simulation targets only."""

from __future__ import annotations

import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BACKENDS = ("verilator", "modelsim", "auto")
RUNNER_HINTS = {
    "eriscv-m0-bsp": "python3 eriscv-m0/sw/tools/run_hello_uart_sim.py",
    "eriscv-m0-bsp-async": "python3 eriscv-m0/sw/tools/run_hello_uart_sim.py",
    "eriscv-m0-coremark": "python3 eriscv-m0/sw/tools/run_coremark_sim.py",
    "eriscv-m0-dhrystone": "python3 eriscv-m0/sw/tools/run_dhrystone_sim.py",
    "eriscv-m0-embench": "python3 eriscv-m0/sw/tools/run_embench_sim.py",
    "eriscv-m0-microbench": "python3 eriscv-m0/sw/tools/run_microbench_sim.py",
    "eriscv-m0-freertos": "python3 eriscv-m0/sw/tools/run_freertos_sim.py",
    "eriscv-m0-freertos-qualification": "python3 eriscv-m0/sw/tools/run_freertos_sim.py --failstops",
    "eriscv-m0-zephyr": "python3 eriscv-m0/sw/tools/run_zephyr_sim.py",
    "eriscv-m1-bsp": "python3 eriscv-m1/sw/tools/run_hello_uart_sim.py",
    "eriscv-m1-bsp-async": "python3 eriscv-m1/sw/tools/run_hello_uart_sim.py",
    "eriscv-m1-mcycle-counter": "python3 eriscv-m1/sw/tools/run_mcycle_counter_sim.py",
    "eriscv-m1-coremark": "python3 eriscv-m1/sw/tools/run_coremark_sim.py",
    "eriscv-m1-dhrystone": "python3 eriscv-m1/sw/tools/run_dhrystone_sim.py",
    "eriscv-m1-embench": "python3 eriscv-m1/sw/tools/run_embench_sim.py",
    "eriscv-m1-microbench": "python3 eriscv-m1/sw/tools/run_microbench_sim.py",
    "eriscv-m1-freertos": "python3 eriscv-m1/sw/tools/run_freertos_sim.py",
    "eriscv-m1-freertos-qualification": "python3 eriscv-m1/sw/tools/run_freertos_sim.py --failstops",
    "eriscv-m1-freertos-umode": "python3 eriscv-m1/sw/tools/run_freertos_umode_sim.py",
    "eriscv-m1-zephyr": "python3 eriscv-m1/sw/tools/run_zephyr_sim.py",
    "eriscv-m2-bsp": "python3 eriscv-m2/sw/tools/run_hello_uart_sim.py",
    "eriscv-m2-bsp-async": "python3 eriscv-m2/sw/tools/run_hello_uart_sim.py",
    "eriscv-m2-bsp-fpu-dma-sram": "python3 eriscv-m2/sw/tools/run_hello_uart_sim.py",
    "eriscv-m2-mcycle-counter": "python3 eriscv-m2/sw/tools/run_mcycle_counter_sim.py",
    "eriscv-m2-coremark": "python3 eriscv-m2/sw/tools/run_coremark_sim.py",
    "eriscv-m2-dhrystone": "python3 eriscv-m2/sw/tools/run_dhrystone_sim.py",
    "eriscv-m2-embench": "python3 eriscv-m2/sw/tools/run_embench_sim.py",
    "eriscv-m2-microbench": "python3 eriscv-m2/sw/tools/run_microbench_sim.py",
    "eriscv-m2-freertos": "python3 eriscv-m2/sw/tools/run_freertos_sim.py",
    "eriscv-m2-freertos-qualification": "python3 eriscv-m2/sw/tools/run_freertos_sim.py --failstops",
    "eriscv-m2-freertos-umode": "python3 eriscv-m2/sw/tools/run_freertos_umode_sim.py",
    "eriscv-m2-zephyr": "python3 eriscv-m2/sw/tools/run_zephyr_sim.py",
}


@dataclass(frozen=True)
class Choice:
    name: str
    description: str
    targets: tuple[str, ...]


CHOICES = (
    Choice("M0 smoke", "M0 core and SoC smoke", ("eriscv-m0-core-smoke", "eriscv-m0-soc-smoke")),
    Choice("M0 full", "M0 full core and SoC regression", ("eriscv-m0-full",)),
    Choice("M1 full", "M1 full core and SoC regression", ("eriscv-m1-full",)),
    Choice("M2 smoke", "M2 core and SoC smoke", ("eriscv-m2-core-smoke", "eriscv-m2-soc-smoke")),
    Choice("M2 full", "M2 full core and SoC regression", ("eriscv-m2-full",)),
    Choice("M0 + M1 + M2 full", "all MCU full regressions", ("eriscv-mcu-full",)),
    Choice("M0 benchmark suite", "CoreMark, Dhrystone, Embench, microbench", (
        "eriscv-m0-coremark", "eriscv-m0-dhrystone", "eriscv-m0-embench", "eriscv-m0-microbench",
    )),
    Choice("M1 benchmark suite", "CoreMark, Dhrystone, Embench, microbench", (
        "eriscv-m1-coremark", "eriscv-m1-dhrystone", "eriscv-m1-embench", "eriscv-m1-microbench",
    )),
    Choice("M2 benchmark suite", "CoreMark, Dhrystone, Embench, microbench", (
        "eriscv-m2-coremark", "eriscv-m2-dhrystone", "eriscv-m2-embench", "eriscv-m2-microbench",
    )),
    Choice("M0 software suite", "BSP, benchmarks, FreeRTOS, Zephyr", (
        "eriscv-m0-bsp", "eriscv-m0-bsp-async", "eriscv-m0-coremark", "eriscv-m0-dhrystone",
        "eriscv-m0-embench", "eriscv-m0-microbench", "eriscv-m0-freertos", "eriscv-m0-zephyr",
    )),
    Choice("M1 software suite", "BSP, benchmarks, FreeRTOS, Zephyr", (
        "eriscv-m1-bsp", "eriscv-m1-bsp-async", "eriscv-m1-mcycle-counter", "eriscv-m1-coremark",
        "eriscv-m1-dhrystone", "eriscv-m1-embench", "eriscv-m1-microbench", "eriscv-m1-freertos",
        "eriscv-m1-freertos-umode", "eriscv-m1-zephyr",
    )),
    Choice("M2 software suite", "BSP, benchmarks, FreeRTOS, Zephyr", (
        "eriscv-m2-bsp", "eriscv-m2-bsp-async", "eriscv-m2-bsp-fpu-dma-sram",
        "eriscv-m2-mcycle-counter", "eriscv-m2-coremark", "eriscv-m2-dhrystone",
        "eriscv-m2-embench", "eriscv-m2-microbench", "eriscv-m2-freertos",
        "eriscv-m2-freertos-umode", "eriscv-m2-zephyr",
    )),
    Choice("M0 core", "M0 core regression", ("eriscv-m0-core",)),
    Choice("M0 core smoke", "M0 core smoke regression", ("eriscv-m0-core-smoke",)),
    Choice("M0 SoC", "M0 SoC regression", ("eriscv-m0-soc",)),
    Choice("M0 SoC smoke", "M0 SoC integration smoke", ("eriscv-m0-soc-smoke",)),
    Choice("M0 ACT", "M0 full ACT4 regression", ("eriscv-m0-act",)),
    Choice("M0 clock/reset", "M0 clock/reset ModelSim regression", ("eriscv-m0-clk-rst",)),
    Choice("M0 TCM arbitration", "M0 TCM arbitration ModelSim test", ("eriscv-m0-tcm-arbitration",)),
    Choice("M0 CoreMark", "build and run M0 CoreMark", ("eriscv-m0-coremark",)),
    Choice("M0 Dhrystone", "build and run M0 Dhrystone", ("eriscv-m0-dhrystone",)),
    Choice("M0 Embench", "build and run M0 Embench-IoT", ("eriscv-m0-embench",)),
    Choice("M0 microbench", "build and run M0 microbench", ("eriscv-m0-microbench",)),
    Choice("M0 BSP", "run M0 BSP workload", ("eriscv-m0-bsp",)),
    Choice("M0 BSP async", "run M0 async BSP workload", ("eriscv-m0-bsp-async",)),
    Choice("M0 FreeRTOS", "build and run M0 FreeRTOS", ("eriscv-m0-freertos",)),
    Choice("M0 Zephyr", "build and run M0 Zephyr", ("eriscv-m0-zephyr",)),
    Choice("M0 board debug", "OpenOCD/GDB smoke; requires ADAPTER_CFG", ("eriscv-m0-openocd-gdb",)),
    Choice("M1 core", "M1 core regression", ("eriscv-m1-core",)),
    Choice("M1 core smoke", "M1 core smoke regression", ("eriscv-m1-core-smoke",)),
    Choice("M1 SoC", "M1 SoC regression", ("eriscv-m1-soc",)),
    Choice("M1 SoC smoke", "M1 SoC integration smoke", ("eriscv-m1-soc-smoke",)),
    Choice("M1 ACT", "M1 full ACT4 regression", ("eriscv-m1-act",)),
    Choice("M1 TCM arbitration", "M1 TCM arbitration ModelSim test", ("eriscv-m1-tcm-arbitration",)),
    Choice("M1 CoreMark", "build and run M1 CoreMark", ("eriscv-m1-coremark",)),
    Choice("M1 Dhrystone", "build and run M1 Dhrystone", ("eriscv-m1-dhrystone",)),
    Choice("M1 Embench", "build and run M1 Embench-IoT", ("eriscv-m1-embench",)),
    Choice("M1 microbench", "build and run M1 microbench", ("eriscv-m1-microbench",)),
    Choice("M1 BSP", "run M1 BSP workload", ("eriscv-m1-bsp",)),
    Choice("M1 BSP async", "run M1 async BSP workload", ("eriscv-m1-bsp-async",)),
    Choice("M1 mcycle counter", "run M1 mcycle-counter workload", ("eriscv-m1-mcycle-counter",)),
    Choice("M1 FreeRTOS", "build and run M1 FreeRTOS", ("eriscv-m1-freertos",)),
    Choice("M1 FreeRTOS U-mode", "build and run M1 FreeRTOS U-mode", ("eriscv-m1-freertos-umode",)),
    Choice("M1 Zephyr", "build and run M1 Zephyr", ("eriscv-m1-zephyr",)),
    Choice("M1 board debug", "OpenOCD/GDB smoke; requires ADAPTER_CFG", ("eriscv-m1-openocd-gdb",)),
    Choice("M2 core", "M2 core regression", ("eriscv-m2-core",)),
    Choice("M2 core smoke", "M2 core smoke regression", ("eriscv-m2-core-smoke",)),
    Choice("M2 SoC", "M2 SoC regression", ("eriscv-m2-soc",)),
    Choice("M2 SoC smoke", "M2 SoC integration smoke", ("eriscv-m2-soc-smoke",)),
    Choice("M2 ACT", "M2 full ACT4 regression", ("eriscv-m2-act",)),
    Choice("M2 TCM arbitration", "M2 TCM arbitration ModelSim test", ("eriscv-m2-tcm-arbitration",)),
    Choice("M2 DMA/System SRAM", "M2 DMA/System-SRAM ModelSim test", ("eriscv-m2-dma-system-sram",)),
    Choice("M2 CoreMark", "build and run M2 CoreMark", ("eriscv-m2-coremark",)),
    Choice("M2 Dhrystone", "build and run M2 Dhrystone", ("eriscv-m2-dhrystone",)),
    Choice("M2 Embench", "build and run M2 Embench-IoT", ("eriscv-m2-embench",)),
    Choice("M2 microbench", "build and run M2 microbench", ("eriscv-m2-microbench",)),
    Choice("M2 BSP", "run M2 BSP workload", ("eriscv-m2-bsp",)),
    Choice("M2 BSP async", "run M2 async BSP workload", ("eriscv-m2-bsp-async",)),
    Choice("M2 FPU/DMA/SRAM BSP", "run M2 FPU/DMA/System-SRAM BSP workload", ("eriscv-m2-bsp-fpu-dma-sram",)),
    Choice("M2 FreeRTOS", "build and run M2 FreeRTOS", ("eriscv-m2-freertos",)),
    Choice("M2 FreeRTOS U-mode", "build and run M2 FreeRTOS U-mode", ("eriscv-m2-freertos-umode",)),
    Choice("M2 Zephyr", "build and run M2 Zephyr", ("eriscv-m2-zephyr",)),
    Choice("M2 board debug", "OpenOCD/GDB smoke; requires ADAPTER_CFG", ("eriscv-m2-openocd-gdb",)),
    Choice("M0 FreeRTOS qualification", "M0 FreeRTOS with injected fail-stops", ("eriscv-m0-freertos-qualification",)),
    Choice("M1 FreeRTOS qualification", "M1 FreeRTOS with injected fail-stops", ("eriscv-m1-freertos-qualification",)),
)


def select_backend() -> str:
    default = os.environ.get("SIM_BACKEND", "verilator")
    while True:
        backend = input(f"Simulation backend [{default}] ({'/'.join(BACKENDS)}): ").strip() or default
        if backend in BACKENDS:
            return backend
        print(f"Invalid backend: {backend}")


def select_choices() -> list[Choice]:
    print("\nAvailable tests and combinations:")
    for index, choice in enumerate(CHOICES, start=1):
        print(f"  {index:2d}. {choice.name:<20} - {choice.description}")

    while True:
        raw = input("\nSelect one or more numbers (comma-separated, q to quit): ").strip().lower()
        if raw in {"q", "quit"}:
            raise SystemExit(0)
        try:
            indexes = [int(value.strip()) for value in raw.split(",") if value.strip()]
        except ValueError:
            indexes = []
        if indexes and all(1 <= index <= len(CHOICES) for index in indexes):
            return [CHOICES[index - 1] for index in indexes]
        print("Enter one or more menu numbers, for example: 1,15,23")


def unique_targets(choices: list[Choice]) -> list[str]:
    return list(dict.fromkeys(target for choice in choices for target in choice.targets))


def main() -> int:
    backend = select_backend()
    choices = select_choices()
    targets = unique_targets(choices)
    print("\nSelected targets:")
    for target in targets:
        print(f"  make SIM_BACKEND={backend} {target}")
    if input("Run selected targets serially? [y/N]: ").strip().lower() not in {"y", "yes"}:
        print("Cancelled.")
        return 0

    failures: list[str] = []
    for target in targets:
        print(f"\n{'=' * 72}\nRunning: make SIM_BACKEND={backend} {target}", flush=True)
        if target in RUNNER_HINTS:
            print(f"Runner:  {RUNNER_HINTS[target]}", flush=True)
        print("=" * 72, flush=True)
        result = subprocess.run(["make", f"SIM_BACKEND={backend}", target], cwd=ROOT)
        if result.returncode:
            failures.append(target)

    print("\nTest wizard summary:")
    for target in targets:
        print(f"  {'FAIL' if target in failures else 'PASS'} {target}")
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
