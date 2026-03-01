# SOS Barrier-Certificate Bounds for Adaptive Scheduler Safety (bd-3vt.6)

## Summary

Evaluated Sum-of-Squares (SOS) barrier-certificate style bounds as a formal
assurance lever for preventing task starvation under adaptive scheduling
policies. Implemented a discrete barrier function prototype and validated it
against simulated scheduling trajectories.

## Background

SOS barrier certificates are a control-theory technique where a polynomial
function B(x) is synthesized (offline via semidefinite programming) such that
B(x) > 0 guarantees the system stays within a safe region. The decrease
condition dB/dt < 0 along trajectories provides the safety invariant.

For discrete-time schedulers, this translates to:
- B(x) = K - max(wait_i) where wait_i is rounds since task i was last polled
- Safety: B(x) > 0 implies no task has starved beyond K rounds
- Decrease: B(x') < B(x) requires the scheduler to reduce max wait

## Prototype Implementation

### Barrier Function

```
B(x) = starvation_bound - max(wait_counts[0..N-1])
```

- `wait_counts[i]` increments each round, resets to 0 when task i is polled
- `starvation_bound` (K) is the safety threshold
- B > 0 means all tasks are within the starvation bound
- B <= 0 means at least one task has been starved

### API

| Function | Purpose |
|----------|---------|
| `asx_barrier_state_init()` | Initialize wait counters for N tasks |
| `asx_barrier_record_poll()` | Reset a task's wait counter (it was polled) |
| `asx_barrier_advance_round()` | Increment all wait counters |
| `asx_barrier_evaluate()` | Compute B(x), check safety and decrease |
| `asx_barrier_max_wait()` | Query current max wait |
| `asx_barrier_admits_bound()` | Check if K is achievable for N tasks |

## Findings

### Scheduler Policy Analysis

| Policy | Starvation Bound K | Achievable? |
|--------|-------------------|-------------|
| Round-robin (budget >= N) | K = 1 | Yes — every task polled every round |
| Round-robin (budget < N) | K = ceil(N/budget) | Yes — guaranteed by round-robin order |
| Weighted (fair) | K = max(N/w_i) | Depends on weight distribution |
| Priority (cancel-first) | Unbounded for low-priority | No — cancel pressure can starve ready tasks |
| Adaptive (external) | Depends on caller | Unknown — no internal guarantee |

### Key Result

**Round-robin scheduling trivially satisfies the barrier certificate.**
When budget >= N tasks, every task is polled every round, so max_wait <= 1.
The barrier function is redundant for the base scheduler.

**Priority and adaptive policies can violate the barrier.** The prototype
correctly detects starvation: when task 0 is never polled but tasks 1-3
are, the barrier trips after `starvation_bound` rounds.

### Test Results

17 tests across 6 categories, all passing:

- Initialization (3): clear, clamp, null
- Barrier function (3): initial value, decrease, violation detection
- Round-robin safety (3): full RR safe, partial RR violates, weighted tracking
- Bound admissibility (4): positive, zero, overflow, null
- State management (3): poll reset, null safety, max tracking
- Determinism (1): identical trajectories produce identical barrier values

## Decision

**DEFER** — The barrier-certificate approach is theoretically sound but
premature for the current codebase:

### Why DEFER (not REJECT)

1. **Base scheduler is already safe**: Round-robin provides implicit starvation
   bounds without a barrier function. The overhead of runtime barrier checking
   adds zero value for the walking skeleton.

2. **Adaptive system is decoupled**: The expected-loss adaptive layer (adaptive.c)
   makes advisory decisions that are applied externally. No mechanism currently
   exists to feed barrier violations back into the adaptive decision loop.

3. **Full SOS synthesis is offline**: True barrier certificates require
   semidefinite programming (DSOS/SDSOS relaxations) to synthesize B(x) offline.
   The runtime evaluator is the simpler half; the harder half (synthesis) requires
   tooling (SOSTOOLS, DSOS) that is outside the ANSI C build chain.

4. **Phase 3 opportunity**: When Phase 3 introduces dynamic allocation and
   multi-threaded scheduling, fairness guarantees become non-trivial and a
   barrier-based monitor could provide real value.

### Alternative Guardrail (Current)

The parallel scheduler already tracks starvation via `lane->starvation_count`.
This provides detection without the formalism overhead. For the walking skeleton,
this is sufficient.

### When to Revisit

- If adaptive decisions directly control scheduler behavior (not just advisory)
- If multi-threaded scheduling is added (fairness becomes non-trivial)
- If a specific deployment requires formal starvation bounds (certification)
- If offline SOS synthesis tooling is integrated into the build chain

### Preserved Artifacts

The spike code is preserved for future reference:
- `barrier_cert_spike.c`: Runtime barrier evaluator
- `test_barrier_cert.c`: 17 validation tests
- This document: feasibility analysis and decision rationale
