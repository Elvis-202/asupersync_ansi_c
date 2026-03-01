#!/usr/bin/env bash
# =============================================================================
# check_translation_validation.sh — Translation validation gate (bd-3vt.1)
#
# Validates C implementation against schemas/invariant_schema.json spec.
# Checks that C transition tables, enum ordinals, and state predicates
# match the machine-readable schema.
#
# Usage:
#   tools/ci/check_translation_validation.sh [--strict] [--output <file>]
#
# Exit codes:
#   0: all checks pass
#   1: translation mismatch detected (strict mode)
#   2: usage/build/tool error
#
# SPDX-License-Identifier: MIT
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

STRICT=0
OUTPUT=""
CC="${CC:-gcc}"

usage() {
    cat <<'USAGE'
Usage: tools/ci/check_translation_validation.sh [OPTIONS]

Options:
  --strict    Exit 1 on mismatch (default: warn only)
  --output    Write report JSON to file (default: stdout)
  --help      Show this help
USAGE
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --strict) STRICT=1; shift ;;
        --output) OUTPUT="$2"; shift 2 ;;
        --help|-h) usage ;;
        *) echo "[asx] tv-check: ERROR — unknown option: $1" >&2; usage ;;
    esac
done

# Check for jq
if ! command -v jq &>/dev/null; then
    echo "[asx] tv-check: ERROR — jq is required but not found" >&2
    exit 2
fi

SCHEMA="$REPO_ROOT/schemas/invariant_schema.json"
if [ ! -f "$SCHEMA" ]; then
    echo "[asx] tv-check: ERROR — schema not found: $SCHEMA" >&2
    exit 2
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/asx-tv-check.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

# --- Extract schema data with jq ---

# Region transitions
jq -r '.domains.region.legal_transitions[] | "\(.from):\(.to)"' \
    "$SCHEMA" > "$tmp_dir/region_legal.txt"

jq -r '.domains.region.forbidden_transitions[] | "\(.from):\(.to)"' \
    "$SCHEMA" > "$tmp_dir/region_forbidden.txt"

jq -r '.domains.region.states[] | "\(.id):\(.ordinal):\(.terminal)"' \
    "$SCHEMA" > "$tmp_dir/region_states.txt"

# Task transitions
jq -r '.domains.task.legal_transitions[] | "\(.from):\(.to)"' \
    "$SCHEMA" > "$tmp_dir/task_legal.txt"

jq -r '.domains.task.forbidden_transitions[] | "\(.from):\(.to)"' \
    "$SCHEMA" > "$tmp_dir/task_forbidden.txt"

jq -r '.domains.task.states[] | "\(.id):\(.ordinal):\(.terminal)"' \
    "$SCHEMA" > "$tmp_dir/task_states.txt"

# Obligation transitions
jq -r '.domains.obligation.legal_transitions[] | "\(.from):\(.to)"' \
    "$SCHEMA" > "$tmp_dir/obligation_legal.txt"

jq -r '.domains.obligation.forbidden_transitions[] | "\(.from):\(.to)"' \
    "$SCHEMA" > "$tmp_dir/obligation_forbidden.txt"

jq -r '.domains.obligation.states[] | "\(.id):\(.ordinal):\(.terminal)"' \
    "$SCHEMA" > "$tmp_dir/obligation_states.txt"

# --- Generate translation-validation probe ---

probe_src="$tmp_dir/tv_probe.c"
probe_bin="$tmp_dir/tv_probe"

cat > "$probe_src" <<'PROBE'
#include <stdio.h>
#include <asx/asx.h>

/* State name-to-ordinal maps */
static const char *region_names[] = {"Open", "Closing", "Draining", "Finalizing", "Closed"};
static const char *task_names[] = {"Created", "Running", "CancelRequested", "Cancelling", "Finalizing", "Completed"};
static const char *obligation_names[] = {"Reserved", "Committed", "Aborted", "Leaked"};

int main(void)
{
    unsigned f, t;

    /* Region state ordinals */
    printf("region_ordinal:Open=%d\n", (int)ASX_REGION_OPEN);
    printf("region_ordinal:Closing=%d\n", (int)ASX_REGION_CLOSING);
    printf("region_ordinal:Draining=%d\n", (int)ASX_REGION_DRAINING);
    printf("region_ordinal:Finalizing=%d\n", (int)ASX_REGION_FINALIZING);
    printf("region_ordinal:Closed=%d\n", (int)ASX_REGION_CLOSED);

    /* Region terminal predicates */
    for (f = 0; f <= 4; f++) {
        printf("region_terminal:%s=%d\n", region_names[f],
               asx_region_is_terminal((asx_region_state)f));
    }

    /* Region transitions */
    for (f = 0; f <= 4; f++) {
        for (t = 0; t <= 4; t++) {
            asx_status st = asx_region_transition_check(
                (asx_region_state)f, (asx_region_state)t);
            if (st == ASX_OK) {
                printf("region_legal:%s:%s\n", region_names[f], region_names[t]);
            }
        }
    }

    /* Task state ordinals */
    printf("task_ordinal:Created=%d\n", (int)ASX_TASK_CREATED);
    printf("task_ordinal:Running=%d\n", (int)ASX_TASK_RUNNING);
    printf("task_ordinal:CancelRequested=%d\n", (int)ASX_TASK_CANCEL_REQUESTED);
    printf("task_ordinal:Cancelling=%d\n", (int)ASX_TASK_CANCELLING);
    printf("task_ordinal:Finalizing=%d\n", (int)ASX_TASK_FINALIZING);
    printf("task_ordinal:Completed=%d\n", (int)ASX_TASK_COMPLETED);

    /* Task terminal predicates */
    for (f = 0; f <= 5; f++) {
        printf("task_terminal:%s=%d\n", task_names[f],
               asx_task_is_terminal((asx_task_state)f));
    }

    /* Task transitions */
    for (f = 0; f <= 5; f++) {
        for (t = 0; t <= 5; t++) {
            asx_status st = asx_task_transition_check(
                (asx_task_state)f, (asx_task_state)t);
            if (st == ASX_OK) {
                printf("task_legal:%s:%s\n", task_names[f], task_names[t]);
            }
        }
    }

    /* Obligation state ordinals */
    printf("obligation_ordinal:Reserved=%d\n", (int)ASX_OBLIGATION_RESERVED);
    printf("obligation_ordinal:Committed=%d\n", (int)ASX_OBLIGATION_COMMITTED);
    printf("obligation_ordinal:Aborted=%d\n", (int)ASX_OBLIGATION_ABORTED);
    printf("obligation_ordinal:Leaked=%d\n", (int)ASX_OBLIGATION_LEAKED);

    /* Obligation terminal predicates */
    for (f = 0; f <= 3; f++) {
        printf("obligation_terminal:%s=%d\n", obligation_names[f],
               asx_obligation_is_terminal((asx_obligation_state)f));
    }

    /* Obligation transitions */
    for (f = 0; f <= 3; f++) {
        for (t = 0; t <= 3; t++) {
            asx_status st = asx_obligation_transition_check(
                (asx_obligation_state)f, (asx_obligation_state)t);
            if (st == ASX_OK) {
                printf("obligation_legal:%s:%s\n", obligation_names[f], obligation_names[t]);
            }
        }
    }

    return 0;
}
PROBE

# --- Compile and run probe ---

if ! $CC -std=c99 -I"$REPO_ROOT/include" \
    -DASX_PROFILE_CORE -DASX_CODEC_JSON -DASX_DETERMINISTIC=1 \
    -o "$probe_bin" "$probe_src" \
    "$REPO_ROOT/src/core/transition_tables.c" 2>"$tmp_dir/compile.log"; then
    echo "[asx] tv-check: ERROR — probe compilation failed" >&2
    cat "$tmp_dir/compile.log" >&2
    exit 2
fi

probe_output="$tmp_dir/probe_output.txt"
"$probe_bin" > "$probe_output"

# --- Compare probe output against schema ---

violations="$tmp_dir/violations.txt"
passes="$tmp_dir/passes.txt"
: > "$violations"
: > "$passes"

check_ordinals() {
    local domain="$1"
    local states_file="$tmp_dir/${domain}_states.txt"

    while IFS=':' read -r name ordinal terminal; do
        actual="$(grep "^${domain}_ordinal:${name}=" "$probe_output" | cut -d= -f2)"
        if [ -z "$actual" ]; then
            echo "${domain}_ordinal:${name}:missing:${ordinal}:0" >> "$violations"
        elif [ "$actual" != "$ordinal" ]; then
            echo "${domain}_ordinal:${name}:changed:${ordinal}:${actual}" >> "$violations"
        else
            echo "${domain}_ordinal:${name}:${ordinal}" >> "$passes"
        fi
    done < "$states_file"
}

check_terminal_predicates() {
    local domain="$1"
    local states_file="$tmp_dir/${domain}_states.txt"

    while IFS=':' read -r name ordinal terminal; do
        expected_flag=0
        if [ "$terminal" = "true" ]; then expected_flag=1; fi

        actual="$(grep "^${domain}_terminal:${name}=" "$probe_output" | cut -d= -f2)"
        if [ -z "$actual" ]; then
            echo "${domain}_terminal:${name}:missing:${expected_flag}:0" >> "$violations"
        elif [ "$actual" != "$expected_flag" ]; then
            echo "${domain}_terminal:${name}:changed:${expected_flag}:${actual}" >> "$violations"
        else
            echo "${domain}_terminal:${name}:${expected_flag}" >> "$passes"
        fi
    done < "$states_file"
}

check_legal_transitions() {
    local domain="$1"
    local legal_file="$tmp_dir/${domain}_legal.txt"

    # Deduplicate schema transitions (multiple IDs for same from:to pair)
    sort -u "$legal_file" > "$tmp_dir/${domain}_legal_unique.txt"

    while IFS=':' read -r from to; do
        if grep -q "^${domain}_legal:${from}:${to}$" "$probe_output"; then
            echo "${domain}_legal:${from}->${to}:ok" >> "$passes"
        else
            echo "${domain}_legal:${from}->${to}:missing_in_code:legal:forbidden" >> "$violations"
        fi
    done < "$tmp_dir/${domain}_legal_unique.txt"
}

check_forbidden_transitions() {
    local domain="$1"
    local forbidden_file="$tmp_dir/${domain}_forbidden.txt"

    while IFS=':' read -r from to; do
        if grep -q "^${domain}_legal:${from}:${to}$" "$probe_output"; then
            echo "${domain}_forbidden:${from}->${to}:accepted_in_code:forbidden:legal" >> "$violations"
        else
            echo "${domain}_forbidden:${from}->${to}:ok" >> "$passes"
        fi
    done < "$forbidden_file"
}

# Run all checks for each domain
for domain in region task obligation; do
    check_ordinals "$domain"
    check_terminal_predicates "$domain"
    check_legal_transitions "$domain"
    check_forbidden_transitions "$domain"
done

violation_count="$(wc -l < "$violations" | tr -d ' ')"
pass_count="$(wc -l < "$passes" | tr -d ' ')"
total=$((violation_count + pass_count))

# --- Build report ---

status="pass"
if [ "$violation_count" -gt 0 ]; then
    status="fail"
fi

report_json="$tmp_dir/report.json"
{
    printf '{\n'
    printf '  "schema": "asx.translation_validation_report.v1",\n'
    printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "compiler": "%s",\n' "$CC"
    printf '  "schema_file": "schemas/invariant_schema.json",\n'
    printf '  "schema_version": "%s",\n' "$(jq -r '.version' "$SCHEMA")"
    printf '  "status": "%s",\n' "$status"
    printf '  "summary": {\n'
    printf '    "total": %d,\n' "$total"
    printf '    "passed": %d,\n' "$pass_count"
    printf '    "failed": %d,\n' "$violation_count"
    printf '    "domains_checked": ["region", "task", "obligation"],\n'
    printf '    "checks": ["ordinals", "terminal_predicates", "legal_transitions", "forbidden_transitions"]\n'
    printf '  },\n'

    printf '  "violations": [\n'
    first=1
    while IFS=':' read -r metric kind expected actual; do
        [ -z "$metric" ] && continue
        if [ "$first" -eq 0 ]; then printf ',\n'; fi
        printf '    {"metric": "%s", "kind": "%s", "expected": "%s", "actual": "%s"}' \
            "$metric" "$kind" "$expected" "$actual"
        first=0
    done < "$violations"
    printf '\n  ],\n'

    printf '  "rerun_command": "tools/ci/check_translation_validation.sh --strict"\n'
    printf '}\n'
} > "$report_json"

# --- Output ---

if [ -n "$OUTPUT" ]; then
    mkdir -p "$(dirname "$OUTPUT")"
    cp "$report_json" "$OUTPUT"
    echo "[asx] tv-check: report written to $OUTPUT" >&2
else
    cat "$report_json"
fi

# --- Summary ---

echo "[asx] tv-check: status=$status total=$total passed=$pass_count failed=$violation_count" >&2

if [ "$violation_count" -gt 0 ]; then
    echo "[asx] tv-check: TRANSLATION VALIDATION FAILURES:" >&2
    while IFS=':' read -r metric kind expected actual; do
        [ -z "$metric" ] && continue
        echo "  - $metric: $kind (expected=$expected actual=$actual)" >&2
    done < "$violations"
fi

# --- Exit code ---

if [ "$STRICT" = "1" ] && [ "$violation_count" -gt 0 ]; then
    echo "[asx] tv-check: FAIL (strict mode, $violation_count mismatches)" >&2
    exit 1
fi

exit 0
