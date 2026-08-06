# eRISCV MCU GitHub Actions CI

The repository workflow is a reproducibility wrapper around the maintained
top-level `make` targets. The workflow source is
[`.github/workflows/ci.yml](../../.github/workflows/ci.yml); this document
defines its intended coverage and evidence boundary without duplicating the
YAML.

## Triggers and coverage

| Trigger | Jobs | Scope |
| --- | --- | --- |
| Push | `static-rtl-checks`, `pr-verilator-full` | Static checks plus, per product, full core/SoC regression without generated ACT4 followed by committed ACT smoke. |
| Pull request | `static-rtl-checks`, `pr-verilator-full` | Same static checks and per-product full core/SoC regression without generated ACT4 followed by committed ACT smoke. |
| Daily schedule, 02:17 UTC | `nightly-change-gate` then nightly jobs | Runs only when the repository has a commit in the previous 24 hours. |
| Manual dispatch | `nightly-change-gate` then nightly jobs | Always runs the nightly jobs; it bypasses the daily change-window test. |

The pull-request path intentionally does not build a new ACT4 environment.
It uses the committed `ci-smoke` vectors. Full ACT4 generation is reserved for
the nightly path.

## Nightly jobs

| Job | Coverage | Result surface | Failure diagnostic |
| --- | --- | --- | --- |
| Full ACT4 regression | M0, M1, M2; `make eriscv-<product>-full` | Job Summary | `nightly-full-<product>` |
| Generic-Liberty PPA | M0, M1, M2 in one job; `source tools/ppa/env.sh && make ppa-all` | Job Summary and performance history | `nightly-ppa-generic-liberty` |
| Software benchmarks | M0, M1, M2 sequentially; CoreMark, Dhrystone, and Embench `matmult-int` smoke | Job Summary and performance history | `nightly-benchmark-diagnostics` |
| Performance-history publisher | Runs after successful PPA and benchmarks | GitHub Pages `gh-pages` branch | None; it does not publish a partial record |

Every job writes a compact result to its GitHub Actions Job Summary. Raw logs
are uploaded only when that job fails, with seven-day retention: static and
regression logs under `build/ci` and product `regression_logs/`; PPA
`summary.json`, generated SDC, synthesis, and OpenSTA logs under `build/ppa`;
and benchmark logs plus generated software outputs under
`build/nightly-benchmarks` and the product software build directories.

The benchmark job runs the three products sequentially so it can publish one
complete metrics record without using a successful-run artifact as an internal
transport. It attempts all nine bounded benchmark commands before returning a
failure status.

## Performance history

When the change gate permits a nightly run and both PPA and benchmark jobs
succeed, `nightly-performance-history` appends the run's generic-Liberty Cell
Area, pre-layout Fmax, synchronous-path WNS, CoreMark/MHz, DMIPS/MHz, and
Embench cycle results to `gh-pages/data/history.json`. It regenerates a small
static dashboard at `gh-pages/index.html`; repeated runs of the same workflow
run URL replace rather than duplicate a record, and the dashboard retains the
latest 180 records.

The first successful publisher job creates the `gh-pages` branch. Enable it
once in repository **Settings → Pages** by selecting **Deploy from a branch**,
branch `gh-pages`, folder `/(root)`. The dashboard URL is
`https://<owner>.github.io/<repository>/`. It is intentionally not updated for
an unchanged scheduled day, a failed PPA/benchmark run, or a partial result.

## Caches

- ACT4 caches include the native tool environment and product-generated
  artifacts. Keys include the upstream ACT4 revision and product profiles.
- PPA caches include the local Yosys/OpenSTA environment and generic Liberty.
  They do not contain a PDK, OpenLane, placement, routing, or signoff data.
- A cache hit avoids rebuilding tools; it does not replace the corresponding
  regression or PPA run.

## Reproduce locally

```bash
# Same static checks used on push and pull requests.
make check

# Same PR regression shape for one product.
make eriscv-m0-full-no-act
make eriscv-m0-act-smoke

# Same nightly generic-Liberty PPA job after local setup.
make ppa-setup
source tools/ppa/env.sh
make ppa-all
```

Replace `m0` with `m1` or `m2` where applicable. Benchmark commands are
listed by `make help`; the nightly workflow fixes the Embench case to
`matmult-int`, `speed`, scale 1 for a bounded CI runtime.

## Evidence boundary

- Verilator is the CI simulator. ModelSim remains a local focused-debug and
  waveform backend.
- Job Summaries provide per-run results; failure artifacts provide raw
  diagnostics. The performance-history page is a trend view, not a signoff
  record. Current dated regression totals are owned by the [MCU Evidence
  Snapshot](eriscv-mcu-simulation-evidence-snapshot.md).
- PPA reports are logic-only pre-layout estimates using generic Liberty; SRAM
  macro area/timing, LEF/DEF, RC extraction, IO placement, and signoff are out
  of scope. The generic SDC verifies root, JTAG, core, and peripheral generated
  clocks, treats UART and external PLIC inputs as asynchronous, and reports
  reset recovery/removal separately. It does not insert CTS or reset/data
  fanout buffers, so its Fmax is a trend estimate rather than a physical target.
  The PPA constraints and report format are documented in
  [`tools/ppa/constraints.sdc`](../../tools/ppa/constraints.sdc) and the
  [PPA section of `make help`](../../Makefile).
- A green workflow is CI evidence, not a certification, ASIC timing closure,
  board-validation result, or guaranteed product-performance specification.

When the workflow or its Make targets change, update this document in the same
change. Do not copy dynamic pass counts, benchmark values, or PPA numbers into
this CI description.
