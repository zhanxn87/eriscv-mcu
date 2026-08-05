#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Convert one ACT4 ELF into eRISCV testbench memory artifacts."""

from __future__ import annotations

import argparse
import json
import shutil
import re
import struct
import subprocess
from pathlib import Path

TOHOST_RE = re.compile(r"^\s*([0-9a-fA-F]+)\s+[a-zA-Z]\s+tohost$")
BEGIN_SIGNATURE_RE = re.compile(r"^\s*([0-9a-fA-F]+)\s+[a-zA-Z]\s+begin_signature$")
MTRAMPTBL_RE = re.compile(r"^\s*([0-9a-fA-F]+)\s+[a-zA-Z]\s+Mtramptbl_sv$")
PT_LOAD = 1
PF_X = 1
PF_W = 2


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("elf", type=Path, help="ACT4 self-checking ELF to import.")
    parser.add_argument("out_dir", type=Path, help="Output directory for generated .mem files.")
    parser.add_argument("--name", help="Override testcase stem. Defaults to ELF stem without .sig.")
    parser.add_argument("--nm", default="riscv64-unknown-elf-nm", help="nm executable.")
    parser.add_argument("--addr-width", type=int, default=13, help="Word-address fold width used by tb memories.")
    parser.add_argument("--max-cycles", type=int, help="Optional per-test simulation cycle limit.")
    parser.add_argument("--exec-data-mirror", action="store_true", help="Mirror writable payload data into core TB IMEM.")
    parser.add_argument("--source", type=Path, help="Original ACT assembly source to preserve beside the artifact.")
    parser.add_argument(
        "--runtime-only",
        action="store_true",
        help="Emit only self-contained simulation collateral and its manifest fields.",
    )
    parser.add_argument("--objdump", default="riscv64-unknown-elf-objdump", help="objdump executable.")
    return parser.parse_args()


def folded_word_index(byte_addr: int, addr_width: int) -> int:
    return (byte_addr >> 2) & ((1 << addr_width) - 1)


def load_elf32(elf: Path) -> tuple[bytes, int, int, int]:
    data = elf.read_bytes()
    if data[:4] != b"\x7fELF" or data[4] != 1 or data[5] != 1:
        raise ValueError(f"{elf} is not a little-endian ELF32 file")
    e_phoff = struct.unpack_from("<I", data, 28)[0]
    e_phentsize = struct.unpack_from("<H", data, 42)[0]
    e_phnum = struct.unpack_from("<H", data, 44)[0]
    return data, e_phoff, e_phentsize, e_phnum


def collect_segment_words(elf: Path, addr_width: int, writable: bool) -> dict[int, int]:
    data, e_phoff, e_phentsize, e_phnum = load_elf32(elf)
    words: dict[int, int] = {}
    for idx in range(e_phnum):
        off = e_phoff + idx * e_phentsize
        p_type, p_offset, p_vaddr, _p_paddr, p_filesz, _p_memsz, p_flags, _p_align = (
            struct.unpack_from("<IIIIIIII", data, off)
        )
        if p_type != PT_LOAD:
            continue
        if writable:
            if not (p_flags & PF_W):
                continue
        else:
            if not (p_flags & PF_X):
                continue
        segment = data[p_offset : p_offset + p_filesz]
        for byte_off in range(0, len(segment), 4):
            chunk = segment[byte_off : byte_off + 4]
            if len(chunk) < 4:
                chunk = chunk + bytes(4 - len(chunk))
            mem_index = folded_word_index(p_vaddr + byte_off, addr_width)
            words[mem_index] = int.from_bytes(chunk, "little")
    return words


def write_mem(words: dict[int, int], out_path: Path) -> bool:
    if not words:
        return False
    previous_index: int | None = None
    with out_path.open("w", encoding="ascii", newline="\n") as f:
        for mem_index in sorted(words):
            if previous_index is None or mem_index != previous_index + 1:
                f.write(f"@{mem_index:x}\n")
            f.write(f"{words[mem_index]:08x}\n")
            previous_index = mem_index
    return True


def extract_symbol_addrs(elf: Path, nm: str) -> dict[str, int]:
    result = subprocess.run(
        [nm, "-n", str(elf)],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    symbols: dict[str, int] = {}
    for line in result.stdout.splitlines():
        match = TOHOST_RE.match(line)
        if match:
            symbols["tohost"] = int(match.group(1), 16)
            continue
        match = BEGIN_SIGNATURE_RE.match(line)
        if match:
            symbols["begin_signature"] = int(match.group(1), 16)
            continue
        match = MTRAMPTBL_RE.match(line)
        if match:
            symbols["Mtramptbl_sv"] = int(match.group(1), 16)
    return symbols


def main() -> int:
    args = parse_args()
    elf = args.elf.resolve()
    if not elf.exists():
        raise FileNotFoundError(elf)
    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    stem = args.name or elf.stem.removesuffix(".sig")
    instr_mem = out_dir / f"{stem}.mem"
    data_mem = out_dir / f"{stem}.data.mem"
    metadata = out_dir / f"{stem}.act.json"
    source_copy = out_dir / f"{stem}.S"
    objdump = out_dir / f"{stem}.elf.objdump"
    nm_dump = out_dir / f"{stem}.elf.nm"

    if args.source is not None and not args.runtime_only:
        source = args.source.resolve()
        if not source.is_file():
            raise FileNotFoundError(source)
        shutil.copy2(source, source_copy)

    instr_words = collect_segment_words(elf, args.addr_width, writable=False)
    data_words = collect_segment_words(elf, args.addr_width, writable=True)
    write_mem(instr_words, instr_mem)

    symbols = extract_symbol_addrs(elf, args.nm)
    tohost_index = folded_word_index(symbols.get("tohost", 0x40000), args.addr_width)
    data_words[tohost_index] = 0
    data_words[tohost_index + 1] = 0

    # The educational ACT target uses the trap-table save area as mscratch.
    # For gp=0 termination ECALLs, ACT later reads the first save-area slot as
    # a no-trap-signature offset sentinel, so keep it cleared in the imported
    # collateral instead of the upstream prototype jump word.
    mtramptbl_addr = symbols.get("Mtramptbl_sv")
    if mtramptbl_addr is not None:
        data_words[folded_word_index(mtramptbl_addr, args.addr_width)] = 0

    has_data_mem = write_mem(data_words, data_mem)
    if not has_data_mem and data_mem.exists():
        data_mem.unlink()
    manifest = {
        "instr_mem_file": instr_mem.name,
        "data_mem_file": data_mem.name if has_data_mem else None,
        "boot_addr": 0x80,
        "tohost_addr": tohost_index,
        "tohost_pass_value": 1,
        "tohost_fail_value": 3,
        "sig_base": folded_word_index(symbols.get("begin_signature", 0x40200), args.addr_width),
    }
    if not args.runtime_only:
        try:
            elf_display_path = elf.relative_to(Path.cwd()).as_posix()
        except ValueError:
            elf_display_path = elf.name
        objdump_output = subprocess.run(
            [args.objdump, "-d", str(elf)], check=True, text=True, stdout=subprocess.PIPE
        ).stdout
        objdump.write_text(
            objdump_output.replace(f"{elf.as_posix()}:", f"{elf_display_path}:", 1),
            encoding="utf-8",
        )
        nm_dump.write_text(subprocess.run(
            [args.nm, "-n", str(elf)], check=True, text=True, stdout=subprocess.PIPE
        ).stdout, encoding="utf-8")
        manifest.update(
            {
                "source": source_copy.name if args.source is not None else None,
                "elf_objdump": objdump.name,
                "elf_nm": nm_dump.name,
            }
        )
    if args.max_cycles is not None:
        manifest["max_cycles"] = args.max_cycles
    if args.exec_data_mirror:
        manifest["exec_data_mirror"] = True
    metadata.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
