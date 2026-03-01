#!/usr/bin/env bash
# =============================================================================
# evaluate_slo_gates.sh — golden performance SLO gate evaluator (bd-66l.5)
#
# Compares benchmark results against per-profile SLO baselines and emits
# structured pass/fail reports with budget deltas and culprit identification.
#
# Usage:
#   tools/ci/evaluate_slo_gates.sh --bench-json <file> [--baselines <file>]
#       [--profile <name>] [--run-id <id>] [--strict] [--output <file>]
#
# Exit codes:
#   0: all SLO gates pass
#   1: one or more SLO gates violated
#   2: usage/configuration error
#
# SPDX-License-Identifier: MIT
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BENCH_JSON=""
BASELINES="${SCRIPT_DIR}/slo_baselines.json"
PROFILE=""
RUN_ID="${ASX_CI_RUN_TAG:-slo-$(date -u +%Y%m%dT%H%M%SZ)}"
STRICT=0
OUTPUT=""

usage() {
    cat <<'USAGE'
Usage: tools/ci/evaluate_slo_gates.sh [OPTIONS]

Required:
  --bench-json <file>     Benchmark JSON results file (from make bench-json)

Options:
  --baselines <file>      SLO baselines file (default: tools/ci/slo_baselines.json)
  --profile <name>        Override profile (default: read from bench JSON)
  --run-id <id>           Run identifier (default: ASX_CI_RUN_TAG or timestamp)
  --strict                Exit 1 on any SLO violation (default: always exit 0)
  --output <file>         Write gate report JSON to file (default: stdout)
  --help                  Show this help
USAGE
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --bench-json)
            [ $# -ge 2 ] || usage
            BENCH_JSON="$2"
            shift 2
            ;;
        --baselines)
            [ $# -ge 2 ] || usage
            BASELINES="$2"
            shift 2
            ;;
        --profile)
            [ $# -ge 2 ] || usage
            PROFILE="$2"
            shift 2
            ;;
        --run-id)
            [ $# -ge 2 ] || usage
            RUN_ID="$2"
            shift 2
            ;;
        --strict)
            STRICT=1
            shift
            ;;
        --output)
            [ $# -ge 2 ] || usage
            OUTPUT="$2"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo "[asx] slo-gate: ERROR — unknown option: $1" >&2
            usage
            ;;
    esac
done

# --- Validate inputs ---

if [ -z "$BENCH_JSON" ]; then
    echo "[asx] slo-gate: ERROR — --bench-json is required" >&2
    usage
fi

if [ ! -f "$BENCH_JSON" ]; then
    echo "[asx] slo-gate: ERROR — bench JSON not found: $BENCH_JSON" >&2
    exit 2
fi

if [ ! -f "$BASELINES" ]; then
    echo "[asx] slo-gate: ERROR — baselines file not found: $BASELINES" >&2
    exit 2
fi

# --- Detect profile ---

if [ -z "$PROFILE" ]; then
    PROFILE="$(jq -r '.profile // "CORE"' "$BENCH_JSON")"
fi

# --- Check profile exists in baselines ---

has_profile="$(jq -r --arg p "$PROFILE" '.profiles[$p] // empty' "$BASELINES")"
if [ -z "$has_profile" ]; then
    echo "[asx] slo-gate: WARN — profile '$PROFILE' not found in baselines, skipping gate" >&2
    # Emit pass report for unknown profiles (no baseline = no gate)
    report=$(jq -n \
        --arg schema "asx.slo_gate_report.v1" \
        --arg run_id "$RUN_ID" \
        --arg profile "$PROFILE" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            schema: $schema,
            run_id: $run_id,
            profile: $profile,
            generated_at: $ts,
            status: "skip",
            reason: "no baseline for profile",
            violations: [],
            passes: [],
            summary: { total: 0, passed: 0, failed: 0, skipped: 0 }
        }')
    if [ -n "$OUTPUT" ]; then
        echo "$report" > "$OUTPUT"
    else
        echo "$report"
    fi
    exit 0
fi

# --- Evaluate SLO gates ---

report=$(jq -n \
    --slurpfile bench "$BENCH_JSON" \
    --slurpfile base "$BASELINES" \
    --arg profile "$PROFILE" \
    --arg run_id "$RUN_ID" \
    --arg bench_file "$BENCH_JSON" \
    --arg baselines_file "$BASELINES" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
'
def check_upper(bench_name; metric_name; actual; budget_obj):
    {
        benchmark: bench_name,
        metric: metric_name,
        actual: actual,
        budget: budget_obj.budget,
        baseline: budget_obj.baseline,
        headroom: budget_obj.headroom,
        delta_vs_budget: (actual - budget_obj.budget),
        delta_vs_baseline: (actual - budget_obj.baseline),
        pct_of_budget: (if budget_obj.budget > 0 then ((actual / budget_obj.budget) * 100 | round) else 0 end),
        passed: (actual <= budget_obj.budget)
    };

def check_lower(bench_name; metric_name; actual; budget_obj):
    {
        benchmark: bench_name,
        metric: metric_name,
        actual: actual,
        budget: budget_obj.budget,
        baseline: budget_obj.baseline,
        headroom: budget_obj.headroom,
        delta_vs_budget: (budget_obj.budget - actual),
        delta_vs_baseline: (budget_obj.baseline - actual),
        pct_of_budget: (if budget_obj.budget > 0 then ((actual / budget_obj.budget) * 100 | round) else 0 end),
        passed: (actual >= budget_obj.budget)
    };

($bench[0]) as $b |
($base[0].profiles[$profile]) as $p |

# Check benchmark SLOs
[
    # For each benchmark in the baselines
    ($p.benchmarks // {} | to_entries[] | . as $bench_entry |
        $bench_entry.value | to_entries[] | . as $metric_entry |
        ($b.benchmarks[$bench_entry.key][$metric_entry.key] // null) as $actual |
        if $actual != null then
            check_upper($bench_entry.key; $metric_entry.key; $actual; $metric_entry.value)
        else
            empty
        end
    ),

    # Deadline report checks (upper bound)
    (if ($p.deadline_report // null) != null and ($b.deadline_report // null) != null then
        ($p.deadline_report | to_entries[] |
            . as $entry |
            ($b.deadline_report[$entry.key] // null) as $actual |
            if $actual != null then
                check_upper("deadline_report"; $entry.key; $actual; $entry.value)
            else
                empty
            end
        )
    else
        empty
    end),

    # Adaptive report checks
    (if ($p.adaptive_report // null) != null and ($b.adaptive_report // null) != null then
        ($p.adaptive_report | to_entries[] |
            . as $entry |
            (if $entry.key == "mean_confidence_fp32_floor" then
                ($b.adaptive_report.mean_confidence_fp32 // null)
            elif $entry.key == "fallback_rate" then
                ($b.adaptive_report.fallback_rate // null)
            else
                null
            end) as $actual |
            if $actual != null then
                if ($entry.value.direction // "upper") == "lower" then
                    check_lower("adaptive_report"; $entry.key; $actual; $entry.value)
                else
                    check_upper("adaptive_report"; $entry.key; $actual; $entry.value)
                end
            else
                empty
            end
        )
    else
        empty
    end)
] as $checks |

($checks | map(select(.passed)) | length) as $passed |
($checks | map(select(.passed | not)) | length) as $failed |

{
    schema: "asx.slo_gate_report.v1",
    run_id: $run_id,
    profile: $profile,
    generated_at: $ts,
    sources: {
        bench_json: $bench_file,
        baselines: $baselines_file
    },
    status: (if $failed > 0 then "fail" else "pass" end),
    summary: {
        total: ($checks | length),
        passed: $passed,
        failed: $failed,
        skipped: 0
    },
    violations: ($checks | map(select(.passed | not)) | sort_by(.delta_vs_budget) | reverse),
    passes: ($checks | map(select(.passed)) | sort_by(.pct_of_budget) | reverse),
    worst_offenders: ($checks | map(select(.passed | not)) | sort_by(.delta_vs_budget) | reverse | .[0:5]),
    rerun_command: "make bench-json > bench-results.json && tools/ci/evaluate_slo_gates.sh --bench-json bench-results.json --strict"
}
')

# --- Output report ---

if [ -n "$OUTPUT" ]; then
    mkdir -p "$(dirname "$OUTPUT")"
    echo "$report" > "$OUTPUT"
    echo "[asx] slo-gate: report written to $OUTPUT" >&2
else
    echo "$report"
fi

# --- Summary ---

status="$(echo "$report" | jq -r '.status')"
total="$(echo "$report" | jq -r '.summary.total')"
passed="$(echo "$report" | jq -r '.summary.passed')"
failed="$(echo "$report" | jq -r '.summary.failed')"

echo "[asx] slo-gate: status=$status total=$total passed=$passed failed=$failed profile=$PROFILE" >&2

if [ "$failed" -gt 0 ]; then
    echo "[asx] slo-gate: violations:" >&2
    echo "$report" | jq -r '.violations[] | "  - \(.benchmark)/\(.metric): actual=\(.actual) budget=\(.budget) delta=\(.delta_vs_budget)"' >&2
fi

# --- Exit code ---

if [ "$STRICT" = "1" ] && [ "$failed" -gt 0 ]; then
    echo "[asx] slo-gate: FAIL (strict mode, $failed violations)" >&2
    exit 1
fi

exit 0
