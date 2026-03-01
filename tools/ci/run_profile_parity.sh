#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPORT_DIR="$SCRIPT_DIR/artifacts/conformance"
RUN_ID="profile-parity-$(date -u +%Y%m%dT%H%M%SZ)"

set +e
"$SCRIPT_DIR/run_conformance.sh" --mode profile-parity --strict --run-id "$RUN_ID" "$@"
rc=$?
set -e

SUMMARY_FILE="$REPORT_DIR/${RUN_ID}-profile-parity.summary.json"
if [[ ! -f "$SUMMARY_FILE" ]]; then
  exit "$rc"
fi

REPORT_FILE="$(jq -r '.report_file // ""' "$SUMMARY_FILE")"
DIFF_FILE="$(jq -r '.diff_file // ""' "$SUMMARY_FILE")"
fail_count="$(jq -r '.fail // 0' "$SUMMARY_FILE")"
comparable_parity_count="$(jq -r '.comparable_parity_records // 0' "$SUMMARY_FILE")"
BUILD_ROOT="${BUILD_DIR:-build}"

adapter_status="skip"
if [[ "$comparable_parity_count" -eq 0 ]]; then
  adapter_status="skip"
elif [[ "$fail_count" -eq 0 ]]; then
  adapter_status="pass"
else
  adapter_status="fail"
fi

profiles_json='[]'
compared_scenarios=0
if [[ -f "$REPORT_FILE" ]]; then
  profiles_json="$(jq -s \
    'map(select(.kind == "fixture" and .status != "skip" and (.profile // "") != "") | .profile) | unique' \
    "$REPORT_FILE")"
  compared_scenarios="$(jq -s \
    'map(select(.kind == "profile_parity" and .status != "skip")) | length' \
    "$REPORT_FILE")"
fi

if [[ "$BUILD_ROOT" = /* ]]; then
  ADAPTER_DIR="$BUILD_ROOT/conformance"
else
  ADAPTER_DIR="$REPO_ROOT/$BUILD_ROOT/conformance"
fi

mkdir -p "$ADAPTER_DIR"
ADAPTER_FILE="$ADAPTER_DIR/adapter_iso_${RUN_ID}.json"

jq -n \
  --arg run_id "$RUN_ID" \
  --arg status "$adapter_status" \
  --arg report_file "$REPORT_FILE" \
  --arg summary_file "$SUMMARY_FILE" \
  --arg diff_file "$DIFF_FILE" \
  --argjson profiles "$profiles_json" \
  --argjson compared_scenarios "$compared_scenarios" \
  --argjson comparable_parity_count "$comparable_parity_count" \
  --argjson fail_count "$fail_count" \
  '{
    kind: "adapter_isomorphism",
    run_id: $run_id,
    mode: "profile-parity",
    status: $status,
    adapter_isomorphism_pass: ($status == "pass"),
    compared_scenarios: $compared_scenarios,
    comparable_parity_records: $comparable_parity_count,
    fail_records: $fail_count,
    profiles: $profiles,
    evidence: {
      report_file: $report_file,
      summary_file: $summary_file,
      diff_file: $diff_file
    },
    diagnostic: (
      if $status == "pass" then
        "profile parity digests match across compared records"
      elif $status == "skip" then
        "no comparable profile parity records available"
      else
        "profile parity mismatches detected; see diff artifact report"
      end
    )
  }' >"$ADAPTER_FILE"

jq \
  --arg status "$adapter_status" \
  --arg artifact "$ADAPTER_FILE" \
  '. + {
    adapter_isomorphism_status: $status,
    adapter_isomorphism_pass: ($status == "pass"),
    adapter_isomorphism_artifact: $artifact
  }' \
  "$SUMMARY_FILE" >"${SUMMARY_FILE}.tmp"
mv "${SUMMARY_FILE}.tmp" "$SUMMARY_FILE"

echo "[asx] profile-parity: adapter_isomorphism_status=$adapter_status artifact=$ADAPTER_FILE" >&2
exit "$rc"
