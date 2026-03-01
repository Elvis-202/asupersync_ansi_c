# Virtual-Time Layer Evaluation

> **Bead:** bd-3vt.8
> **Status:** Prototype complete — GO recommendation
> **Last updated:** 2026-03-01 by NobleCanyon

## 1. Executive Summary

A virtual-time injection layer has been prototyped and validated for
deterministic replay of clock anomalies (jitter, stalls, and forward
jumps). The layer integrates with the existing `asx_clock_hooks`
infrastructure via the `logical_now_ns_fn` callback.

**Decision: GO.** Overhead is negligible (~31 cycles/query), anomaly
scenarios reproduce deterministically, and the fallback to physical
time is preserved by design.

## 2. Design

### 2.1 Architecture

```
┌─────────────────────────┐
│  asx_runtime_now_ns()   │  ← Public API
├─────────────────────────┤
│  Hook dispatch           │  ← ASX_DETERMINISTIC selects logical clock
├─────────────────────────┤
│  asx_vtime_now_ns()     │  ← Virtual-time callback
├─────────────────────────┤
│  Anomaly schedule       │  ← Programmed jitter/stall/jump events
│  Monotonic base ticker  │  ← Configurable tick_ns per query
└─────────────────────────┘
```

### 2.2 Anomaly Types

| Type | Behavior | Use Case |
|------|----------|----------|
| **JITTER** | Add/subtract ns at query N | Clock drift, NTP corrections |
| **STALL** | Hold time constant for N queries | System freeze, GC pause |
| **JUMP** | Leap forward by N ns | Suspend/resume, VM migration |

### 2.3 Key Properties

- **Deterministic:** Same schedule + same query count = identical output
- **Composable:** Multiple anomalies can fire at the same query
- **Bounded:** Max 32 anomalies per schedule (configurable)
- **Lightweight:** ~31 cycles/query (O(anomaly_count) scan per query)
- **Hook-compatible:** Plugs directly into `logical_now_ns_fn`

## 3. API

```c
/* Initialize with base time and tick rate */
asx_vtime_init(&vt, 0, 1000);        /* start=0ns, tick=1µs */

/* Schedule anomalies */
asx_vtime_add_jitter(&vt, 5, 500);   /* +500ns at query 5 */
asx_vtime_add_jitter(&vt, 10, -200); /* -200ns at query 10 (reversal) */
asx_vtime_add_stall(&vt, 20, 5);     /* Freeze for 5 queries at q20 */
asx_vtime_add_jump(&vt, 30, 10000);  /* +10µs forward jump at q30 */

/* Install as logical clock */
hooks.clock.logical_now_ns_fn = asx_vtime_now_ns;
hooks.clock.ctx = &vt;

/* Reset and replay with identical output */
asx_vtime_reset(&vt);
```

## 4. Test Results

### 4.1 Functional Tests (18/18 pass)

| Test | What it validates |
|------|-------------------|
| `monotonic_advance` | Linear tick advance: 0, 1000, 2000, 3000 |
| `custom_base_time` | Non-zero start: 1s base + 500ns ticks |
| `jitter_positive` | +500ns offset at query 2 |
| `jitter_negative` | -500ns offset (clock reversal) at query 2 |
| `stall_freeze` | Time frozen for 3 queries after trigger |
| `stall_recovery` | Time resumes advancing after stall ends |
| `forward_jump` | +10µs leap at query 1 |
| `combined_anomalies` | Jitter + stall + jump in single schedule |
| `deterministic_replay` | Bit-identical output across 2 runs with reset |
| `anomaly_schedule_overflow` | 33rd anomaly returns ASX_E_RESOURCE_EXHAUSTED |
| `zero_tick_manual` | No auto-advance, time changes only via anomalies |
| `jitter_underflow_clamp` | Negative jitter exceeding time clamps to 0 |
| `query_count_tracking` | Query counter matches expected count |
| `reset_preserves_schedule` | Reset clears state but keeps anomaly schedule |
| `hook_callback_integration` | Works via asx_clock_now_ns_fn function pointer |
| `null_safety` | All APIs handle NULL gracefully |
| `multiple_jitters_same_query` | Two jitters at same query both apply |
| `overhead_measurement` | <1000 cycles/query (measured ~31) |

### 4.2 Overhead Measurement

| Metric | Value |
|--------|-------|
| Cycles per query | ~31 |
| Queries measured | 10,000 |
| Anomalies scheduled | 3 |
| Overhead vs bare function call | ~5x (acceptable for test/debug) |

The overhead is negligible for test and replay scenarios. In
production, the virtual-time layer is not used (physical clock
hook is installed instead).

### 4.3 Deterministic Reproduction

The `deterministic_replay` test validates that identical anomaly
schedules produce bit-identical time sequences across runs. This
is the core requirement for anomaly replay.

Test procedure:
1. Configure schedule: jitter(-100 at q3), stall(4 at q7), jump(8000 at q12)
2. Run 20 queries, record all times
3. Reset (preserves schedule)
4. Run 20 queries again
5. Assert all 20 timestamps are bit-identical

Result: **PASS** — perfect determinism.

## 5. Integration Points

### 5.1 Current (Working)

- **Hook callback:** `asx_vtime_now_ns` matches `asx_clock_now_ns_fn` signature
- **Hindsight logging:** All virtual clock reads are automatically logged
  as `ASX_ND_CLOCK_READ` events by the hook dispatch in `hooks.c`
- **Timer wheel:** `asx_timer_advance()` accepts virtual time values

### 5.2 Future Extensions

| Extension | Effort | Priority |
|-----------|--------|----------|
| Scenario DSL parser (JSON anomaly schedules) | ~100 LOC | LOW |
| Fault injection integration (ASX_FAULT_CLOCK_SKEW) | ~50 LOC | MEDIUM |
| Multi-step anomaly chains (jitter → stall → recover) | ~80 LOC | LOW |
| Statistical jitter model (Gaussian, uniform) | ~60 LOC | LOW |

## 6. Risk Assessment

| Risk | Level | Mitigation |
|------|-------|------------|
| Overhead in hot paths | **LOW** | Only used in test/debug; physical clock in production |
| Schedule exhaustion (32 max) | **LOW** | Configurable; sufficient for all known scenarios |
| Non-monotonic time confuses timers | **MEDIUM** | Documented; timer wheel handles non-monotonic input |
| Stall duration too long | **LOW** | Bounded by query_count; no infinite loops |

## 7. Fallback Status

Physical-time mode remains the default and is unaffected:

- When `logical_now_ns_fn` is NULL, the hook dispatch falls through
  to `now_ns_fn` (physical clock)
- Virtual-time layer is compile-time optional (no binary impact if unused)
- All 53 unit tests pass with and without virtual-time in the library

## 8. Artifacts

| Artifact | Purpose |
|----------|---------|
| `include/asx/runtime/virtual_time.h` | Virtual-time injection API |
| `src/runtime/virtual_time.c` | Implementation (~170 LOC) |
| `tests/unit/runtime/test_virtual_time.c` | 18-test deterministic replay suite |
| `docs/VIRTUAL_TIME_EVALUATION.md` | This evaluation document |
