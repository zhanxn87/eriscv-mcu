# eRISCV-M0 FreeRTOS Monitor

This board-oriented image is separate from `rtos/freertos`, which remains the
deterministic qualification test. The monitor uses UART RX interrupts and a
small FreeRTOS command task to expose task, memory, interrupt, and counter
state.

## Build

```sh
make -C eriscv-m0/sw/demos/freertos_monitor images
make -C eriscv-m0/sw/demos/freertos_monitor board-images
```

`images` is the 100 MHz / divider-8 simulation profile and writes under
`sw/build/freertos_monitor/`. `board-images` selects the VCU108 profile:
100 MHz and UART divisor 868 for 115200 baud, writing separately under
`sw/build/freertos_monitor_board/`.

## Commands

Single-key commands are used in the initial monitor to keep the parser small:

| Key | Action |
| --- | --- |
| `h` | Help |
| `i` | Product and clock profile |
| `s` / `m` | `@STAT` telemetry snapshot: CPU estimate, counters, heap, TCM, IRQ counts, pipeline trace |
| `t` | Static task profile and per-task stack high-water mark |
| `e` | Echo acknowledgement |
| `q` | Queue producer/consumer event |
| `r` | Timer0/PLIC/task wake-up event |
| `w` | Start/stop the periodic signal path: Timer0 -> PLIC -> FreeRTOS queue -> 32-tap FIR worker |
| `b` | Queue a deterministic 4096-iteration integer compute burst and report its cycle cost |
| `d` | Stop the pipeline if needed and run the embedded 1,000,000-iteration Dhrystone workload |
| `c` | Stop the pipeline if needed and run the embedded 1,000-iteration CoreMark workload |

The monitor drains bytes left by UART boot before enabling the runtime RX
interrupt. UART boot must therefore be reset before loading a new image.

`cpu_permille` is sampled from `mcycle` between two `s` reports. A
`traceTASK_SWITCHED_IN` hook attributes each completed task interval to the
previously selected task; only intervals belonging to FreeRTOS Idle are counted
as idle time. CPU occupancy is reported to 0.01%. The telemetry task runs once
per second but does not write UART output; its counter is included in each
manual status response.

The local Web Serial dashboard offers an explicit 1 s polling toggle after UART
boot; polling is off by default. It pauses while a benchmark is active; the
worker emits one `@BENCH_DONE` line at completion and the dashboard always
requests one final `@STAT`. Regular 1 s polling resumes only when enabled.
The dashboard uses the private uppercase `S` status command, which returns
`@STAT` without echoing a command or prompt into the terminal; interactive
lowercase `s` remains unchanged.

The dashboard keeps one Web Serial connection and one loaded image, but
separates the user-facing functions into Runtime Overview, Signal Pipeline,
Benchmark Lab, and RTOS Exercises; the shared UART terminal remains fixed
below those views.

## Signal-pipeline showcase

The board has no external sensor wired to this demo, so Timer0 produces a
deterministic 10-bit waveform at 1 kHz: a 64-point low-frequency cosine
component plus a Nyquist-rate alternating disturbance. Each timer interrupt is
routed through PLIC and queues a timestamped sample for the worker task. The
highest-priority worker runs a 32-tap fixed-point triangular FIR, tracks
end-to-end latency and queue drops, and records the latest 128 raw and filtered
samples. While the pipeline is active, `@STAT` carries both traces to the
local Web Serial dashboard, where they are overlaid. Idle status replies omit
the traces and use the UART asynchronous TX queue, so periodic monitoring does
not spend character times in a CPU spin loop. Thus the displayed pipeline,
latency, and attenuation are measurements of the running image, not a
browser-side simulation.

## Mutually exclusive benchmark modes

The signal pipeline, Dhrystone, and CoreMark workloads are mutually exclusive.
`d` and `c` run existing benchmark sources through the highest-priority worker
task with Timer0 stopped and benchmark UART output suppressed. The resulting
cycle counts are exposed in `@STAT`; the dashboard derives Dhrystone
DMIPS/MHz using the conventional 1 DMIPS = 1,757 Dhrystones/s conversion, and
CoreMark/MHz from the fixed iteration counts. The check validates the list,
matrix, and state-machine result CRCs. The board monitor is compiled at `-O2`
for the 100 MHz VCU108 SoC clock. These are
monitor-mode measurements, not EEMBC-certified CoreMark scores: the FreeRTOS
scheduler, interrupt path, compiler, and image layout remain part of the
system under test.

Each benchmark also programs HPM3-HPM6 for `BRANCH_RETIRED`, `BRANCH_TAKEN`,
`CONTROL_TRANSFER_RETIRED`, and `IFETCH_WAIT_CYCLES`. The dashboard reports
the measured counts and CPI. `redirects` is `taken + control-transfer`; the
displayed `flush_slots` is `2 * redirects`, because this core resolves normal
control flow in EX and flushes IF/ID and ID/EX. It is a structural upper-bound
indicator, not a separately measured cycle loss: a redirect can overlap an
instruction-fetch wait.

## Focused simulation evidence

The simulation profile has been checked with the M0 SoC Verilator binary:

- banner, UART RX interrupt, and `i` profile response;
- `s` telemetry prefix and `t` stack-profile output;
- `q` queue producer/consumer handoff;
- `r` Timer0 -> PLIC -> task-notification wake-up.
- accelerated 10 kHz signal-pipeline profile: Timer0 -> PLIC -> ISR queue send
  -> FIR worker frame processing.

The board build has been generated but is not yet board-validated. Upload
`sw/build/freertos_monitor_board/freertos_monitor.imem.mem` through the local
Web Serial console at 115200 baud after programming the M0 VCU108 bitstream.
