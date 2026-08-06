#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Build and import a product-local ACT4 artifact corpus from a JSON profile."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("profile", type=Path, help="Product-local ACT4 JSON profile.")
    parser.add_argument("--jobs", type=int, help="Override the profile ACT4 job count.")
    parser.add_argument("--import-only", action="store_true", help="Import ELF files already present in the profile workdir.")
    parser.add_argument("--dry-run", action="store_true", help="Print the planned build and import locations only.")
    return parser.parse_args()


def load_profile(path: Path) -> dict[str, object]:
    with path.open(encoding="utf-8") as profile_file:
        profile = json.load(profile_file)
    required = (
        "name",
        "config_file",
        "workdir",
        "extensions",
        "exclude_extensions",
        "output_dir",
        "addr_width",
        "jobs",
    )
    missing = [field for field in required if field not in profile]
    if missing:
        raise ValueError(f"profile missing required field(s): {', '.join(missing)}")
    return profile


def resolve_repo_path(root: Path, path_value: object) -> Path:
    if not isinstance(path_value, str):
        raise ValueError("profile path fields must be strings")
    path = Path(path_value)
    if path.is_absolute():
        raise ValueError(f"profile paths must be repository-relative: {path}")
    return root / path


def materialize_config(root: Path, config_path: Path, temp_dir: Path) -> Path:
    config_dir = config_path.parent
    resolved_lines: list[str] = []
    for line in config_path.read_text(encoding="utf-8").splitlines():
        key, separator, value = line.partition(":")
        if separator and key in {"udb_config", "linker_script", "dut_include_dir"}:
            raw_value = value.strip()
            if raw_value and not raw_value.startswith("$"):
                candidate = Path(raw_value)
                if not candidate.is_absolute():
                    value = f" {config_dir / candidate}"
                    line = f"{key}:{value}"
        resolved_lines.append(line.replace("$repo_root", str(root)))
    resolved = temp_dir / config_path.name
    resolved.write_text("\n".join(resolved_lines) + "\n", encoding="utf-8")
    return resolved


def materialize_test_dir(act_root: Path, profile: dict[str, object], temp_dir: Path) -> Path:
    excluded = profile.get("exclude_test_sources", [])
    if not excluded:
        return act_root / "tests"
    if not isinstance(excluded, list) or not all(isinstance(item, str) for item in excluded):
        raise ValueError("exclude_test_sources must be a list of ACT test-source paths")

    source_root = act_root / "tests"
    excluded_paths = {Path(item) for item in excluded}
    for excluded_path in excluded_paths:
        if not (source_root / excluded_path).is_file():
            raise FileNotFoundError(f"ACT test source not found: {excluded_path}")

    test_dir = temp_dir / "tests"
    test_dir.mkdir()
    (test_dir / "env").symlink_to(source_root / "env", target_is_directory=True)
    extensions = str(profile["extensions"]).split(",")
    for extension in extensions:
        for source in source_root.rglob(f"*/{extension.strip()}/*.S"):
            relative = source.relative_to(source_root)
            if relative in excluded_paths:
                continue
            destination = test_dir / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
    return test_dir


def build_elfs(root: Path, profile: dict[str, object], jobs: int) -> None:
    env_script = root / "tools" / "compliance" / "riscv-arch-test" / "act4-standard-env.sh"
    act_root = root / "third_party" / "riscv-arch-test"
    config_path = resolve_repo_path(root, profile["config_file"])
    workdir = resolve_repo_path(root, profile["workdir"])
    workdir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="config-", dir=workdir) as temp_name:
        temp_dir = Path(temp_name)
        resolved_config = materialize_config(root, config_path, temp_dir)
        test_dir = materialize_test_dir(act_root, profile, temp_dir)
        command = [
            "bash",
            "-c",
            'source "$1" && shift && exec "$@"',
            "bash",
            str(env_script),
            "make",
            "-C",
            str(act_root),
            f"CONFIG_FILES={resolved_config}",
            f"WORKDIR={resolve_repo_path(root, profile['workdir'])}",
            f"TESTDIR={test_dir}",
            f"EXTENSIONS={profile['extensions']}",
            f"EXCLUDE_EXTENSIONS={profile['exclude_extensions']}",
            f"JOBS={jobs}",
            "elfs",
        ]
        process = subprocess.Popen(command, cwd=root)
        start_time = time.monotonic()
        while process.poll() is None:
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                elapsed = int(time.monotonic() - start_time)
                print(f"ACT4 build active ({elapsed}s)", flush=True)
        if process.returncode:
            raise subprocess.CalledProcessError(process.returncode, command)


def selected_elfs(workdir: Path, excluded_sources: set[Path] | None = None) -> list[Path]:
    if not workdir.is_dir():
        raise NotADirectoryError(f"ACT4 workdir not found: {workdir}")
    # ACT4 keeps intermediate <test>.sig.elf files below build/. Only the
    # final self-checking artifacts below elfs/ are DUT test inputs.
    elfs = sorted(path for path in workdir.glob("*/elfs/**/*.elf") if path.is_file())
    if not elfs:
        raise FileNotFoundError(f"no final ACT4 ELF files found below {workdir}")
    if not excluded_sources:
        return elfs

    selected: list[Path] = []
    for elf in elfs:
        relative = elf.relative_to(workdir)
        try:
            elfs_index = relative.parts.index("elfs")
        except ValueError:
            selected.append(elf)
            continue
        source = Path(*relative.parts[elfs_index + 1 :]).with_suffix(".S")
        if source not in excluded_sources:
            selected.append(elf)
    if not selected:
        raise FileNotFoundError(f"all ACT4 ELF files below {workdir} were excluded")
    return selected


def original_source(root: Path, elf: Path) -> Path:
    stem = elf.stem.removesuffix(".sig")
    source_root = root / "third_party" / "riscv-arch-test" / "tests"
    rv32i_candidates = sorted(source_root.glob(f"rv32i/**/{stem}.S"))
    pmp32_candidates = sorted(source_root.glob(f"priv/pmp/pmp32/**/{stem}.S"))
    candidates = rv32i_candidates or pmp32_candidates or sorted(source_root.rglob(f"{stem}.S"))
    if len(candidates) != 1:
        raise ValueError(f"cannot uniquely map {elf.name} to ACT source: {candidates}")
    return candidates[0]


def import_elfs(root: Path, profile: dict[str, object], elfs: list[Path]) -> None:
    importer = root / "tools" / "compliance" / "riscv-arch-test" / "import_act4_artifact.py"
    out_dir = resolve_repo_path(root, profile["output_dir"])
    workdir = resolve_repo_path(root, profile["workdir"])
    out_dir.mkdir(parents=True, exist_ok=True)
    names: set[str] = set()
    imported: list[dict[str, str]] = []
    total = len(elfs)
    for index, elf in enumerate(elfs, start=1):
        if index == 1 or index % 10 == 0 or index == total:
            print(f"Importing ACT4 artifacts ({index}/{total})", flush=True)
        name = elf.stem.removesuffix(".sig")
        source = original_source(root, elf)
        if name in names:
            raise ValueError(f"duplicate ACT testcase stem: {name}")
        names.add(name)
        command = [
            sys.executable,
            str(importer),
            str(elf),
            str(out_dir),
            "--name",
            name,
            "--source",
            str(source),
            "--addr-width",
            str(profile["addr_width"]),
        ]
        if profile.get("runtime_only", False):
            command.append("--runtime-only")
        max_cycles_by_test = profile.get("max_cycles_by_test", {})
        if isinstance(max_cycles_by_test, dict) and name in max_cycles_by_test:
            command.extend(["--max-cycles", str(max_cycles_by_test[name])])
        exec_data_mirror_tests = profile.get("exec_data_mirror_tests", [])
        if isinstance(exec_data_mirror_tests, list) and name in exec_data_mirror_tests:
            command.append("--exec-data-mirror")
        result = subprocess.run(
            command,
            cwd=root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        if result.returncode != 0:
            print(result.stdout, end="")
            raise subprocess.CalledProcessError(result.returncode, command)
        imported.append(
            {
                "name": name,
                "source": source.relative_to(root).as_posix(),
                "source_elf": elf.relative_to(workdir).as_posix(),
            }
        )
    (out_dir / "act4-import-manifest.json").write_text(
        json.dumps({"profile": profile["name"], "tests": imported}, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Imported {len(imported)} ACT4 artifact(s) into {out_dir}")


def main() -> int:
    args = parse_args()
    root = repo_root()
    profile_path = args.profile.resolve()
    profile = load_profile(profile_path)
    workdir = resolve_repo_path(root, profile["workdir"])
    out_dir = resolve_repo_path(root, profile["output_dir"])
    jobs = args.jobs if args.jobs is not None else int(profile["jobs"])
    print(f"Profile: {profile['name']}")
    print(f"ACT4 workdir: {workdir}")
    print(f"Product cache: {out_dir}")
    if args.dry_run:
        print(f"Extensions: {profile['extensions']}")
        print(f"Exclude extensions: {profile['exclude_extensions']}")
        print(f"Jobs: {jobs}")
        return 0
    if not args.import_only:
        build_elfs(root, profile, jobs)
    excluded_sources = profile.get("exclude_test_sources", [])
    if not isinstance(excluded_sources, list) or not all(
        isinstance(item, str) for item in excluded_sources
    ):
        raise ValueError("exclude_test_sources must be a list of ACT test-source paths")
    import_elfs(root, profile, selected_elfs(workdir, {Path(item) for item in excluded_sources}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
