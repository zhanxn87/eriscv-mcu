# eRISCV MCU Testbench Performance-Profile Specification v1.0

**Status:** Active engineering measurement contract for `eriscv-m0`,
`eriscv-m1`, and `eriscv-m2` SoC simulation testbenches.

This specification governs the optional `+perf_profile=1` and
`+perf_profile_trace=<csv>` instrumentation. It is testbench-only: it changes
neither synthesizable RTL nor the software-visible HPM CSR ABI. Product-local
testbenches retain their own copies of the implementation; no MCU consumes
another MCU directory.

Published benchmark evidence is owned by the
[Product Manual: Performance](../product-manual/performance.html).
The profile is diagnostic evidence, not a product-performance claim.

## 1. Measurement model

### 1.1 Sampling and window

- Sample observed DUT state at each SoC-clock posedge before NBA updates.
- A profile window begins and ends at explicitly selected retired PCs when the
  runner supplies them. Both boundary retirements are included.
- `window_cycles` includes every SoC-clock cycle in the window. `core_enabled`
  is a subset in which the core clock-enable is active.
- Latency is accepted-request edge to matching-response edge. A fixed
  next-cycle SRAM response has latency one; a same-cycle fast store completion
  has latency zero.
- An opt-in **sparse root-cause trace** records the observation cycle, event
  name, architectural or request PC, and two documented event-specific values.
  It requires `+perf_profile=1` and is not enabled for ordinary regression.

### 1.2 Evidence classes

Every metric belongs to exactly one class.

| Class | Meaning | May be summed into a cycle-loss claim? |
| --- | --- | --- |
| **Cycle-accountable** | Mutually exclusive member of a documented closure. | Only within its own closure. |
| **Overlap diagnostic** | A sampled condition that may coexist with other conditions. | No. Use its explicit union counter if provided. |
| **Traffic/event diagnostic** | Requests, responses, retirements, prediction events, or buffer states. | No. |

No report may call an admission guard, a request state, or a raw stall level a
"lost cycle". A performance conclusion must cite a cycle-accountable closure
or controlled same-image A/B data.

## 2. Required metric set

### 2.1 Window and retirement closure

All products shall report:

| Metric | Class | Definition |
| --- | --- | --- |
| `window_cycles` | Cycle-accountable | Total sampled cycles in the selected window. |
| `retired` | Cycle-accountable | Architectural retirement pulse count. |
| `no_retire` | Cycle-accountable | `window_cycles - retired`. |
| `no_retire.{clock_off,wfi_sleep,debug_halted,selected_hold,redirect_recovery,idex_empty,other}` | Cycle-accountable | Mutually exclusive immediate reason for a no-retire cycle. |
| `cpi` | Derived | `window_cycles / retired`; never derived from overlapping diagnostics. |

`no_retire` must close exactly to its members. `selected_hold` is the union of
the listed pipeline hold sources, not the sum of their individual counters.
`wfi_sleep` and `debug_halted` take priority over the generic clock-off,
redirect-recovery, and empty-pipeline classes, so a halted core is never
misreported as front-end recovery. They are reported only in this closure, not
again as overlapping stall-level counters.

### 2.2 Pipeline and memory diagnostics

All available product-local sources shall be reported as overlap diagnostics:

- IF response wait, D-bus response wait, ID/EX and EX/MEM load-use holds;
- local-memory early-load candidates, accepts, and responses;
- forwarding selection and value-check results;
- D-bus request count, target class, response latency histogram, and errors;
- IF request count, response latency histogram, request/read-data contention;
- branch prediction accuracy and redirect recovery interval.

M1/M2 additionally report mul/div completion count, busy cycles, and the
union/overlap with other selected holds. M2 additionally reports FPU hold and
completion diagnostics. A product without the underlying feature prints
`N/A`, not zero as if it had measured the feature.

### 2.3 IF request-admission diagnostics

`if_stage.can_issue` is a request-admission predicate, not an instruction
delivery or retirement predicate. While `core_enabled` is active, report:

- opportunities where `can_issue=1` and its outcome: request accepted,
  request backpressured by IMEM readiness, or no request demanded;
- an admission-guard vector for each `can_issue=0` opportunity;
- a deterministic **primary guard** only for histogram closure and PC grouping;
- raw per-guard counts, which may overlap, and a multi-guard count.

Do not retain separate packing sub-histograms (for example `upper_start.c16`
or `cross_word.id_hold`). They do not describe a delivery bubble beyond the
cycle-accountable causes in Section 2.4 and add profile work without changing
an optimization decision.

The guard vector mirrors the implemented IF expression.  The single-word M0/M1
front end reports:

```text
fetch_disabled, boot_init, hold_valid, pending_response,
two_c16_pack, upper_start_without_prefetch, cross_word_single_buffer
```

M2's two-word line front end has no halfword packing guard.  It instead
reports:

```text
fetch_disabled, boot_init, outstanding_line, line_slots_full
```

`outstanding_line` means a prior IF line transaction has not returned;
`line_slots_full` means two retained lines prevent a requested replacement.
The legacy `two_c16`, `upper_start`, and `cross_word` fields are retained as
zero-valued columns solely to keep the common report parser stable.

Admission guards are summary-only. If one actually prevents IF delivery, the
cycle-accountable `no_source.guard` trace row carries the unaligned candidate
PC and the complete guard bit mask. Report labels use `admission_guard`,
never `blocked`, `stall`, or `lost`.

### 2.4 IF delivery to ID/EX-empty attribution

The profile shall independently mirror the priority of the IF delivery logic
and register its result through the IF/ID-to-ID/EX boundary. It must check the
predicted IF/ID valid bit against the actual registered valid bit on the next
edge before using the result for attribution.

The following causes form a mutually exclusive, cycle-accountable partition
of `idex_empty.ifid_invalid`:

| Cause | Required PC | Meaning |
| --- | --- | --- |
| `redirect.{id_branch,id_jal,id_ras,ex_recovery,trap,debug,fence_i,wfi}` | Redirect target | IF/ID was deliberately discarded for the named redirect source. Correct ID prediction is not a misprediction. |
| `flush` | Candidate PC | Explicit IF/ID flush other than redirect. |
| `cross_word_wait` | Buffered upper-halfword PC | RV32 instruction awaits the following word (single-word front ends only). |
| `upper_start_rv32` | Requested upper-halfword PC | Halfword-addressed target starts an RV32 instruction (single-word front ends only). |
| `response_wait` | Candidate PC | A previously accepted request has not returned. |
| `no_source.request_started` | Candidate PC | No data was available for this delivery, but a request is accepted at this edge. This identifies exposed request/response latency, not a guaranteed queue saving. |
| `no_source.no_demand` | Candidate PC | No data and no request because neither PC advance nor redirect demands one. |
| `no_source.guard` | Candidate PC plus guard mask | No data and a current admission guard prevents a request. |
| `id_hold.{front,full,pmp,other}` | Candidate PC | IF/ID retains an invalid packet because a documented downstream hold is active. |
| `drop_response` | Response PC | Stale response intentionally discarded after a redirect. |
| `unclassified` | Candidate PC | Contract failure; must be zero in a valid run. |

`no_source.*` records the exact empty-delivery state and current request action.
It does **not** claim the prior cause of that state and must never be used alone
to forecast the benefit of a fetch queue. Queue feasibility requires a
controlled A/B implementation and a review of the request-lifecycle trace.

The former live-state `IFID INVALID.{cross_word_wait,imem_response_wait,
fetch_disabled,delivery_gap}` report is forbidden. It observes controls after
the causal IF edge and is redundant once the registered delivery model exists.

### 2.5 Redirect and predictor metrics

Redirect delivery bubbles and prediction correctness are separate metrics.

- A conditional-branch prediction reports direction correctness only at branch
  resolution; it does not include direct JAL or RAS return redirects.
- `redirect.id_branch`, `redirect.id_jal`, and `redirect.id_ras` identify
  deliberate ID-stage target changes. They may be correct predictions and
  still incur a fixed one-cycle local-memory refill opportunity.
- `redirect.ex_recovery` means EX corrected an unpredicted or incorrect control
  transfer. `redirect_recovery_cycles` is separately measured from that event
  until the next architectural retirement.
- Trap, Debug, FENCE.I, and WFI redirects remain distinct because they have
  different architectural causes and must not be attributed to predictor cost.

### 2.6 PC trace and aggregation

The trace is optional because file I/O can dominate a long simulation. It is
therefore sparse: only cycle-accountable IF-delivery bubbles, load-use holds,
and DBus responses with latency greater than one cycle or an error emit rows.
It deliberately omits retirements, correctly resolved branches, normal DBus
requests/responses, and benign admission guards such as `two_c16_pack`.
Aggregate counters retain those population measurements without creating CSV
traffic. The standard summary groups `event × PC` and reports the top PCs.

Use the repository tool, for example:

```sh
python3 tools/sim/summarize_perf_profile_trace.py /tmp/m1-profile.csv \
  --event-prefix if_delivery_to_bubble --top 12
```

PC fields are event-local. They are not always the retiring PC:

- request guards and `no_source.*`: next request candidate;
- cross-word: buffered first-halfword PC;
- upper-start: requested target PC;
- redirect: chosen redirect target;
- branch/load-use/retirement events: instruction PC.

## 3. Product applicability

| Metric family | M0 | M1 | M2 |
| --- | --- | --- | --- |
| Window, retirement, IF admission, IF delivery, traffic, hazards | Required | Required | Required |
| Branch/BHT/RAS diagnostics | Required when feature enabled | Required when feature enabled | Required when feature enabled |
| PMP hold and PMP redirect detail | N/A | Required when PMP enabled | Required when PMP enabled |
| Mul/div diagnostics | N/A | Required | Required |
| FPU hold/completion diagnostics | N/A | N/A | Required when RV32F is enabled |

The report schema and names are aligned across product-local files. Product
feature differences are represented by `N/A` or a documented conditional
field, never by silently omitting a common metric.

## 4. Verification requirements

An implementation change is complete only when all of the following hold:

1. The profile compiles in the product SoC testbench with the default Verilator
   flow and does not alter the software image, RTL, or HPM report ABI.
2. Every cycle-accountable partition closes exactly; every `unclassified`
   counter is zero.
3. The IF delivery valid prediction is checked against the registered IF/ID
   valid bit on every sampled edge.
4. Directed or workload evidence covers each enabled nontrivial IF delivery
   cause. A fixed one-cycle product memory may mark an unavailable response
   wait as `N/A`; it must not be reported as verified zero without such scope.
5. At least one trace run is summarized by event and PC, and its aggregate
   counts match the corresponding report counters.
6. Controlled performance A/B claims use the same committed RTL revision,
   compiler flags, linker layout, image, profile window, and simulator backend.

## 5. Non-goals

- The profile is not a replacement for HPM, RTL assertions, formal proof,
  FPGA timing, power analysis, or board measurements.
- It does not infer a speedup from guard frequency, overlap diagnostics, or
  an isolated benchmark hotspot.
- It does not make cache, prefetch queue, predictor, or multiplier design
  decisions. It supplies evidence for those decisions.
