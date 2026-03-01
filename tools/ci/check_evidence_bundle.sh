#!/usr/bin/env bash
# =============================================================================
# check_evidence_bundle.sh — Evidence bundle completeness checker (bd-56t.3)
#
# Validates that all required evidence artifacts referenced in the
# evidence_bundle_manifest.json exist and that claim IDs are consistent.
#
# Usage:
#   tools/ci/check_evidence_bundle.sh [--strict] [--output <file>]
#
# Exit codes:
#   0: all checks pass
#   1: completeness violation (strict mode)
#   2: usage/config error
#
# SPDX-License-Identifier: MIT
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

STRICT=0
OUTPUT=""

usage() {
    cat <<'USAGE'
Usage: tools/ci/check_evidence_bundle.sh [OPTIONS]

Options:
  --strict    Exit 1 on missing artifacts (default: warn only)
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
        *) echo "[asx] evidence-bundle: ERROR — unknown option: $1" >&2; usage ;;
    esac
done

MANIFEST="$REPO_ROOT/schemas/evidence_bundle_manifest.json"

if [ ! -f "$MANIFEST" ]; then
    echo "[asx] evidence-bundle: ERROR — manifest not found: $MANIFEST" >&2
    exit 2
fi

# Check for jq
if ! command -v jq >/dev/null 2>&1; then
    echo "[asx] evidence-bundle: ERROR — jq required but not found" >&2
    exit 2
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/asx-evidence-bundle.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

passes="$tmp_dir/passes.txt"
violations="$tmp_dir/violations.txt"
warnings="$tmp_dir/warnings.txt"
: > "$passes"
: > "$violations"
: > "$warnings"

# --- Extract artifacts from manifest ---

artifact_count=0
ci_artifact_count=0

# Iterate over all sections and their artifacts
sections=$(jq -r '.sections | keys[]' "$MANIFEST")
for section in $sections; do
    artifacts=$(jq -r ".sections.\"$section\".artifacts | length" "$MANIFEST")
    for i in $(seq 0 $((artifacts - 1))); do
        claim_id=$(jq -r ".sections.\"$section\".artifacts[$i].id" "$MANIFEST")
        claim=$(jq -r ".sections.\"$section\".artifacts[$i].claim" "$MANIFEST")
        path=$(jq -r ".sections.\"$section\".artifacts[$i].path" "$MANIFEST")
        required=$(jq -r ".sections.\"$section\".artifacts[$i].required" "$MANIFEST")
        ci_artifact=$(jq -r ".sections.\"$section\".artifacts[$i].ci_artifact // false" "$MANIFEST")

        artifact_count=$((artifact_count + 1))

        if [ "$ci_artifact" = "true" ]; then
            ci_artifact_count=$((ci_artifact_count + 1))
            # CI artifacts are generated at build time — skip file existence check
            echo "evidence:${claim_id}:ci_artifact:skipped" >> "$passes"
            continue
        fi

        # Check if artifact path contains glob patterns
        case "$path" in
            *\**|*\?*)
                # Glob pattern — check if any matching files exist
                # shellcheck disable=SC2086
                matches=$(find "$REPO_ROOT" -path "$REPO_ROOT/$path" 2>/dev/null | head -1)
                if [ -n "$matches" ]; then
                    echo "evidence:${claim_id}:glob_match:found" >> "$passes"
                else
                    if [ "$required" = "true" ]; then
                        echo "evidence:${claim_id}:missing_glob:${path}" >> "$violations"
                    else
                        echo "evidence:${claim_id}:missing_glob:${path}" >> "$warnings"
                    fi
                fi
                ;;
            *)
                # Exact path
                if [ -f "$REPO_ROOT/$path" ]; then
                    echo "evidence:${claim_id}:exists:found" >> "$passes"
                elif [ -d "$REPO_ROOT/$path" ]; then
                    echo "evidence:${claim_id}:dir_exists:found" >> "$passes"
                else
                    if [ "$required" = "true" ]; then
                        echo "evidence:${claim_id}:missing:${path}" >> "$violations"
                    else
                        echo "evidence:${claim_id}:missing:${path}" >> "$warnings"
                    fi
                fi
                ;;
        esac
    done
done

# --- Cross-reference: verify standards mappings reference valid claim IDs ---

all_claim_ids=$(jq -r '[.sections[].artifacts[].id] | .[]' "$MANIFEST" | sort -u)

standards=$(jq -r '.standards_mappings | keys[]' "$MANIFEST")
for std in $standards; do
    mapping_key=$(jq -r "
        if .standards_mappings.\"$std\" | has(\"clause_mapping\") then \"clause_mapping\"
        elif .standards_mappings.\"$std\" | has(\"objective_mapping\") then \"objective_mapping\"
        else empty end
    " "$MANIFEST")

    if [ -z "$mapping_key" ]; then
        continue
    fi

    clauses=$(jq -r ".standards_mappings.\"$std\".\"$mapping_key\" | keys[]" "$MANIFEST")
    for clause in $clauses; do
        claims=$(jq -r ".standards_mappings.\"$std\".\"$mapping_key\".\"$clause\".claims[]" "$MANIFEST")
        for claim in $claims; do
            if echo "$all_claim_ids" | grep -qx "$claim"; then
                echo "xref:${std}:${clause}:${claim}:valid" >> "$passes"
            else
                echo "xref:${std}:${clause}:${claim}:dangling" >> "$violations"
            fi
        done
    done
done

# --- Build report ---

violation_count="$(wc -l < "$violations" | tr -d ' ')"
pass_count="$(wc -l < "$passes" | tr -d ' ')"
warning_count="$(wc -l < "$warnings" | tr -d ' ')"
total=$((violation_count + pass_count + warning_count))

status="pass"
if [ "$violation_count" -gt 0 ]; then
    status="fail"
fi

report_json="$tmp_dir/report.json"
{
    printf '{\n'
    printf '  "schema": "asx.evidence_bundle_report.v1",\n'
    printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "manifest": "schemas/evidence_bundle_manifest.json",\n'
    printf '  "status": "%s",\n' "$status"
    printf '  "summary": {\n'
    printf '    "total_artifacts": %d,\n' "$artifact_count"
    printf '    "ci_artifacts_skipped": %d,\n' "$ci_artifact_count"
    printf '    "total_checks": %d,\n' "$total"
    printf '    "passed": %d,\n' "$pass_count"
    printf '    "failed": %d,\n' "$violation_count"
    printf '    "warnings": %d\n' "$warning_count"
    printf '  },\n'

    printf '  "violations": [\n'
    first=1
    while IFS=':' read -r category claim_id kind detail; do
        [ -z "$category" ] && continue
        if [ "$first" -eq 0 ]; then printf ',\n'; fi
        printf '    {"category": "%s", "claim_id": "%s", "kind": "%s", "detail": "%s"}' \
            "$category" "$claim_id" "$kind" "$detail"
        first=0
    done < "$violations"
    printf '\n  ],\n'

    printf '  "warnings": [\n'
    first=1
    while IFS=':' read -r category claim_id kind detail; do
        [ -z "$category" ] && continue
        if [ "$first" -eq 0 ]; then printf ',\n'; fi
        printf '    {"category": "%s", "claim_id": "%s", "kind": "%s", "detail": "%s"}' \
            "$category" "$claim_id" "$kind" "$detail"
        first=0
    done < "$warnings"
    printf '\n  ],\n'

    printf '  "rerun_command": "tools/ci/check_evidence_bundle.sh --strict"\n'
    printf '}\n'
} > "$report_json"

# --- Output ---

if [ -n "$OUTPUT" ]; then
    mkdir -p "$(dirname "$OUTPUT")"
    cp "$report_json" "$OUTPUT"
    echo "[asx] evidence-bundle: report written to $OUTPUT" >&2
else
    cat "$report_json"
fi

# --- Summary ---

echo "[asx] evidence-bundle: status=$status total=$total passed=$pass_count failed=$violation_count warnings=$warning_count" >&2
echo "[asx] evidence-bundle: artifacts=$artifact_count ci_skipped=$ci_artifact_count" >&2

if [ "$violation_count" -gt 0 ]; then
    echo "[asx] evidence-bundle: MISSING EVIDENCE:" >&2
    while IFS=':' read -r category claim_id kind detail; do
        [ -z "$category" ] && continue
        echo "  - $claim_id: $kind ($detail)" >&2
    done < "$violations"
fi

if [ "$warning_count" -gt 0 ]; then
    echo "[asx] evidence-bundle: WARNINGS:" >&2
    while IFS=':' read -r category claim_id kind detail; do
        [ -z "$category" ] && continue
        echo "  - $claim_id: $kind ($detail)" >&2
    done < "$warnings"
fi

# --- Exit code ---

if [ "$STRICT" = "1" ] && [ "$violation_count" -gt 0 ]; then
    echo "[asx] evidence-bundle: FAIL (strict mode, $violation_count violations)" >&2
    exit 1
fi

exit 0
