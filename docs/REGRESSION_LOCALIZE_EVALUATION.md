# Replay-Guided Regression Localization and Circuit-Breaker (bd-3vt.5)

## Summary

Implements two complementary strategies for performance regression management:

1. **Replay-guided regression localization**: Correlates trace divergence with
   per-subsystem event count deltas to identify which subsystem is responsible
   for a regression.

2. **Deterministic circuit-breaker**: Pure-function state machine that trips
   on consecutive failures and recovers through probed half-open state.

## Regression Localization

### Subsystem Classification

Trace events are classified by their kind byte range:

| Range | Subsystem |
|-------|-----------|
| 0x00-0x0F | scheduler (poll, complete, budget, quiescent) |
| 0x10-0x1F | lifecycle (region open/close, task spawn/transition) |
| 0x20-0x2F | obligation (reserve, commit, abort) |
| 0x30-0x3F | channel (send, recv) |
| 0x40-0x4F | timer (set, fire, cancel) |

### Workflow

1. Build baseline `asx_perf_snapshot` from a known-good trace
2. Run the system under test and build a current snapshot
3. Optionally run `asx_replay_verify()` for divergence index
4. Call `asx_regression_localize()` to get blame-ranked suspects

### Blame Scoring

Each suspect receives a score (0-100) proportional to its share of the
total absolute event delta across all subsystems. Suspects are sorted
by blame score descending.

### Output

```c
typedef struct {
    int                     regressed;       /* 1 if regression detected */
    uint32_t                suspect_count;   /* up to 4 suspects */
    asx_regression_suspect  suspects[4];     /* blame-ranked */
    uint32_t                divergence_index;/* from replay if available */
    asx_replay_result_kind  divergence_kind; /* type of first mismatch */
} asx_regression_report;
```

## Circuit-Breaker

### State Machine

```
  CLOSED ──failures >= threshold──> OPEN
    ^                                  │
    │                                  │ events >= cooldown
    │                                  v
    └──successes >= probes──── HALF_OPEN
                                  │
                                  │ failure
                                  v
                                 OPEN
```

### Configuration

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `failure_threshold` | 3 | Consecutive failures before trip |
| `recovery_probes` | 2 | Consecutive successes to close from half-open |
| `cooldown_events` | 10 | Events to wait in OPEN before probing |

### Determinism Guarantee

The circuit-breaker is a pure function of its input sequence:
- No randomness (no jitter, no exponential backoff)
- No time dependency (cooldown is event-counted, not wall-clock)
- Identical failure/success/tick sequences produce identical state
- Fixture-testable via direct unit tests

### Integration with Regression Localization

```c
// After building regression report:
if (report.regressed) {
    asx_cb_record_failure(&ctx, &cfg);
} else {
    asx_cb_record_success(&ctx, &cfg);
}

// Before admitting work:
if (!asx_cb_allows(&ctx)) {
    return ASX_E_ADMISSION_CLOSED;
}
```

## Test Coverage

27 tests across 5 categories:

- Subsystem classification (8): all event kind ranges + names
- Snapshot building (4): empty, counting, aux accumulation, null safety
- Regression localization (5): identical, different, blame ranking, replay correlation, null
- Circuit-breaker (9): init, trip, reset, cooldown, recovery, re-trip, determinism, null, names
- Integration workflow (1): regression -> trip -> cooldown -> probe -> recovery

## Decision

**GO** — Both components are sound and ready for integration:

- Zero allocation (all stack-local or global state)
- Deterministic (no time, no randomness, no FP)
- Composable (regression localization feeds circuit-breaker)
- 27/27 tests pass with strict -Werror
- Operational guardrails: cooldown prevents flapping, half-open limits probe traffic
