# Zero-Drift Extractor Prototype Evaluation (bd-3vt.10)

## Summary

Prototyped a Rust-AST zero-drift extractor that parses Rust enum definitions
and transition implementations to automatically generate C transition tables
and JSON invariant schema fragments. Validated against the manually curated
C baseline with **zero mismatches** across all three domains.

## Approach

### What the Extractor Does

1. **Parse** Rust `pub enum` definitions to extract state variants and ordinals
2. **Parse** `matches!((self, target), ...)` blocks to extract legal transitions
3. **Parse** `is_terminal` methods to extract terminal states
4. **Emit** C transition table arrays (`static const int X_transitions[N][N]`)
5. **Emit** JSON schema fragments (states, legal/forbidden transitions)
6. **Compare** extracted tables against the manually curated C baseline

### Parser Strategy

The prototype uses regex-based parsing on representative Rust source fragments.
This is sufficient for the highly structured `matches!()` pattern used in the
asupersync Rust source. A production version would use `syn` (Rust AST) or
`tree-sitter-rust` for full fidelity.

## Results

### Extraction Accuracy

| Domain | Variants | Legal Trans. | Forbidden Trans. | Matrix Match | Terminal Match |
|--------|----------|-------------|-----------------|-------------|---------------|
| Region | 5 | 5 | 20 | EXACT | EXACT |
| Task | 6 | 13 | 23 | EXACT | EXACT |
| Obligation | 4 | 3 | 13 | EXACT | EXACT |

All three extracted transition matrices are byte-identical to the manually
curated C baseline in `transition_tables.c`.

### Test Results

17 self-test cases, all passing:

| Category | Tests | What |
|----------|-------|------|
| Extraction (4) | 3 domains + overall | All domains extracted |
| Variant counts (3) | region/task/obligation | 5/6/4 variants |
| Transition counts (3) | region/task/obligation | 5/13/3 legal |
| Baseline parity (3) | matrix comparison | All match C baseline |
| Terminal states (1) | all domains | All terminals match |
| C emission (1) | syntax check | Valid declaration |
| JSON emission (2) | schema fragment | Correct counts |
| Self-transition (1) | CancelRequested→self | Strengthen detected |

### Emitted Artifacts

**C output** (`--emit-c`): Produces drop-in transition table arrays that
match the format of `src/core/transition_tables.c`.

**JSON output** (`--emit-json`): Produces invariant schema fragments compatible
with `schemas/invariant_schema.json` structure (states, legal_transitions,
forbidden_transitions, state_count).

**Comparison** (`--compare`): Structured JSON diff against baseline, with
per-cell mismatch detail if any.

## Decision

### **DEFER** — Correct but premature

The extractor successfully demonstrates zero-drift parity. However, adoption
is premature for these reasons:

### Why DEFER (not REJECT)

1. **No local Rust source**: The Rust baseline lives in a separate repository.
   A production extractor needs access to the actual source AST, not embedded
   samples. The embedded samples prove the technique but don't catch real drift.

2. **Regex is fragile**: The `matches!()` pattern is highly structured, making
   regex viable. But variations in Rust formatting, use of `match` instead of
   `matches!`, or complex predicates would break the regex parser. A production
   version needs `syn` or `tree-sitter`.

3. **Manual curation is working**: The manually curated transition tables have
   been correct throughout the project. The invariant schema was extracted once
   and validated by the litmus suite (102 translation checks). Drift risk is
   low in the current single-extraction model.

4. **Build chain complexity**: Adding a Rust/Python tool to the ANSI C build
   chain introduces a new dependency. The cost is justified only if the Rust
   baseline changes frequently enough to warrant automated tracking.

### When to Adopt

- **If the Rust baseline rebases**: A new Rust commit would invalidate the
  manually curated tables. The extractor could detect drift automatically.
- **If more domains are added**: Each new domain increases manual curation
  burden. At ~10+ domains, automation pays for itself.
- **If `syn` or `tree-sitter` is available**: A full AST parser eliminates
  the regex fragility concern.
- **If CI includes Rust checkout**: The extractor needs access to Rust source
  to run in CI. This requires a cross-repo pipeline.

### Promotion Criteria (for future adoption)

1. Replace regex parser with `syn`-based or `tree-sitter-rust` parser
2. Point at real Rust source (not embedded samples)
3. Run in CI on every Rust baseline update
4. Emit diff report (not just pass/fail) for human review
5. Require sign-off before C table updates are applied

### Rollback Plan

If extractor proves brittle after adoption:
1. Freeze extracted tables at last-known-good
2. Revert to manual curation
3. Delete extractor from build chain
4. No semantic impact (tables are identical either way)

## Artifacts

| Artifact | Purpose |
|----------|---------|
| `tools/zero_drift_extractor.py` | Prototype extractor (17 self-tests) |
| `docs/ZERO_DRIFT_EXTRACTOR_EVALUATION.md` | This evaluation |
