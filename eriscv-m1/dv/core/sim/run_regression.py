#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Run the product-local eRISCV-M1 core regression suite."""

from __future__ import annotations

import os
import sys
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parents[4] / "tools"
sys.path.insert(0, str(TOOLS_DIR / "sim"))
sys.path.insert(0, str(TOOLS_DIR / "project"))
from phase_regression import DEFAULT_FAIL_MARKERS, PhaseRegressionConfig, run_phase_regression
from resolve_filelist import write_resolved_filelist

PASS_MARKER = "ERISCV_M1 PASS:"
FAIL_MARKERS = ("ERISCV_M1 FAIL:", *DEFAULT_FAIL_MARKERS)

INHERITED_TESTS = {
    # Throughput guard for the C16 + raw-32-bit IF compose path.
    "MCU-C-IFETCH-CROSSWORD-01": {
        "phase": "core/C", "max_cycles": 160,
    },
    "MCU-WFI-01": {"phase": "core/WFI", "max_cycles": 200, "irq_start_cycle": 40, "irq_duration": 6},
    "MCU-M-01": {"phase": "core/M", "max_cycles": 800},
    "MCU-M-DIV-SHORT-01": {"phase": "core/M", "max_cycles": 180},
    "MCU-M-CTRL-01": {
        "phase": "core/M",
        "max_cycles": 600,
        "irq_on_muldiv_busy": 1,
    },
    "MCU-M-DIV-IRQ-01": {
        "phase": "core/M",
        "max_cycles": 800,
        "irq_on_muldiv_busy": 1,
    },
    "MCU-M-RESET-01": {
        "phase": "core/M",
        "max_cycles": 1000,
        "reset_on_muldiv_busy": 1,
    },
    "MCU-PMP-01": {"phase": "core/PMP", "max_cycles": 260, "completion_reg": 24, "completion_value": 1},
    "MCU-PMP-RESET-01": {"phase": "core/PMP", "max_cycles": 220},
    "MCU-PMP-SWEEP-01": {"phase": "core/PMP", "max_cycles": 500},
    "MCU-PMP-CFLOW-OVERLAP-01": {
        "phase": "core/PMP", "max_cycles": 360, "completion_reg": 24, "completion_value": 1,
    },
    "MCU-PMP-WFI-OVERLAP-01": {
        "phase": "core/PMP", "max_cycles": 220, "completion_reg": 24, "completion_value": 1,
    },
    "MCU-PMP-DEBUG-OVERLAP-01": {
        "phase": "core/PMP", "max_cycles": 360, "completion_reg": 24, "completion_value": 1,
        "debug_on_pmp_fault": 1, "debug_resume_cycle": 80, "expected_debug_cause": 1,
    },
    "MCU-PMP-IRQ-OVERLAP-01": {
        "phase": "core/PMP", "max_cycles": 360, "completion_reg": 24, "completion_value": 1,
        "irq_on_pmp_fault": 1,
    },
    "MCU-UMODE-01": {"phase": "core/U", "max_cycles": 400, "completion_reg": 24, "completion_value": 1},
    "MCU-UMODE-EXT-01": {"phase": "core/U", "max_cycles": 500, "completion_reg": 24, "completion_value": 1},
    "P1-ALU-01": {"phase": "core/legacy/phase1", "max_cycles": 80},
    "MCU-JAL-ID-01": {
        "phase": "core/JAL", "max_cycles": 200,
        "imem_read_latency": 3, "dedicated_latency": True,
    },
    # A one-cycle DTCM response must retire the second static load-use bubble.
    "MCU-LOAD-RESP-BYPASS-01": {
        "phase": "core/LDST", "max_cycles": 180,
    },
    "MCU-BTFNT-ID-01": {
        "phase": "core/BTFNT", "max_cycles": 260,
    },
    "MCU-BTFNT-C-01": {
        "phase": "core/BTFNT", "max_cycles": 260,
    },
    "MCU-RAS-01": {
        "phase": "core/RAS", "max_cycles": 220,
    },
    "P2-CFLOW-01": {"phase": "core/legacy/phase2", "max_cycles": 120},
    "P4-FWD-01": {"phase": "core/legacy/phase4", "max_cycles": 100},
    "P4-LDST-01": {"phase": "core/legacy/phase4", "max_cycles": 140},
    "P5-CSR-TRAP-01": {"phase": "core/legacy/phase5", "max_cycles": 180},
    # P5-SYS-MISALIGN-01 is RV32I/IALIGN=32-specific. eRISCV-M1 is RV32IC
    # with IALIGN=16, so its replacement evidence lives in the SoC product
    # regression: MCU-C-01 and MCU-C-DPC-01.
    "P7-FWD-STRESS-01": {"phase": "core/legacy/phase7", "max_cycles": 120},
    "P7-LDST-STRESS-01": {"phase": "core/legacy/phase7", "max_cycles": 180},
    "P7-CTRL-KILL-01": {"phase": "core/legacy/phase7", "max_cycles": 240},
    "P7-CSR-DEP-01": {"phase": "core/legacy/phase7", "max_cycles": 120},
    "MCU-COUNTER-CSR-01": {"phase": "core/HPM", "max_cycles": 140},
    "MCU-HPM-01": {"phase": "core/HPM", "max_cycles": 400},
    "MCU-HPM-CFLOW-01": {"phase": "core/HPM", "max_cycles": 240},
    "MCU-HPM-CSR-01": {"phase": "core/HPM", "max_cycles": 400},
    "MCU-HPM-TRAP-01": {"phase": "core/HPM", "max_cycles": 400},
    "MCU-HPM-IRQ-01": {"phase": "core/HPM", "max_cycles": 400},
    "MCU-HPM-WAIT-01": {
        "phase": "core/HPM",
        "max_cycles": 400,
        "imem_read_latency": 3,
        "dmem_read_latency": 4,
        "dedicated_latency": True,
    },
    "MCU-HPM-DEBUG-01": {
        "phase": "core/HPM",
        "max_cycles": 200,
        "expected_debug_cause": 2,
    },
    "MCU-HPM-PENDING-01": {
        "phase": "core/HPM",
        "max_cycles": 200,
        "irq_start_cycle": 40,
        "irq_duration": 6,
    },
    "P8-COUNTER-01": {"phase": "core/legacy/phase8", "max_cycles": 100},
    # P8-HPM-01 retired: assumed obsolete fixed event mapping without
    # programming mhpmevent3..6.  Replaced by MCU-HPM-01.
    "P9-IRQ-01": {"phase": "core/legacy/phase9", "max_cycles": 160, "irq_start_cycle": 40, "irq_duration": 6},
    "P10-MEMWAIT-01": {
        "phase": "core/legacy/phase10",
        "max_cycles": 180,
        "imem_read_latency": 3,
        "dmem_read_latency": 4,
        "dedicated_latency": True,
    },
    "P11-EXT-HALT-01": {
        "phase": "core/legacy/phase11",
        "max_cycles": 100,
        "debug_halt_cycle": 4,
        "debug_resume_cycle": 20,
        "expected_debug_cause": 1,
    },
    "P11-EBREAK-DRET-01": {
        "phase": "core/legacy/phase11",
        "max_cycles": 140,
        "expected_debug_cause": 2,
    },
    "P11-STEP-01": {
        "phase": "core/legacy/phase11",
        "max_cycles": 180,
        "expected_debug_cause": 4,
    },
}

COMPLIANCE_SMOKE = ()
# Zicsr-csrrw-00's ACT oracle is RV32I-misa-specific; eRISCV-M1's RV32IC
# CSR evidence is product-local in the SoC regression.
ACT_SMOKE = (
    "I-add-00",
    "I-lw-00",
    "I-beq-00",
    "I-jalr-00",
    "Zca-c.add-00",
    "M-mul-00",
    "M-div-00",
)

CONFIG = PhaseRegressionConfig(
    script_file=__file__,
    phase_label="eRISCV-M1 core",
    pass_marker=PASS_MARKER,
    fail_markers=FAIL_MARKERS,
    inherited_tests=INHERITED_TESTS,
    compliance_smoke=COMPLIANCE_SMOKE,
    compliance_exclude=("I-MISALIGN_JMP-01",),
    act_smoke=ACT_SMOKE,
    act_phase=os.environ.get(
        "ERISCV_ACT_PHASE",
        "compliance/riscv-arch-test/generated",
    ),
    allow_act=True,
    compliance_max_cycles=50000,
    act_max_cycles=50000,
    supports_latency_parameters=True,
    supports_addr_width_parameters=True,
    imem_word_addr_width=17,
    dmem_word_addr_width=17,
    act_imem_word_addr_width=17,
    act_dmem_word_addr_width=17,
    testcase_root_override=str(Path(__file__).resolve().parents[4] / "eriscv-m1"),
    product_dv_layout=True,
)


if __name__ == "__main__":
    sim_dir = Path(__file__).resolve().parent
    write_resolved_filelist(sim_dir / "filelist.f", sim_dir / "file.list")
    raise SystemExit(run_phase_regression(CONFIG))
