# Cache-Oblivious Arena Layout Evaluation (bd-3vt.3)

## Summary

Evaluated two alternative memory layouts for scheduler task slots against the
baseline Array-of-Structures (AoS): hot/cold field splitting and full
Structure-of-Arrays (SoA) columnar layout.

## Layouts Evaluated

### 1. Baseline AoS (current)
Each task slot is a contiguous struct of all fields (152 bytes).
The scheduler scans the entire array linearly.

### 2. Hot/Cold Split
Separate hot fields (state, alive, region, poll_fn, user_data = 32 bytes)
from cold fields (cancel_reason, outcome, capture, generation = 112 bytes).
Scheduler scan touches only the hot array.

### 3. SoA (Structure of Arrays)
Each field is a separate contiguous array. Scheduler scan touches only
the alive[], regions[], and states[] arrays.

## Measurements (64 task slots)

| Metric | AoS | Hot/Cold | SoA |
|--------|-----|----------|-----|
| Slot size (bytes) | 152 | 32 hot + 112 cold | N/A (columnar) |
| Cache lines touched (scan) | 152 | 32 | 16 |
| Working set (scan, bytes) | 9,728 | 2,048 | 1,024 |
| Throughput (cycles/scan) | ~254 | ~255 | ~251 |

## Analysis

### Cache Line Reduction
- Hot/Cold reduces cache lines 4.75x (152 -> 32)
- SoA reduces cache lines 9.5x (152 -> 16)

### Throughput Impact
At the current arena size (64 tasks), **all three layouts produce
identical throughput** (~250 cycles). This is because the entire
working set (< 10 KB) fits in L1 cache regardless of layout.

The cache line reduction would only produce measurable benefit when:
- Task count exceeds ~256 (working set > L1 size)
- Multiple hot data structures compete for cache space
- The system runs under sustained cache pressure

### Portability Concerns

**Hot/Cold split:**
- Requires maintaining two parallel arrays with synchronized indices
- Task creation/deletion must update both arrays atomically
- Adds indirection for cold-field access (cancel operations)
- Generation-tagged handles must encode which array to index

**SoA:**
- Requires rewriting every field access site (`task->state` becomes `states[i]`)
- Breaks encapsulation: no single "task struct" to pass by pointer
- Task creation requires initializing N separate arrays
- Significantly harder to extend with new fields
- Captured state dtor callback loses its natural struct context

### Semantic Neutrality

All layouts are semantically neutral for the scheduler scan path.
However, the cancel/cleanup/completion paths access cold fields
(cancel_reason, outcome, captured_state), which would require
dereferencing the cold array in the hot/cold split or accessing
separate columns in SoA — negating some of the scan benefit.

### Maintenance Cost

The current AoS layout has zero coordination overhead. Adding a field
to a task slot requires editing one struct definition. Both alternatives
require proportional changes across multiple data structures and every
access site.

## Decision

**DEFER** — The evaluation shows clear theoretical cache efficiency gains
but zero measurable throughput improvement at the current arena size (64
tasks). The maintenance and complexity costs of either alternative
outweigh the benefits:

1. **No measurable benefit now**: All layouts run at ~250 cycles/scan
   because the full working set fits in L1 cache.

2. **Phase 3 will change the arena model**: The walking skeleton uses
   static arrays. Phase 3 introduces hook-backed dynamic allocation,
   which will require re-evaluating layout strategy anyway.

3. **High code churn, low payoff**: Hot/cold split or SoA would touch
   every file that accesses task slots (scheduler, lifecycle,
   cancellation, quiescence, resource, adapter). This is significant
   refactoring for zero current gain.

### When to Revisit

- If ASX_MAX_TASKS increases beyond 256
- If Phase 3 dynamic allocation introduces arena-level decisions
- If profiling shows scheduler scan as a cache-miss bottleneck
- If multi-threaded scheduling (false sharing) becomes relevant

### Fallback

The spike code and benchmarks are preserved in `arena_locality_spike.c`
and `test_arena_locality.c` for future reference. The SoA approach is
the recommended candidate if re-evaluation is triggered.
