#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Convert a phase Verilator FST/VCD waveform into a Konata pipeline trace."""

from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


CORE_CANDIDATES = (
    "TOP.riscv_tb.dut.riscv_core_i",
    "TOP.riscv_soc_tb.dut.riscv_core_i",
)
BASE_SIGNALS = {
    "clk": "TOP.riscv_tb.clk",
    "rst_n": "TOP.riscv_tb.rst_n",
    "soc_clk": "TOP.riscv_soc_tb.clk",
    "soc_rst_n": "TOP.riscv_soc_tb.rst_n",
}
CORE_SIGNAL_SUFFIXES = {
    "fetch_valid": "instr_req_o",
    "fetch_pc": "instr_addr_o[31:0]",
    "if_id_valid": "if_id_q.valid",
    "if_id_pc": "if_id_q.pc[31:0]",
    "if_id_instr": "if_id_q.instr[31:0]",
    "id_ex_valid": "id_ex_q.valid",
    "id_ex_pc": "id_ex_q.pc[31:0]",
    "ex_mem_valid": "ex_mem_q.valid",
    "mem_wb_valid": "mem_wb_q.valid",
}


def signal_candidates() -> dict[str, list[str]]:
    candidates: dict[str, list[str]] = {
        "clk": [BASE_SIGNALS["clk"], BASE_SIGNALS["soc_clk"]],
        "rst_n": [BASE_SIGNALS["rst_n"], BASE_SIGNALS["soc_rst_n"]],
    }
    for name, suffix in CORE_SIGNAL_SUFFIXES.items():
        candidates[name] = [f"{core}.{suffix}" for core in CORE_CANDIDATES]
    return candidates


@dataclass
class Instruction:
    ident: int
    pc: int | None
    instr: int | None
    label: str


def bits_to_int(bits: str | None) -> int | None:
    if bits is None:
        return None
    bits = bits.lower()
    if any(ch in bits for ch in "xz"):
        return None
    try:
        return int(bits, 2)
    except ValueError:
        return None


def read_vcd(wave_path: Path) -> tuple[dict[str, str], list[dict[str, int | None]]]:
    if wave_path.suffix == ".fst":
        with tempfile.NamedTemporaryFile(dir=wave_path.parent, prefix=f".{wave_path.stem}-", suffix=".vcd", delete=False) as tmp:
            tmp_path = Path(tmp.name)
        try:
            with tmp_path.open("w", encoding="ascii", errors="replace") as out:
                subprocess.run(["fst2vcd", str(wave_path)], stdout=out, check=True)
            return parse_vcd(tmp_path)
        finally:
            tmp_path.unlink(missing_ok=True)
    return parse_vcd(wave_path)


def parse_vcd(vcd_path: Path) -> tuple[dict[str, str], list[dict[str, int | None]]]:
    id_by_path: dict[str, str] = {}
    name_by_id: dict[str, str] = {}
    values: dict[str, str | None] = {}
    scopes: list[str] = []
    samples: list[dict[str, int | None]] = []
    in_defs = True
    prev_clk = "0"

    candidates = signal_candidates()
    name_by_path = {path: name for name, paths in candidates.items() for path in paths}
    wanted_paths = set(name_by_path)

    with vcd_path.open("r", encoding="ascii", errors="replace") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue

            if in_defs:
                if line.startswith("$scope "):
                    parts = line.split()
                    if len(parts) >= 3:
                        scopes.append(parts[2])
                elif line.startswith("$upscope"):
                    if scopes:
                        scopes.pop()
                elif line.startswith("$var "):
                    parts = line.split()
                    if len(parts) >= 5:
                        ident = parts[3]
                        ref = " ".join(parts[4:-1])
                        ref = ref.replace(" [", "[")
                        full_path = ".".join([*scopes, ref])
                        if full_path in wanted_paths:
                            id_by_path[full_path] = ident
                            name_by_id[ident] = name_by_path[full_path]
                            values.setdefault(ident, None)
                elif line.startswith("$enddefinitions"):
                    in_defs = False
                continue

            if line.startswith("#") or line.startswith("$"):
                continue

            if line[0] in "01xXzZ":
                ident = line[1:]
                value = line[0].lower()
                if ident in values:
                    values[ident] = value
            elif line[0] in "bBrR":
                try:
                    value, ident = line[1:].split(None, 1)
                except ValueError:
                    continue
                if ident in values:
                    values[ident] = value.lower()
            else:
                continue

            clk_ids = [id_by_path.get(path) for path in candidates["clk"]]
            clk = "0"
            for clk_id in clk_ids:
                if clk_id and values.get(clk_id) is not None:
                    clk = values.get(clk_id) or "0"
                    break
            if prev_clk == "0" and clk == "1":
                sample: dict[str, int | None] = {}
                for name, paths in candidates.items():
                    if name in ("soc_clk", "soc_rst_n"):
                        continue
                    ident = next((id_by_path.get(path) for path in paths if id_by_path.get(path)), None)
                    sample[name] = bits_to_int(values.get(ident)) if ident else None
                samples.append(sample)
            prev_clk = clk or prev_clk

    return id_by_path, samples


def sign_extend(value: int, bits: int) -> int:
    sign = 1 << (bits - 1)
    return (value ^ sign) - sign


def reg_name(index: int) -> str:
    return f"x{index}"


def csr_name(csr: int) -> str:
    names = {
        0x300: "mstatus",
        0x304: "mie",
        0x305: "mtvec",
        0x341: "mepc",
        0x342: "mcause",
        0x343: "mtval",
        0x344: "mip",
        0xB00: "mcycle",
        0xB02: "minstret",
        0xC00: "cycle",
        0xC02: "instret",
    }
    return names.get(csr, f"0x{csr:03x}")


def decode_rv32i(instr: int) -> str:
    opcode = instr & 0x7f
    rd = (instr >> 7) & 0x1f
    funct3 = (instr >> 12) & 0x7
    rs1 = (instr >> 15) & 0x1f
    rs2 = (instr >> 20) & 0x1f
    funct7 = (instr >> 25) & 0x7f

    if instr == 0x00000013:
        return "nop"
    if opcode == 0x37:
        return f"lui {reg_name(rd)},0x{instr & 0xfffff000:08x}"
    if opcode == 0x17:
        return f"auipc {reg_name(rd)},0x{instr & 0xfffff000:08x}"
    if opcode == 0x6f:
        imm = ((instr >> 31) & 0x1) << 20
        imm |= ((instr >> 12) & 0xff) << 12
        imm |= ((instr >> 20) & 0x1) << 11
        imm |= ((instr >> 21) & 0x3ff) << 1
        imm = sign_extend(imm, 21)
        return f"jal {reg_name(rd)},{imm:+d}"
    if opcode == 0x67:
        imm = sign_extend(instr >> 20, 12)
        return f"jalr {reg_name(rd)},{imm:+d}({reg_name(rs1)})"
    if opcode == 0x63:
        names = {0x0: "beq", 0x1: "bne", 0x4: "blt", 0x5: "bge", 0x6: "bltu", 0x7: "bgeu"}
        imm = ((instr >> 31) & 0x1) << 12
        imm |= ((instr >> 7) & 0x1) << 11
        imm |= ((instr >> 25) & 0x3f) << 5
        imm |= ((instr >> 8) & 0xf) << 1
        imm = sign_extend(imm, 13)
        return f"{names.get(funct3, 'branch?')} {reg_name(rs1)},{reg_name(rs2)},{imm:+d}"
    if opcode == 0x03:
        names = {0x0: "lb", 0x1: "lh", 0x2: "lw", 0x4: "lbu", 0x5: "lhu"}
        imm = sign_extend(instr >> 20, 12)
        return f"{names.get(funct3, 'load?')} {reg_name(rd)},{imm:+d}({reg_name(rs1)})"
    if opcode == 0x23:
        names = {0x0: "sb", 0x1: "sh", 0x2: "sw"}
        imm = ((instr >> 25) << 5) | rd
        imm = sign_extend(imm, 12)
        return f"{names.get(funct3, 'store?')} {reg_name(rs2)},{imm:+d}({reg_name(rs1)})"
    if opcode == 0x13:
        imm = sign_extend(instr >> 20, 12)
        if funct3 == 0x0:
            return f"addi {reg_name(rd)},{reg_name(rs1)},{imm:+d}"
        if funct3 == 0x2:
            return f"slti {reg_name(rd)},{reg_name(rs1)},{imm:+d}"
        if funct3 == 0x3:
            return f"sltiu {reg_name(rd)},{reg_name(rs1)},{imm:+d}"
        if funct3 == 0x4:
            return f"xori {reg_name(rd)},{reg_name(rs1)},{imm:+d}"
        if funct3 == 0x6:
            return f"ori {reg_name(rd)},{reg_name(rs1)},{imm:+d}"
        if funct3 == 0x7:
            return f"andi {reg_name(rd)},{reg_name(rs1)},{imm:+d}"
        shamt = rs2
        if funct3 == 0x1 and funct7 == 0x00:
            return f"slli {reg_name(rd)},{reg_name(rs1)},{shamt}"
        if funct3 == 0x5 and funct7 == 0x00:
            return f"srli {reg_name(rd)},{reg_name(rs1)},{shamt}"
        if funct3 == 0x5 and funct7 == 0x20:
            return f"srai {reg_name(rd)},{reg_name(rs1)},{shamt}"
    if opcode == 0x33:
        names = {
            (0x0, 0x00): "add",
            (0x0, 0x20): "sub",
            (0x1, 0x00): "sll",
            (0x2, 0x00): "slt",
            (0x3, 0x00): "sltu",
            (0x4, 0x00): "xor",
            (0x5, 0x00): "srl",
            (0x5, 0x20): "sra",
            (0x6, 0x00): "or",
            (0x7, 0x00): "and",
        }
        name = names.get((funct3, funct7), "op?")
        return f"{name} {reg_name(rd)},{reg_name(rs1)},{reg_name(rs2)}"
    if opcode == 0x0f:
        if funct3 == 0x0:
            return "fence"
        if funct3 == 0x1:
            return "fence.i"
    if opcode == 0x73:
        if instr == 0x00000073:
            return "ecall"
        if instr == 0x00100073:
            return "ebreak"
        if instr == 0x30200073:
            return "mret"
        csr = (instr >> 20) & 0xfff
        names = {0x1: "csrrw", 0x2: "csrrs", 0x3: "csrrc", 0x5: "csrrwi", 0x6: "csrrsi", 0x7: "csrrci"}
        name = names.get(funct3, "system?")
        if funct3 in (0x5, 0x6, 0x7):
            return f"{name} {reg_name(rd)},{csr_name(csr)},{rs1}"
        return f"{name} {reg_name(rd)},{csr_name(csr)},{reg_name(rs1)}"
    return f"unknown 0x{instr:08x}"


def instruction_label(pc: int | None, instr: int | None) -> str:
    if pc is None:
        return "unknown"
    if instr is None:
        return f"0x{pc:08x}: --------"
    return f"0x{pc:08x}: 0x{instr:08x}  {decode_rv32i(instr)}"


def build_trace(samples: list[dict[str, int | None]]) -> tuple[list[Instruction], dict[int, dict[str, set[int]]]]:
    instructions: list[Instruction] = []
    stages_by_id: dict[int, dict[str, set[int]]] = {}
    prev_slots: dict[str, int | None] = {"IF": None, "ID": None, "EX": None, "MEM": None, "WB": None}
    prev_id_key: tuple[int | None, int | None] | None = None
    prev_ex_pc: int | None = None

    def new_instruction(pc: int | None, instr: int | None) -> int:
        ident = len(instructions)
        instructions.append(Instruction(ident, pc, instr, instruction_label(pc, instr)))
        stages_by_id[ident] = {}
        return ident

    def update_instruction(ident: int, pc: int | None, instr: int | None) -> None:
        insn = instructions[ident]
        if insn.pc is None and pc is not None:
            insn.pc = pc
        if insn.instr is None and instr is not None:
            insn.instr = instr
        insn.label = instruction_label(insn.pc, insn.instr)

    for cycle, sample in enumerate(samples):
        if sample.get("rst_n") != 1:
            prev_slots = {"IF": None, "ID": None, "EX": None, "MEM": None, "WB": None}
            prev_id_key = None
            prev_ex_pc = None
            continue

        cur_slots: dict[str, int | None] = {"IF": None, "ID": None, "EX": None, "MEM": None, "WB": None}

        if sample.get("if_id_valid") == 1:
            pc = sample.get("if_id_pc")
            instr = sample.get("if_id_instr")
            key = (pc, instr)
            if key == prev_id_key and prev_slots["ID"] is not None:
                ident = prev_slots["ID"]
            elif (
                prev_slots["IF"] is not None
                and (
                    instructions[prev_slots["IF"]].pc is None
                    or instructions[prev_slots["IF"]].pc == pc
                )
            ):
                ident = prev_slots["IF"]
            else:
                ident = new_instruction(pc, instr)
            update_instruction(ident, pc, instr)
            if "IF" not in stages_by_id[ident]:
                stages_by_id[ident]["IF"] = {max(0, cycle - 1)}
            cur_slots["ID"] = ident
            prev_id_key = key
        else:
            prev_id_key = None

        if sample.get("id_ex_valid") == 1:
            id_pc = sample.get("id_ex_pc")
            if id_pc == prev_ex_pc and prev_slots["EX"] is not None:
                cur_slots["EX"] = prev_slots["EX"]
            elif prev_slots["ID"] is not None:
                cur_slots["EX"] = prev_slots["ID"]
            else:
                cur_slots["EX"] = new_instruction(id_pc, None)
            prev_ex_pc = id_pc
        else:
            prev_ex_pc = None

        if sample.get("ex_mem_valid") == 1:
            cur_slots["MEM"] = prev_slots["MEM"] if prev_slots["EX"] is None else prev_slots["EX"]
            if cur_slots["MEM"] is None:
                cur_slots["MEM"] = new_instruction(None, None)

        if sample.get("mem_wb_valid") == 1:
            cur_slots["WB"] = prev_slots["WB"] if prev_slots["MEM"] is None else prev_slots["MEM"]
            if cur_slots["WB"] is None:
                cur_slots["WB"] = new_instruction(None, None)

        for stage, ident in cur_slots.items():
            if ident is not None:
                stages_by_id[ident].setdefault(stage, set()).add(cycle)

        prev_slots = cur_slots

    return instructions, stages_by_id


def intervals(cycles: set[int]) -> list[tuple[int, int]]:
    if not cycles:
        return []
    result: list[tuple[int, int]] = []
    start = prev = min(cycles)
    for cycle in sorted(cycles):
        if cycle == start:
            continue
        if cycle == prev + 1:
            prev = cycle
            continue
        result.append((start, prev + 1))
        start = prev = cycle
    result.append((start, prev + 1))
    return result


def write_kanata(
    out_path: Path,
    instructions: list[Instruction],
    stages_by_id: dict[int, dict[str, set[int]]],
) -> None:
    events: dict[int, list[str]] = {}

    def display_cycle(cycle: int) -> int:
        return max(0, cycle - 1)

    def add(cycle: int, line: str) -> None:
        events.setdefault(cycle, []).append(line)

    def first_stage_cycle(insn: Instruction) -> int:
        stage_cycles = [
            min(cycles)
            for cycles in stages_by_id.get(insn.ident, {}).values()
            if cycles
        ]
        return min(stage_cycles) if stage_cycles else 0

    ordered_instructions = sorted(
        instructions,
        key=lambda insn: (
            first_stage_cycle(insn),
            insn.pc if insn.pc is not None else 0xFFFF_FFFF,
            insn.ident,
        ),
    )
    output_id_by_ident = {insn.ident: output_id for output_id, insn in enumerate(ordered_instructions)}

    for insn in ordered_instructions:
        output_id = output_id_by_ident[insn.ident]
        add(0, f"I\t{output_id}\t{output_id}\t0")
        add(0, f"L\t{output_id}\t0\t{insn.label}")
        last_end = 0
        for stage in ("IF", "ID", "EX", "MEM", "WB"):
            for start, end in intervals(stages_by_id.get(insn.ident, {}).get(stage, set())):
                add(display_cycle(start), f"S\t{output_id}\t0\t{stage}")
                add(display_cycle(end), f"E\t{output_id}\t0\t{stage}")
                last_end = max(last_end, end)
        if last_end:
            add(display_cycle(last_end), f"R\t{output_id}\t0\t0")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="ascii") as f:
        f.write("Kanata\t0004\n")
        for cycle in sorted(events):
            f.write(f"C=\t{cycle}\n")
            for line in events[cycle]:
                f.write(line + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("wave", type=Path, help="Input .fst or .vcd waveform.")
    parser.add_argument("-o", "--output", type=Path, help="Output .kanata path.")
    args = parser.parse_args()

    if not args.wave.exists():
        print(f"Waveform not found: {args.wave}", file=sys.stderr)
        return 2

    output = args.output or args.wave.with_suffix(".kanata")
    _ids, samples = read_vcd(args.wave)
    instructions, stages_by_id = build_trace(samples)
    write_kanata(output, instructions, stages_by_id)
    print(f"Wrote {output} ({len(instructions)} instructions, {len(samples)} sampled clock edges)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
