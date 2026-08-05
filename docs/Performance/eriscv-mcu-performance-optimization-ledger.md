# eRISCV MCU Performance Optimization Ledger

Cross-product index of implemented performance work. The product manual owns
current benchmark snapshots. A measured effect is a controlled same-image A/B
only. Other figures are diagnostic or product snapshots and are labelled
accordingly.

## Public-repository provenance

This ledger retains measurements collected during development before eRISCV-MCU
was split from its engineering monorepo. The predecessor commit identifiers are
intentionally omitted: they are not reachable from this public repository and
therefore cannot reproduce a result here. The first public release tag, and
later eRISCV-MCU commit/tag pairs, are the reproducibility anchors for new
measurements. Each new entry must record its public revision, clean worktree,
command, toolchain, image identity, and report path.

| ID | Product | Change | Measured effect | Proof / remaining evidence |
| --- | --- | --- | --- | --- |
| P-01 | M0; M1/M2 inherit | RV32C cross-word fetch buffering | M0 Dhrystone `1,062,037 → 1,013,020` cycles; DMIPS/MHz `0.535906 → 0.561837` | `MCU-C-IFETCH-CROSSWORD-01`: 35 → 8 cycles and precise trap recovery. |
| P-02 | M0/M1/M2 | Native JAL ID redirect | No whole-program A/B | `MCU-JAL-ID-01`; EX suppresses duplicate redirect. Same-image JAL microbenchmark remains open. |
| P-03 | M0/M1 | Accepted DTCM/CLINT/PLIC-store completion | M0 temporary A/B: -79,005 cycles (-8.01%); 73,676 DTCM stores fast-complete | `MCU-STORE-FAST-01`; M1 PMP/PLIC/SBA evidence. Pinned same-image A/B and paired PPA remain open if retained. |
| P-04 | M0/M1/M2 | ID BTFNT; direct JAL/C.J/C.JAL redirect | M0 A/B: `932,086 → 872,475` cycles (-6.40%) | Product control tests. A matched M0 pre/post-route PPA comparison remains open. |
| P-05 | M1/M2 | Hardware RV32M | M1/M0 microbench ratio: MUL 4.80×, DIV 6.27×; CoreMark comparison is workload-only | Integer regression and CoreMark CRC. |
| P-06 | M1 | Registered PMP/control verdict | No cycle A/B | PMP overlap/reset/sweep/SoC evidence; timing closure is an unpaired product snapshot. |
| P-07 | M2 | Registered RV32F CVFPU boundary | No standalone throughput claim | RV32F directed/ACT; bit-exact FFT smoke and stress. Workload-specific FP throughput remains open. |
| P-08 | M2 | Eight-bank System SRAM and generic DMA | No benchmark A/B | Bank-contention, descriptor, error, and UART-TX endpoint tests. DMA/System-SRAM throughput remains open. |
| P-09 | M0/M1 | `.rodata/.srodata` runtime placement in DTCM | M0 A/B: `850,016 → 819,016` cycles; `0.669578 → 0.694922` DMIPS/MHz | M0 evidence; M1 bare/FreeRTOS rebuild. |
| P-10 | M0/M1 | UART FIFO submission fast paths | Not measured; wire baud remains the limit | UART hello and async smoke. |
| P-11 | M1 | EX-stage DTCM load launch | Same-image total `897,550 → 781,156` (-12.97%); profile DBus wait `118,884 → 8,488` | Focused forwarding/load-store/CSR/M-D/PMP/Dhrystone evidence. |
| P-12 | M0 | EX-stage DTCM load launch | Diagnostic endpoint: 674,016 cycles / 0.844419 DMIPS/MHz; not an A/B | Core/SoC load and arbitration tests. Paired disabled/enable run and matched route remain open. |
| P-13 | M0/M1/M2 | Folded-PC 64-entry 2-bit BHT (`PC[6:1] ^ PC[12:7]`) | M1 same-image all-on run: `603,016 → 597,019` cycles (-0.99%); DMIPS/MHz `0.943842 → 0.953323` | BHT corrections `8,000 → 4,003`; predictor unit test and BTFNT/C/RAS directed tests pass on all products. No paired routed PPA; this is controlled historical diagnostic evidence. |
| P-14 | M1/M2 | Parametric RV32M multiplier slice: 8 → 16 bits/iteration | M1 CoreMark: `4,269,496 → 4,081,576` cycles (-4.40%), `2.342197 → 2.450034` CoreMark/MHz. M2: `4,256,434 → 4,068,514` (-4.41%), `2.349384 → 2.457900`. | Controlled uncommitted Verilator A/B, 10 iterations, `-O2`, all other performance gates enabled, identical IMEM/DTCM images per product, CRC PASS. Delivery SoC default is 16; paired FPGA area/timing remains required. |
| P-15 | M1 | GCC CoreMark code-generation sweep | `-O2`: `4,376,295` cycles / `2.285038` CoreMark/MHz; `-O2 -flto`: `4,566,263` / `2.189975`; `-O3`: `4,267,038` / `2.343546`; `-O3 -flto`: `4,103,509` / `2.436939` (+6.65% vs `-O2`). | Historical clean-worktree Verilator A/B, ten iterations, all hardware gates on, GCC 13.2.0, CRC PASS. Profile rerun reproduced all four raw results exactly: `-O2 -flto` versus `-O2` retires +82,087 instructions and adds 113,752 ID/EX-empty cycles (cross-word +26,481; upper-start 32-bit +48,124); `-O3 -flto` versus `-O3` retires −64,571, removes 78,292 ID/EX-empty and 21,715 redirect-recovery cycles. `-O3 -flto` text is 13,586 B versus 7,078 B at `-O2` (+91.9%); it is not the product default pending broader workload and PPA evidence. |
| P-16 | M0/M1/M2 | Four-byte compiler layout as the published benchmark convention | Historical clean-worktree Dhrystone A/B: M0 `0.896275 → 0.906268` DMIPS/MHz (+1.10%); M1 `0.956527 → 0.967904` (+1.19%); M2 `0.858424 → 0.979565` (+12.58%). | `-falign-functions=4 -falign-loops=4 -falign-jumps=4` is now the default only for performance benchmark images. Historical unaligned rows remain archived in `dmips_runs.csv`; `PERF_LAYOUT_ALIGN_CFLAGS=` or Dhrystone `--no-layout-align` reproduces them. |
| P-17 | M0/M1/M2 | Reproducible layout4 feature-gate and CoreMark baseline | Historical clean-worktree all-on Dhrystone: M0 `628,017 / 0.906268`, M1 `588,025 / 0.967904`, M2 `581,025 / 0.979565` (cycles / DMIPS/MHz). CoreMark layout4: M0 `0.931944`, M1 `2.331845`, M2 `2.332937` CoreMark/MHz. Same-build no-align A/B: M0 `0.915955 → 0.931944` (+1.75%), M1 `2.285038 → 2.331845` (+2.05%), M2 `2.241473 → 2.332937` (+4.08%). | Verilator, `-O2`, all hardware gates on, CoreMark ten iterations / Dhrystone 1,000 iterations, and Dhrystone HPM off. All CoreMark CRC runs passed. |
