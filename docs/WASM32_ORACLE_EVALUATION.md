# wasm32 Determinism Oracle Evaluation (bd-3vt.11)

## Summary

Evaluated a wasm32 determinism oracle for detecting hidden host-coupling
and nondeterminism in the asx ANSI C runtime. The oracle compiles C source
to wasm32 and compares semantic digests against native execution.

## Approach

### Oracle Concept

The wasm32 sandbox provides a controlled execution environment where:
- Pointer size is fixed (4 bytes vs native 8)
- Memory layout is deterministic
- No system calls (no time, no randomness, no filesystem)
- No floating-point nondeterminism
- No alignment tricks or padding assumptions

If a C function produces identical output on wasm32 as on x86_64, it has
**no hidden host coupling**. This is a stronger guarantee than the existing
litmus tests (which validate C99 assumptions but can't detect subtle
platform-dependent behavior).

### Build Probe

Created `tools/ci/wasm32_oracle_probe.sh` to systematically test which
source files compile to `wasm32-unknown-unknown` using clang's built-in
headers (no sysroot required).

### Results

| Category | Pass | Total | Pass Rate |
|----------|------|-------|-----------|
| Core | 7 | 10 | 70% |
| Runtime | 6 | 21 | 29% |
| Channel | 0 | 1 | 0% |
| **Total** | **13** | **31** | **42%** |

#### Files That Compile to wasm32 (no sysroot)

**Core (algebraic, pure functions):**
- `abi.c` — ABI layout validation
- `budget.c` — meet algebra
- `cancel.c` — cancel kinds and severity
- `cleanup.c` — cleanup stack (LIFO)
- `outcome.c` — severity lattice and join
- `status.c` — error code registry
- `transition_tables.c` — state machine authority

**Runtime (scheduler, resource management):**
- `cancellation.c` — cancel propagation
- `profile_compat.c` — profile compatibility
- `quiescence.c` — close preconditions
- `resource.c` — resource management
- `scheduler.c` — round-robin scheduling
- `telemetry.c` — telemetry counters

#### Files That Fail (require libc sysroot)

All failures are due to `<string.h>` (memset/memcpy), `<stdlib.h>`, or
`<stdio.h>`. With wasi-sdk sysroot, all files would compile.

### Semantic Digest Results (native x86_64)

| Digest | Value | Domain |
|--------|-------|--------|
| transition_digest | `0xd50c84f244847664` | Region + Task + Obligation tables |
| outcome_digest | `0xa43cd6488b7bf5d5` | Outcome severity lattice (4x4 join) |
| cancel_severity_digest | `0xdb6e25d96404ba83` | 11 cancel kinds → severity |
| budget_meet_digest | `0xb6eebab98fae117b` | Budget meet algebra |
| region_predicates_digest | `0x0e6be84dfa208a74` | can_spawn, is_closing, etc. |
| terminal_predicates_digest | `0xd4ed4aca6ed38e95` | task/obligation terminal states |
| **AGGREGATE_DIGEST** | **`0xaf2ba9fba1f02942`** | All pure functions combined |

These digests must be identical on wasm32 for the oracle to confirm
platform independence. The aggregate digest captures the entire semantic
fingerprint of the algebraic core.

### Defect Classes the Oracle Would Catch

| Defect Class | Example | Severity | Detected? |
|-------------|---------|----------|-----------|
| Pointer-size assumptions | `sizeof(void*) == 8` | HIGH | Yes — wasm32 has 4-byte pointers |
| Alignment tricks | Casting `uint8_t*` to `uint64_t*` | HIGH | Yes — wasm32 traps on misalignment |
| Padding in structs | `memcmp` on structs with padding | MEDIUM | Yes — different padding |
| size_t assumptions | `size_t` in serialization | MEDIUM | Yes — 4 vs 8 bytes |
| Endian assumptions | Direct byte access of multi-byte | LOW | No — wasm32 is little-endian |
| `long` size | `long` in computations | MEDIUM | Yes — 4 vs 8 bytes |
| Floating-point | FP rounding mode | LOW | Partially — wasm uses IEEE 754 |

### Defect Classes NOT Caught

| Defect Class | Why | Alternative |
|-------------|-----|-------------|
| Endianness | wasm32 is LE like x86 | `check_endian_assumptions.sh` |
| Thread safety | wasm32 is single-threaded | ThreadSanitizer on native |
| Time-dependent | No wall clock in wasm32 | Deterministic hook injection |
| System call coupling | No syscalls in wasm32 | Freestanding profile testing |

## Test Results

9 tests, all passing:

| Category | Tests | What |
|----------|-------|------|
| Semantic digests (6) | transition, outcome, cancel, budget, region, terminal | FNV-1a digest stability |
| Type oracle (1) | sizeof validation | Fixed-width type stability |
| Aggregate (1) | combined digest | Full semantic fingerprint |
| Compatibility (1) | file count | 13/31 compile to wasm32 |

## Decision

### **DEFER** — High value, high setup cost

The wasm32 oracle is the **highest-confidence portability gate** available
(stronger than litmus tests, compiler matrix, or code review). However,
adoption requires toolchain investment.

### Why DEFER (not REJECT)

1. **No wasm runtime available**: wasmtime/wasmer is not installed. The
   oracle compiles to wasm32 but cannot execute. Semantic digest comparison
   requires a wasm runtime.

2. **wasi-sdk needed for full library**: 58% of files fail without a libc
   sysroot. wasi-sdk provides `<string.h>` etc. for wasm targets.

3. **CI pipeline complexity**: Adding wasm32 to CI requires:
   - wasi-sdk installation step
   - wasmtime binary
   - Cross-compilation Makefile target
   - Digest comparison script

4. **Core already passes litmus**: The 15-test litmus suite + 102 translation
   validation checks already cover the C99 assumption surface. The wasm32
   oracle adds confidence but is not discovering new defects today.

### When to Adopt

- **When wasi-sdk enters CI**: If the compiler matrix adds wasm32-wasi,
  the oracle becomes nearly free to run.
- **When portability is questioned**: If porting to ARM32 or other 32-bit
  targets, the oracle validates pointer-size independence.
- **When CI budget allows**: The oracle adds ~30s to CI (compile + run
  + digest comparison).

### Maintenance Cost

| Item | One-time | Ongoing |
|------|----------|---------|
| wasi-sdk installation | 5 min | 0 (pinned version) |
| wasmtime installation | 2 min | 0 (pinned version) |
| Makefile wasm32 target | 30 min | Low (follows native target) |
| Digest baseline file | 10 min | Update on semantic changes |
| CI integration | 1 hr | Low (runs automatically) |

### Invocation Path (future)

```bash
# Build for wasm32
make CC=clang TARGET=wasm32-wasi SYSROOT=/opt/wasi-sdk/share/wasi-sysroot build

# Run digest computation via wasmtime
wasmtime run build/wasm32/test_wasm32_oracle > wasm32_digests.txt

# Compare against native baseline
diff native_digests.txt wasm32_digests.txt
```

### Preserved Artifacts

| Artifact | Purpose |
|----------|---------|
| `tools/ci/wasm32_oracle_probe.sh` | Build compatibility probe |
| `tests/unit/runtime/test_wasm32_oracle.c` | 9 digest + compatibility tests |
| `docs/WASM32_ORACLE_EVALUATION.md` | This evaluation |
| Native digests (in test output) | Baseline for cross-target comparison |
