# Certification-Ready Evidence Bundle

> **Bead:** bd-56t.3
> **Status:** Canonical certification skeleton
> **Last updated:** 2026-03-01 by NobleCanyon
> **Applicable standards:** ISO 26262 (Automotive), DO-178C (Avionics), IEC 61508 (Industrial)

This document defines the evidence bundle structure for certification-ready
release candidates of the asupersync ANSI C runtime. It maps every claim
to documented evidence and traceable artifacts.

## 1. Bundle Structure

```
evidence-bundle/
  1-requirements/
    traceability_index.md          → docs/PLAN_EXECUTION_TRACEABILITY_INDEX.md
    feature_parity.md              → docs/FEATURE_PARITY.md
    invariant_schema.json          → schemas/invariant_schema.json
    canonical_fixture.schema.json  → schemas/canonical_fixture.schema.json
  2-design/
    guarantee_substitution.md      → docs/GUARANTEE_SUBSTITUTION_MATRIX.md
    architecture_decisions.md      → docs/OPEN_DECISIONS_ADR.md
    lifecycle_transitions.md       → docs/LIFECYCLE_TRANSITION_TABLES.md
    formal_assurance_ladder.md     → docs/FORMAL_ASSURANCE_LADDER.md
    memory_model_findings.md       → docs/MEMORY_MODEL_FINDINGS.md
  3-verification/
    quality_gates.md               → docs/QUALITY_GATES.md
    test_log_schema.md             → docs/TEST_LOG_SCHEMA.md
    wave_gating_protocol.md        → docs/WAVE_GATING_PROTOCOL.md
    semantic_delta_budget.md       → docs/SEMANTIC_DELTA_BUDGET.md
  4-risk/
    risk_register.md               → docs/RISK_REGISTER.md
    proof_block_exceptions.md      → docs/PROOF_BLOCK_EXCEPTION_WORKFLOW.md
    deferred_surfaces.md           → docs/DEFERRED_SURFACES.md
  5-ci-artifacts/
    conformance/                   → tools/ci/artifacts/conformance/
    evidence/                      → tools/ci/artifacts/evidence/
    test-logs/                     → build/test-logs/
    bench/                         → build/bench/
    perf/                          → build/perf/
  6-deployment/
    deployment_hardening.md        → docs/DEPLOYMENT_HARDENING.md
    automotive_profile.md          → docs/AUTOMOTIVE_PROFILE.md
```

## 2. Claim-Evidence-Artifact Mapping

### 2.1 Requirements Traceability

| Claim ID | Claim | Evidence Type | Artifact Location | Gate |
|----------|-------|--------------|-------------------|------|
| CL-REQ-01 | All plan commitments are mapped to implementation beads | Traceability index | `docs/PLAN_EXECUTION_TRACEABILITY_INDEX.md` | LINT-EVIDENCE |
| CL-REQ-02 | Feature parity with Rust reference is tracked | Parity matrix | `docs/FEATURE_PARITY.md` | GATE-SEM-DELTA |
| CL-REQ-03 | State machines are formally specified | Invariant schema | `schemas/invariant_schema.json` | MODEL-CHECK |
| CL-REQ-04 | Fixture schema defines acceptance format | Fixture schema | `schemas/canonical_fixture.schema.json` | CONFORMANCE |

### 2.2 Design Assurance

| Claim ID | Claim | Evidence Type | Artifact Location | Gate |
|----------|-------|--------------|-------------------|------|
| CL-DES-01 | Rust safety guarantees have explicit C substitutions | Substitution matrix | `docs/GUARANTEE_SUBSTITUTION_MATRIX.md` | LINT-ANTI-BUTCHERING |
| CL-DES-02 | Architecture decisions are recorded and justified | ADR records | `docs/OPEN_DECISIONS_ADR.md` | — |
| CL-DES-03 | Lifecycle transitions are formally documented | Transition tables | `docs/LIFECYCLE_TRANSITION_TABLES.md` | MODEL-CHECK |
| CL-DES-04 | Formal verification covers critical paths | Assurance ladder | `docs/FORMAL_ASSURANCE_LADDER.md` | formal-check |
| CL-DES-05 | Memory model assumptions are documented | Litmus findings | `docs/MEMORY_MODEL_FINDINGS.md` | formal-litmus |
| CL-DES-06 | ABI stability contract is defined | ABI header | `include/asx/asx_abi.h` | abi-check |
| CL-DES-07 | Forward-compatible evolution via size-field pattern | Config struct design | `include/asx/asx_abi.h` Section 6 | test-abi-shim |

### 2.3 Verification Evidence

| Claim ID | Claim | Evidence Type | Artifact Location | Gate |
|----------|-------|--------------|-------------------|------|
| CL-VER-01 | Unit tests cover all modules | JSONL test logs | `build/test-logs/unit-*.jsonl` | UNIT |
| CL-VER-02 | Invariant tests verify state machine properties | JSONL test logs | `build/test-logs/invariant-*.jsonl` | INVARIANT |
| CL-VER-03 | Conformance runner validates Rust parity | Summary JSON + JSONL | `tools/ci/artifacts/conformance/*-conformance.*` | CONFORMANCE |
| CL-VER-04 | Codec equivalence verified (JSON vs BIN) | Summary JSON | `tools/ci/artifacts/conformance/*-codec-equivalence.*` | CODEC |
| CL-VER-05 | Profile parity verified across targets | Summary JSON | `tools/ci/artifacts/conformance/*-profile-parity.*` | GATE-PROFILE |
| CL-VER-06 | Differential fuzzing finds no divergence | Fuzz summary | `tools/ci/artifacts/fuzz/*.summary.json` | GATE-FUZZ |
| CL-VER-07 | Bounded model checking exhaustive | Model check results | `build/test-logs/invariant-model_check*.jsonl` | MODEL-CHECK |
| CL-VER-08 | CBMC harnesses verify C code correctness | Formal harness output | `make formal-cbmc` (145 checks) | formal-cbmc |
| CL-VER-09 | Algebraic properties hold for lattice/monoid ops | Algebraic test output | `make formal-algebraic` (25 tests) | formal-algebraic |
| CL-VER-10 | Translation validation: schema matches C code | TV report JSON | `tools/ci/check_translation_validation.sh` (102 checks) | formal-tv |
| CL-VER-11 | Codegen stable across optimization levels | Codegen report JSON | `tools/ci/check_codegen_stability.sh` (5 levels) | formal-codegen |
| CL-VER-12 | ABI stability: frozen values unchanged | ABI report JSON | `tools/ci/check_abi_stability.sh` (29 checks) | abi-check |
| CL-VER-13 | Consumer shim validates external usage | Shim test output | `tests/abi/consumer_shim.c` (51 assertions) | test-abi-shim |
| CL-VER-14 | SLO performance budgets met | SLO gate JSON | `tools/ci/evaluate_slo_gates.sh` | slo-gate |
| CL-VER-15 | Binary size budgets met | Size gate JSON | `tools/ci/evaluate_size_gates.sh` | size-gate |
| CL-VER-16 | E2E deployment scenarios pass | E2E script output | `tests/e2e/*.sh` | GATE-E2E |
| CL-VER-17 | Semantic delta budget is zero | Delta budget JSON | `build/conformance/semantic_delta_*.json` | GATE-SEM-DELTA |
| CL-VER-18 | Memory-model litmus tests pass | Litmus test output | `make formal-litmus` (15 tests) | formal-litmus |

### 2.4 Risk Mitigation

| Claim ID | Claim | Evidence Type | Artifact Location | Gate |
|----------|-------|--------------|-------------------|------|
| CL-RSK-01 | All identified risks have owners and mitigations | Risk register | `docs/RISK_REGISTER.md` | — |
| CL-RSK-02 | Anti-butchering prevents semantic regression | Proof block audit | `build/conformance/anti_butcher_*.json` | LINT-ANTI-BUTCHERING |
| CL-RSK-03 | Deferred surfaces are explicitly tracked | Deferred register | `docs/DEFERRED_SURFACES.md` | — |
| CL-RSK-04 | Exception workflow is documented and auditable | Exception records | `docs/SEMANTIC_DELTA_EXCEPTIONS.json` | GATE-SEM-DELTA |

### 2.5 Deployment Readiness

| Claim ID | Claim | Evidence Type | Artifact Location | Gate |
|----------|-------|--------------|-------------------|------|
| CL-DEP-01 | Operator runbooks exist for target verticals | Hardening playbooks | `docs/DEPLOYMENT_HARDENING.md` | — |
| CL-DEP-02 | Automotive safety profile is documented | Profile companion | `docs/AUTOMOTIVE_PROFILE.md` | GATE-AUTO-DEADLINE |
| CL-DEP-03 | Embedded targets build and run | Matrix results | `tools/ci/artifacts/qemu/` | GATE-EMBED |
| CL-DEP-04 | Compiler matrix passes | CI job results | `.github/workflows/ci.yml` compiler-matrix job | GATE-PORT |
| CL-DEP-05 | Evidence dashboard shows no regressions | Dashboard JSON | `build/perf/regression_dashboard_*.json` | evidence-dashboard |

## 3. Standards Mapping Templates

### 3.1 ISO 26262 (Automotive Safety)

| ISO 26262 Requirement | ASIL Level | Evidence Bundle Section | Claim IDs |
|----------------------|-----------|----------------------|-----------|
| 6.4.1 Safety requirements specification | B-D | 1-requirements/ | CL-REQ-01..04 |
| 6.4.2 Software architectural design | B-D | 2-design/ | CL-DES-01..07 |
| 6.4.3 Software unit design | B-D | 2-design/ + 3-verification/ | CL-DES-03, CL-VER-01..02 |
| 6.4.4 Software unit testing | B-D | 3-verification/ | CL-VER-01..02, CL-VER-07..09 |
| 6.4.5 Software integration testing | B-D | 3-verification/ | CL-VER-03..06, CL-VER-16 |
| 6.4.6 Software qualification testing | B-D | 5-ci-artifacts/ | CL-VER-14..15, CL-DEP-03..04 |
| 6.4.7 Verification of software safety | B-D | 4-risk/ | CL-RSK-01..04 |
| 6.4.8 Software release | B-D | 6-deployment/ | CL-DEP-01..05 |
| 6.4.9 Functional safety management | B-D | 4-risk/ | CL-RSK-01 |

### 3.2 DO-178C (Avionics Software)

| DO-178C Objective | DAL A-D | Evidence Bundle Section | Claim IDs |
|------------------|---------|----------------------|-----------|
| A-1: SW Plans | A-D | 1-requirements/ | CL-REQ-01 |
| A-2: SW Development Standards | A-D | 2-design/ | CL-DES-01..07 |
| A-3: SW Requirements | A-D | 1-requirements/ | CL-REQ-01..04 |
| A-4: SW Design | A-D | 2-design/ | CL-DES-01..05 |
| A-5: SW Coding Standards | A-D | 3-verification/ | FORMAT, LINT gates |
| A-6: Integration Process | A-D | 5-ci-artifacts/ | CL-VER-03..06 |
| A-7: Verification Process | A-D | 3-verification/ | CL-VER-01..18 |
| A-8: Configuration Management | A-D | 5-ci-artifacts/ | Run manifests |

### 3.3 IEC 61508 (Industrial Safety)

| IEC 61508 Requirement | SIL 1-4 | Evidence Bundle Section | Claim IDs |
|----------------------|---------|----------------------|-----------|
| 7.4.2 Software safety requirements | 1-4 | 1-requirements/ | CL-REQ-01..04 |
| 7.4.3 Software design and development | 1-4 | 2-design/ | CL-DES-01..07 |
| 7.4.4 Software verification | 1-4 | 3-verification/ | CL-VER-01..18 |
| 7.4.5 Software integration testing | 1-4 | 5-ci-artifacts/ | CL-VER-03..06 |
| 7.4.6 Modification procedures | 1-4 | 4-risk/ | CL-RSK-02..04 |
| 7.4.7 Software verification report | 1-4 | 5-ci-artifacts/ | All CI artifacts |

## 4. CI Artifact Cross-Reference

### 4.1 Per-Gate Artifact Map

| Gate ID | Makefile Target | Artifact Path | Schema |
|---------|----------------|---------------|--------|
| UNIT | `test-unit` | `build/test-logs/unit-*.jsonl` | `schemas/test_log.schema.json` |
| INVARIANT | `test-invariants` | `build/test-logs/invariant-*.jsonl` | `schemas/test_log.schema.json` |
| CONFORMANCE | `conformance` | `tools/ci/artifacts/conformance/*-conformance.*` | Inline JSONL |
| CODEC | `codec-equivalence` | `tools/ci/artifacts/conformance/*-codec-equivalence.*` | Inline JSONL |
| GATE-PROFILE | `profile-parity` | `tools/ci/artifacts/conformance/*-profile-parity.*` | Inline JSONL |
| GATE-FUZZ | `fuzz-smoke` | `tools/ci/artifacts/fuzz/*.summary.json` | Inline JSON |
| MODEL-CHECK | `model-check` | Build output | — |
| formal-cbmc | `formal-cbmc` | Build output (145 checks) | — |
| formal-algebraic | `formal-algebraic` | Build output (25 tests) | — |
| formal-tv | `formal-tv` | Report JSON | `asx.translation_validation_report.v1` |
| formal-litmus | `formal-litmus` | Build output (15 tests) | — |
| formal-codegen | `formal-codegen` | Report JSON | `asx.codegen_stability_report.v1` |
| abi-check | `abi-check` | Report JSON | `asx.abi_stability_report.v1` |
| test-abi-shim | `test-abi-shim` | Build output (51 assertions) | — |
| slo-gate | `slo-gate` | Report JSON | `asx.slo_gate_report.v1` |
| size-gate | `size-gate` | Report JSON | `asx.size_gate_report.v1` |
| GATE-EMBED | `ci-embedded-matrix` | `tools/ci/artifacts/qemu/` | Inline JSON |
| GATE-PORT | `compiler-matrix` | Build output | — |
| evidence-dashboard | `evidence-dashboard` | `build/perf/regression_dashboard_*.json` | `asx.evidence_regression_dashboard.v1` |

### 4.2 Run Manifest Cross-Reference

Every CI run produces a manifest at `build/perf/ci_manifest_*.json` with:
- `run_id`: Unique run identifier
- `git_sha`: Commit hash
- `timestamp`: ISO 8601
- `gate_results`: Per-gate pass/fail/skip
- `artifact_paths`: Per-gate artifact locations

## 5. Audit Replay Protocol

For third-party audit replay of key failures and mitigations:

### 5.1 Failure Replay

1. Identify failure in conformance JSONL: `grep '"status":"fail"' *.jsonl`
2. Extract `scenario_id` and `seed` from failing record
3. Replay: `ASX_E2E_SEED=<seed> tests/e2e/<scenario>.sh`
4. Compare trace digest against expected
5. If `delta_classification: "harness_defect"`, check `build/conformance/` for build logs
6. If `delta_classification: "c_regression"`, check diff artifact at path in record

### 5.2 Mitigation Replay

1. Locate exception in `docs/SEMANTIC_DELTA_EXCEPTIONS.json`
2. Verify `tracking_bead` is closed
3. Verify `deadline` has not passed
4. Replay affected scenarios with `run_conformance.sh --mode <mode>`
5. Confirm semantic delta count <= approved budget

### 5.3 Risk Register Replay

1. For each risk in `docs/RISK_REGISTER.md`:
2. Verify controlling CI gate passes in latest manifest
3. Check evidence dashboard for trend alerts
4. Confirm no unresolved proof-block exceptions

## 6. Evidence Completeness Checklist

| # | Item | Source | Status |
|---|------|--------|--------|
| 1 | Traceability index complete | `docs/PLAN_EXECUTION_TRACEABILITY_INDEX.md` | Verify all TRC-* rows have artifacts |
| 2 | Feature parity matrix complete | `docs/FEATURE_PARITY.md` | Verify all units at impl-complete or conformance-passed |
| 3 | All GS-* rows have proof artifacts | `docs/GUARANTEE_SUBSTITUTION_MATRIX.md` | Verify kernel rows mapped |
| 4 | Risk register has no unmitigated HIGH risks | `docs/RISK_REGISTER.md` | Verify all HIGH risks have CI gates |
| 5 | Semantic delta budget = 0 | Latest conformance run | Verify `semantic_delta_count == 0` |
| 6 | No unresolved proof-block exceptions | `docs/SEMANTIC_DELTA_EXCEPTIONS.json` | Verify all `status == "approved"` and within deadline |
| 7 | All mandatory gates pass | Latest CI manifest | Verify 9 mandatory + supplementary gates |
| 8 | Evidence dashboard shows no HIGH alerts | Latest dashboard JSON | Verify `release_readiness != "fail"` |
| 9 | Formal verification gates pass | `make formal-check` | Verify L2-L4 pass |
| 10 | ABI stability contract frozen | `make abi-check` | Verify 29/29 pass |
| 11 | Deployment playbooks reviewed | `docs/DEPLOYMENT_HARDENING.md` | Verify 3 scenario packs documented |
| 12 | Wave close evidence complete | `docs/WAVE_GATING_PROTOCOL.md` | Verify Wave A/B close packages |
