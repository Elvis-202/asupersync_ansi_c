#!/usr/bin/env bash
# =============================================================================
# generate_traceability_index.sh — machine-readable traceability export (bd-3gn)
#
# Parses the three canonical traceability documents and the beads JSONL to
# produce a consolidated traceability_index.json.  CI can then validate link
# completeness, orphan detection, and coverage audits automatically.
#
# Inputs (auto-discovered):
#   - docs/PLAN_EXECUTION_TRACEABILITY_INDEX.md  (trace IDs)
#   - docs/FEATURE_PARITY.md                      (semantic units)
#   - docs/SOURCE_TO_FIXTURE_PROVENANCE_MAP.md    (provenance mappings)
#   - docs/QUALITY_GATES.md                        (gate registry)
#   - .beads/issues.jsonl                          (bead graph)
#
# Output:
#   - build/traceability/traceability_index.json
#   - (optional) tools/ci/artifacts/traceability/traceability_index_<run_id>.json
#
# Exit codes:
#   0: export generated successfully
#   1: validation warnings (missing links)
#   2: usage/config error
#
# SPDX-License-Identifier: MIT
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

RUN_ID="${ASX_CI_RUN_TAG:-trace-$(date -u +%Y%m%dT%H%M%SZ)}"
GENERATED_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

OUT_DIR="$REPO_ROOT/build/traceability"
ARTIFACT_DIR="$REPO_ROOT/tools/ci/artifacts/traceability"
STRICT=0

usage() {
    cat <<'USAGE'
Usage: tools/ci/generate_traceability_index.sh [OPTIONS]

Options:
  --run-id <id>    Override run id (default: ASX_CI_RUN_TAG or timestamp)
  --out-dir <dir>  Output directory (default: build/traceability)
  --strict         Exit 1 on validation warnings
  -h, --help       Show this help
USAGE
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --run-id)    RUN_ID="$2"; shift 2 ;;
        --out-dir)   OUT_DIR="$2"; shift 2 ;;
        --strict)    STRICT=1; shift ;;
        -h|--help)   usage ;;
        *)           echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

mkdir -p "$OUT_DIR" "$ARTIFACT_DIR"

TRACEABILITY_MD="$REPO_ROOT/docs/PLAN_EXECUTION_TRACEABILITY_INDEX.md"
PARITY_MD="$REPO_ROOT/docs/FEATURE_PARITY.md"
PROVENANCE_MD="$REPO_ROOT/docs/SOURCE_TO_FIXTURE_PROVENANCE_MAP.md"
GATES_MD="$REPO_ROOT/docs/QUALITY_GATES.md"
BEADS_JSONL="$REPO_ROOT/.beads/issues.jsonl"

# Validate inputs exist
for f in "$TRACEABILITY_MD" "$PARITY_MD" "$PROVENANCE_MD" "$GATES_MD"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: Required input missing: $f" >&2
        exit 2
    fi
done

WARNINGS=0
OUT_FILE="$OUT_DIR/traceability_index.json"

# ---- Helper: escape JSON string ----
json_str() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g'
}

# ---- 1. Parse trace IDs from PLAN_EXECUTION_TRACEABILITY_INDEX.md ----
# Format: | `TRC-XXX-NNN` | theme | bead(s) | surface | artifact(s) | status |

parse_trace_ids() {
    local line trace_id theme beads surface artifacts status
    grep -E '^\| `TRC-' "$TRACEABILITY_MD" | while IFS='|' read -r _ trace_id theme beads surface artifacts status _; do
        trace_id="$(echo "$trace_id" | sed 's/`//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        theme="$(echo "$theme" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        beads="$(echo "$beads" | sed 's/`//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        surface="$(echo "$surface" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        artifacts="$(echo "$artifacts" | sed 's/`//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        status="$(echo "$status" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

        # Split beads by comma
        bead_arr=""
        for b in $(echo "$beads" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'); do
            [ -n "$b" ] || continue
            [ -n "$bead_arr" ] && bead_arr="$bead_arr,"
            bead_arr="$bead_arr\"$(json_str "$b")\""
        done

        # Split artifacts by comma
        art_arr=""
        for a in $(echo "$artifacts" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'); do
            [ -n "$a" ] || continue
            [ -n "$art_arr" ] && art_arr="$art_arr,"
            art_arr="$art_arr\"$(json_str "$a")\""
        done

        printf '{"trace_id":"%s","theme":"%s","beads":[%s],"verification_surface":"%s","artifacts":[%s],"status":"%s"}' \
            "$(json_str "$trace_id")" \
            "$(json_str "$theme")" \
            "$bead_arr" \
            "$(json_str "$surface")" \
            "$art_arr" \
            "$(json_str "$status")"
        printf '\n'
    done
}

# ---- 2. Parse semantic units from FEATURE_PARITY.md ----
# Format: | `U-XXX` | name | source | acceptance | must-fail | status | bead(s) |

parse_semantic_units() {
    grep -E '^\| `U-' "$PARITY_MD" | while IFS='|' read -r _ unit_id name source accept mustfail status beads _; do
        unit_id="$(echo "$unit_id" | sed 's/`//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        name="$(echo "$name" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        source="$(echo "$source" | sed 's/`//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        accept="$(echo "$accept" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        mustfail="$(echo "$mustfail" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        status="$(echo "$status" | sed 's/`//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        beads="$(echo "$beads" | sed 's/`//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"

        # Split source artifacts
        src_arr=""
        for s in $(echo "$source" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'); do
            [ -n "$s" ] || continue
            [ -n "$src_arr" ] && src_arr="$src_arr,"
            src_arr="$src_arr\"$(json_str "$s")\""
        done

        # Split beads
        bead_arr=""
        for b in $(echo "$beads" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'); do
            [ -n "$b" ] || continue
            [ -n "$bead_arr" ] && bead_arr="$bead_arr,"
            bead_arr="$bead_arr\"$(json_str "$b")\""
        done

        printf '{"unit_id":"%s","semantic_unit":"%s","source_artifacts":[%s],"acceptance_obligations":"%s","must_fail_obligations":"%s","status":"%s","impl_beads":[%s]}' \
            "$(json_str "$unit_id")" \
            "$(json_str "$name")" \
            "$src_arr" \
            "$(json_str "$accept")" \
            "$(json_str "$mustfail")" \
            "$(json_str "$status")" \
            "$bead_arr"
        printf '\n'
    done
}

# ---- 3. Parse provenance mappings from SOURCE_TO_FIXTURE_PROVENANCE_MAP.md ----
# Format: | `PROV-ID` | unit | source | fixture_links | parity_targets | test_obligations | status |

parse_provenance() {
    grep -E '^\| `[A-Z]+-[0-9]+`' "$PROVENANCE_MD" | while IFS='|' read -r _ prov_id unit source fixtures parity tests status _; do
        prov_id="$(echo "$prov_id" | sed 's/`//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        unit="$(echo "$unit" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        source="$(echo "$source" | sed 's/`//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        fixtures="$(echo "$fixtures" | sed 's/`//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        parity="$(echo "$parity" | sed 's/`//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        tests="$(echo "$tests" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        status="$(echo "$status" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

        # Split parity targets
        par_arr=""
        for p in $(echo "$parity" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'); do
            [ -n "$p" ] || continue
            [ -n "$par_arr" ] && par_arr="$par_arr,"
            par_arr="$par_arr\"$(json_str "$p")\""
        done

        # Split test obligations
        test_arr=""
        for t in $(echo "$tests" | sed 's/ + /\n/g'); do
            t="$(echo "$t" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
            [ -n "$t" ] || continue
            [ -n "$test_arr" ] && test_arr="$test_arr,"
            test_arr="$test_arr\"$(json_str "$t")\""
        done

        printf '{"prov_id":"%s","semantic_unit":"%s","source_provenance":"%s","fixture_links":"%s","parity_targets":[%s],"test_obligations":[%s],"status":"%s"}' \
            "$(json_str "$prov_id")" \
            "$(json_str "$unit")" \
            "$(json_str "$source")" \
            "$(json_str "$fixtures")" \
            "$par_arr" \
            "$test_arr" \
            "$(json_str "$status")"
        printf '\n'
    done
}

# ---- 4. Parse gates from QUALITY_GATES.md ----

parse_gates() {
    local gate_id plan_ref targets ci_job scripts artifacts pass_criteria
    local in_gate=0 current_gate=""

    # Extract mandatory gates (sections 1.1-1.10)
    grep -E '^\| \*\*Gate ID\*\*|^\| \*\*Plan ref\*\*|^\| \*\*Makefile targets\*\*|^\| \*\*CI job\*\*|^\| \*\*Pass criteria\*\*' "$GATES_MD" | while read -r line; do
        if echo "$line" | grep -q 'Gate ID'; then
            gate_id="$(echo "$line" | sed 's/.*`\(GATE-[^`]*\)`.*/\1/')"
        elif echo "$line" | grep -q 'Plan ref'; then
            plan_ref="$(echo "$line" | sed 's/.*| *\(.*\) *|$/\1/; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        elif echo "$line" | grep -q 'Makefile targets'; then
            targets="$(echo "$line" | sed 's/.*| *`\{0,1\}\(.*\)`\{0,1\} *|$/\1/; s/`//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        elif echo "$line" | grep -q 'CI job'; then
            ci_job="$(echo "$line" | sed 's/.*| *`\{0,1\}\(.*\)`\{0,1\} *|$/\1/; s/`//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        elif echo "$line" | grep -q 'Pass criteria'; then
            pass_criteria="$(echo "$line" | sed 's/.*| *\(.*\) *|$/\1/; s/^[[:space:]]*//; s/[[:space:]]*$//')"

            # Emit accumulated gate
            if [ -n "$gate_id" ]; then
                printf '{"gate_id":"%s","plan_ref":"%s","makefile_targets":"%s","ci_job":"%s","pass_criteria":"%s","blocking":true}' \
                    "$(json_str "$gate_id")" \
                    "$(json_str "$plan_ref")" \
                    "$(json_str "$targets")" \
                    "$(json_str "$ci_job")" \
                    "$(json_str "$pass_criteria")"
                printf '\n'
            fi
            gate_id="" plan_ref="" targets="" ci_job="" pass_criteria=""
        fi
    done

    # Extract supplementary gates (section 2 table, exclude E2E which are parsed separately)
    grep -E '^\| `GATE-' "$GATES_MD" | grep -v 'Gate ID' | grep -v 'GATE-E2E-' | while IFS='|' read -r _ gid target job script purpose _; do
        gid="$(echo "$gid" | sed 's/`//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        target="$(echo "$target" | sed 's/`//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        job="$(echo "$job" | sed 's/`//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        purpose="$(echo "$purpose" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

        printf '{"gate_id":"%s","makefile_targets":"%s","ci_job":"%s","pass_criteria":"%s","blocking":true}' \
            "$(json_str "$gid")" \
            "$(json_str "$target")" \
            "$(json_str "$job")" \
            "$(json_str "$purpose")"
        printf '\n'
    done

    # Extract E2E gates (section 3 table)
    grep -E '^\| `GATE-E2E-' "$GATES_MD" | while IFS='|' read -r _ gid scripts profile _; do
        gid="$(echo "$gid" | sed 's/`//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        scripts="$(echo "$scripts" | sed 's/`//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        profile="$(echo "$profile" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

        printf '{"gate_id":"%s","scripts":"%s","profile":"%s","blocking":true}' \
            "$(json_str "$gid")" \
            "$(json_str "$scripts")" \
            "$(json_str "$profile")"
        printf '\n'
    done
}

# ---- 5. Bead summary from JSONL ----

parse_beads_summary() {
    if [ ! -f "$BEADS_JSONL" ]; then
        echo '{"total":0,"closed":0,"open":0,"in_progress":0}'
        return
    fi

    local total closed open in_progress
    total="$(wc -l < "$BEADS_JSONL" | tr -d ' ')"
    closed="$(grep -c '"status":"closed"' "$BEADS_JSONL" || true)"
    open="$(grep -c '"status":"open"' "$BEADS_JSONL" || true)"
    in_progress="$(grep -c '"status":"in_progress"' "$BEADS_JSONL" || true)"

    printf '{"total":%d,"closed":%d,"open":%d,"in_progress":%d}' \
        "$total" "$closed" "$open" "$in_progress"
}

# ---- 6. Test/gate family index ----

parse_test_families() {
    grep -E '^\| `TG-' "$TRACEABILITY_MD" | while IFS='|' read -r _ fid scope commands _; do
        fid="$(echo "$fid" | sed 's/`//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        scope="$(echo "$scope" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        commands="$(echo "$commands" | sed 's/`//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"

        printf '{"family_id":"%s","scope":"%s","commands":"%s"}' \
            "$(json_str "$fid")" \
            "$(json_str "$scope")" \
            "$(json_str "$commands")"
        printf '\n'
    done
}

# ---- Assemble JSON ----

echo "[traceability] Parsing trace IDs..."
TRACE_IDS="$(parse_trace_ids | paste -sd ',' -)"
TRACE_COUNT="$(echo "$TRACE_IDS" | tr ',' '\n' | grep -c '{' || true)"

echo "[traceability] Parsing semantic units..."
UNITS="$(parse_semantic_units | paste -sd ',' -)"
UNIT_COUNT="$(echo "$UNITS" | tr ',' '\n' | grep -c '{' || true)"

echo "[traceability] Parsing provenance mappings..."
PROV="$(parse_provenance | paste -sd ',' -)"
PROV_COUNT="$(echo "$PROV" | tr ',' '\n' | grep -c '{' || true)"

echo "[traceability] Parsing gates..."
GATES="$(parse_gates | paste -sd ',' -)"
GATE_COUNT="$(echo "$GATES" | tr ',' '\n' | grep -c '{' || true)"

echo "[traceability] Parsing test families..."
FAMILIES="$(parse_test_families | paste -sd ',' -)"

echo "[traceability] Parsing bead summary..."
BEAD_SUMMARY="$(parse_beads_summary)"

# Count semantic units by status
IMPL_COMPLETE="$(echo "$UNITS" | grep -o '"status":"impl-complete"' | wc -l || true)"
SPEC_REVIEWED="$(echo "$UNITS" | grep -o '"status":"spec-reviewed"' | wc -l || true)"

# ---- Validation ----

# Check all trace IDs have at least one bead
ORPHAN_TRACES=0
for tid in $(echo "$TRACE_IDS" | grep -o '"trace_id":"[^"]*"' | sed 's/"trace_id":"//; s/"//'); do
    beads_for_tid="$(echo "$TRACE_IDS" | grep -o "\"trace_id\":\"$tid\"[^}]*" | grep -o '"beads":\[[^]]*\]')"
    if echo "$beads_for_tid" | grep -q '\[\]'; then
        echo "  WARNING: Trace ID $tid has no linked beads" >&2
        ORPHAN_TRACES=$((ORPHAN_TRACES + 1))
        WARNINGS=$((WARNINGS + 1))
    fi
done

# ---- Write output ----

cat > "$OUT_FILE" <<ENDJSON
{
  "schema": "asx.traceability_index.v1",
  "generated_at": "$GENERATED_TS",
  "run_id": "$RUN_ID",
  "generator": "tools/ci/generate_traceability_index.sh",
  "sources": {
    "traceability_md": "docs/PLAN_EXECUTION_TRACEABILITY_INDEX.md",
    "feature_parity_md": "docs/FEATURE_PARITY.md",
    "provenance_map_md": "docs/SOURCE_TO_FIXTURE_PROVENANCE_MAP.md",
    "quality_gates_md": "docs/QUALITY_GATES.md",
    "beads_jsonl": ".beads/issues.jsonl"
  },
  "summary": {
    "trace_ids": $TRACE_COUNT,
    "semantic_units": $UNIT_COUNT,
    "semantic_units_impl_complete": $IMPL_COMPLETE,
    "semantic_units_spec_reviewed": $SPEC_REVIEWED,
    "provenance_mappings": $PROV_COUNT,
    "gates": $GATE_COUNT,
    "beads": $BEAD_SUMMARY,
    "validation_warnings": $WARNINGS,
    "orphan_trace_ids": $ORPHAN_TRACES
  },
  "trace_ids": [$TRACE_IDS],
  "semantic_units": [$UNITS],
  "provenance_mappings": [$PROV],
  "gates": [$GATES],
  "test_families": [$FAMILIES]
}
ENDJSON

# Copy to artifact dir
cp "$OUT_FILE" "$ARTIFACT_DIR/traceability_index_${RUN_ID}.json"

echo "[traceability] Generated: $OUT_FILE"
echo "[traceability] Artifact:  $ARTIFACT_DIR/traceability_index_${RUN_ID}.json"
echo "[traceability] Summary: ${TRACE_COUNT} trace IDs, ${UNIT_COUNT} semantic units, ${PROV_COUNT} provenance mappings, ${GATE_COUNT} gates"

if [ "$WARNINGS" -gt 0 ]; then
    echo "[traceability] WARNING: $WARNINGS validation warnings detected"
    if [ "$STRICT" -eq 1 ]; then
        exit 1
    fi
fi

exit 0
