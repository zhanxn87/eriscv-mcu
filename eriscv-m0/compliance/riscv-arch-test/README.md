# eRISCV-M0 ACT4 Profile

This is the sole architectural-test flow for eRISCV-M0 MCU verification. The
profile selects `I`, `Zca`, `Zicsr`, `Zifencei`, `Zicntr`, `Zihpm`, and `Zihintpause`. A fresh reference build of the pinned ACT4 sources imports 77 artifacts. UDB represents the RV32C base through `Zca`.

ACT4 artifacts are local, reproducible cache under:

```text
eriscv-m0/compliance/riscv-arch-test/generated/
```

The cache contains instruction `.mem`, optional `.data.mem`, and `.act.json`
manifests. It is ignored by Git. The pinned `riscv-arch-test` submodule remains
the source of the ACT assembly.

ACT4 build work is kept in `work/`; shared tool caches are kept in `.cache/act4/`. Both locations are ignored by Git. The Sail reference configuration maps a 256 KiB executable test-harness window so generated ACT code and its startup shim fit; this is not the product's fixed 64 KiB IMEM contract.

Rebuild the cache when needed:

```bash
make act-generate-m0
```

Set up the required ACT4 tools first using the repository-level
[ACT4 instructions](../../../README.md#generate-act4-artifacts-optional).
Native hosts use `make ACT_BOOTSTRAP_ARGS=--all act-bootstrap-native` once,
then this target. `make act-generate-m0-container` is the Docker fallback.
