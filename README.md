# eRISCV MCU Family

eRISCV-MCU is a self-contained RV32 RISC-V MCU family with three implemented
products: M0, M1, and M2.  The repository contains synthesizable RTL, software,
verification collateral, FPGA inputs, and evidence.  It is engineering source,
not a commercial availability, certification, or electrical-specification
claim.

## Start here

- [Family documentation map](docs/README.md) — contracts, evidence, and history.
- [Architecture claim](docs/eriscv-mcu-architecture-claim.md) — frozen product
  profiles and deliberate exclusions.
- [HTML product manual](docs/product-manual/index.html) — reader-facing family
  guide and preliminary datasheets.
- [Verification evidence snapshot](docs/Verification/eriscv-mcu-simulation-evidence-snapshot.md)
  — sole owner of current regression totals and status.
- [Changelog](CHANGELOG.md) — public release history and known limitations.
- [Contributing](CONTRIBUTING.md) and [security reporting](SECURITY.md) —
  contribution and private-disclosure expectations.

## Product line

| Product | Frozen ISA profile | Role |
| --- | --- | --- |
| [eRISCV-M0](eriscv-m0/README.md) | `RV32IC_Zicsr_Zifencei_Zicntr_Zihpm_Zihintpause` | Compact M-mode control MCU |
| [eRISCV-M1](eriscv-m1/README.md) | `RV32IMC_Zicsr_Zifencei_Zicntr_Zihpm_Zihintpause` | Mainstream M/U-mode MCU with PMP |
| [eRISCV-M2](eriscv-m2/README.md) | `RV32IMFC_Zicsr_Zifencei_Zicntr_Zihpm_Zihintpause_Zba_Zcf` | Performance MCU with FPU, TCM, System SRAM, and DMA |

## Quick start

The default regression backend is Verilator. On Debian/Ubuntu, install the
first-checkout prerequisites before running the commands below:

```bash
sudo apt-get update
sudo apt-get install -y git build-essential python3 verilator
verilator --version
```

`build-essential` provides the host C++ compiler used by Verilator-generated
simulation binaries. ModelSim/Questa targets remain optional for focused
waveform inspection and require a separately licensed installation discoverable
through `VSIM` or `PATH`.

```bash
git clone https://github.com/zhanxn87/eriscv-mcu.git
cd eriscv-mcu
make help                         # list supported repository commands and their scope
make lint-all                     # screen synthesizable M0/M1/M2 RTL with Verilator
make eriscv-m0-smoke-no-act       # run the M0 directed/SoC smoke baseline without ACT4
```

The benchmark and RTOS submodules are optional for RTL lint and standard
core/SoC regression.  Initialize only a dependency needed by a selected
software workflow, for example `git submodule update --init
third_party/FreeRTOS-Kernel`; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

### Generate ACT4 artifacts (optional)

ACT4 runtime collateral is an ignored local cache. It generates self-checking
ELFs with the RISC-V Sail reference model, then imports the testbench images
and manifests. It requires the pinned generator, Sail, a RISC-V GCC toolchain,
and the Ruby/uv tools selected by upstream `riscv-arch-test`.

Initialize the generator once for either setup path:

```bash
git submodule update --init third_party/riscv-arch-test
```

#### Default: native Debian/Ubuntu setup

The native bootstrap uses
`sudo` only to install build packages, installs mise and Sail below
`.cache/act4`, and builds the pinned RISC-V GCC toolchain there. The compiler
build is CPU-, disk-, and time-intensive. This path currently supports
Debian/Ubuntu Linux on x86_64 hosts.

```bash
make ACT_BOOTSTRAP_ARGS=--all act-bootstrap-native
tools/compliance/riscv-arch-test/check_act4_standard_env.sh
make act-generate-m1
```

For a pre-provisioned native host, install only the missing components with
`ACT_BOOTSTRAP_ARGS=--mise`, `--sail`, or `--toolchain`; run
`make act-bootstrap-native` with that argument. The bootstrap currently
supports Debian/Ubuntu. Generate all product caches with
`make act-generate-all`. Other hosts should install the equivalent tools
according to the pinned upstream
[`riscv-arch-test` instructions](https://github.com/riscv/riscv-arch-test).

The M1/M2 default cache includes their U-mode ACT profile; PMPSm remains an
explicit product-local flow. After native setup, use `make act-generate-m0`,
`make act-generate-m1`, or `make act-generate-m2` for native regeneration.

#### Docker fallback: isolated environment

Use Docker Engine or Docker Desktop when a compatible native environment is
unavailable or when a reproducible isolated toolchain is preferred. The first
run builds a cached Linux image, including the pinned RISC-V GCC toolchain, so
it is intentionally slow and larger than the native setup. Generated files and
ACT caches remain in the repository; the container itself is disposable.

```bash
make act-generate-m1-container
```

Use `make act-generate-m0-container`, `make act-generate-m1-container`, or
`make act-generate-m2-container` for one product, or
`make act-generate-all-container` for all three product caches. The image is
built once and shared by every container target.

`make eriscv-m0-full`, `make eriscv-m1-full`, and `make eriscv-m2-full` run
the complete generated ACT corpus in addition to directed core and SoC
regression when their ACT4 cache is present. If the ignored cache is absent,
they emit a prominent warning and run directed/compliance-full core plus the
full SoC regression without ACT instead; that fallback is not ACT evidence.
Use the matching native or Docker generation target above before claiming ACT
coverage. Explicit
`make eriscv-m0-act`, `make eriscv-m1-act`, and `make eriscv-m2-act` targets
remain strict and fail if their cache is absent.

The standard `make eriscv-m0-core` (and M1/M2 equivalent) similarly skips its
ACT smoke subset with a prominent warning when that subset is unavailable,
while retaining directed and compliance-smoke coverage.

## Repository boundaries

Each product directory owns its core/SoC RTL, DV, ACT4 selection, software,
FPGA inputs, product documentation, and evidence.  Product RTL must not import
RTL from another product directory.  Common APB peripheral IP lives in
[`peripherals/`](peripherals/).  M2's FPU vendor snapshot remains in-tree so
that M2 stays self-contained.

The companion educational repository, [eRISCV Lab](https://github.com/zhanxn87/eriscv-lab),
teaches the RV32I five-stage pipeline and its teaching SoC.  It is design
heritage only: neither repository sources, compiles, or requires the other.

## Common commands

```bash
make help
make lint-m0
make lint-m1
make lint-m2
make eriscv-m0-full
make eriscv-m1-full
make eriscv-m2-full
make eriscv-mcu-full
```

See the [verification guide](docs/product-manual/verification.html) for scope,
focused targets, and evidence boundaries.  Third-party terms are described in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md); the top-level BSD-3-Clause
license applies only to original eRISCV content.
