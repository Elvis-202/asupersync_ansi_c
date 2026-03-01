#!/usr/bin/env bash
# wasm32_oracle_probe.sh — wasm32 determinism oracle build probe (bd-3vt.11)
#
# Evaluates which asx source files compile to wasm32-unknown-unknown
# using clang's built-in headers (no sysroot/wasi-sdk required for
# freestanding-compatible files).
#
# Usage: tools/ci/wasm32_oracle_probe.sh [--json]
#
# SPDX-License-Identifier: MIT

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CC="${CC:-clang}"
TARGET="wasm32-unknown-unknown"
CFLAGS="-std=c99 -Wall -Wextra -pedantic -Werror -I ${REPO_ROOT}/include"
JSON_MODE=0

if [[ "${1:-}" == "--json" ]]; then
    JSON_MODE=1
fi

# Check clang supports wasm32
if ! "$CC" --print-targets 2>/dev/null | grep -q "wasm32"; then
    echo "ERROR: $CC does not support wasm32 target" >&2
    exit 1
fi

PASS=0
FAIL=0
TOTAL=0
RESULTS=()

probe_file() {
    local f="$1"
    local base
    base="$(basename "$f" .c)"
    local tmpobj="/tmp/wasm32_probe_${base}.o"

    TOTAL=$((TOTAL + 1))
    local errout
    if errout=$("$CC" --target="$TARGET" $CFLAGS -c "$f" -o "$tmpobj" 2>&1); then
        PASS=$((PASS + 1))
        if [[ $JSON_MODE -eq 1 ]]; then
            RESULTS+=("{\"file\":\"$f\",\"status\":\"pass\",\"target\":\"$TARGET\"}")
        else
            printf "  %-50s OK\n" "$f"
        fi
        rm -f "$tmpobj"
        return 0
    else
        FAIL=$((FAIL + 1))
        local reason
        reason=$(echo "$errout" | grep "fatal error" | head -1 | sed 's/.*fatal error: //' | sed "s/'//g")
        if [[ $JSON_MODE -eq 1 ]]; then
            RESULTS+=("{\"file\":\"$f\",\"status\":\"fail\",\"target\":\"$TARGET\",\"reason\":\"$reason\"}")
        else
            printf "  %-50s FAIL: %s\n" "$f" "$reason"
        fi
        return 1
    fi
}

if [[ $JSON_MODE -eq 0 ]]; then
    echo "=== wasm32 determinism oracle build probe (bd-3vt.11) ==="
    echo "Compiler: $CC ($(${CC} --version 2>&1 | head -1))"
    echo "Target:   $TARGET"
    echo ""
fi

# Probe core files
if [[ $JSON_MODE -eq 0 ]]; then echo "--- Core ---"; fi
for f in "$REPO_ROOT"/src/core/*.c; do
    probe_file "$f" || true
done

# Probe runtime files (non-spike)
if [[ $JSON_MODE -eq 0 ]]; then echo "--- Runtime ---"; fi
for f in "$REPO_ROOT"/src/runtime/*.c; do
    case "$(basename "$f")" in
        *_spike.c) continue ;;  # skip spikes
    esac
    probe_file "$f" || true
done

# Probe channel files (non-spike)
if [[ $JSON_MODE -eq 0 ]]; then echo "--- Channel ---"; fi
for f in "$REPO_ROOT"/src/channel/*.c; do
    case "$(basename "$f")" in
        *_spike.c) continue ;;
    esac
    probe_file "$f" || true
done

if [[ $JSON_MODE -eq 1 ]]; then
    echo "{"
    echo "  \"probe\": \"wasm32_oracle\","
    echo "  \"target\": \"$TARGET\","
    echo "  \"compiler\": \"$CC\","
    echo "  \"total\": $TOTAL,"
    echo "  \"pass\": $PASS,"
    echo "  \"fail\": $FAIL,"
    echo "  \"pass_rate\": \"$(awk "BEGIN{printf \"%.1f\", ($PASS/$TOTAL)*100}")%\","
    echo "  \"results\": ["
    for i in "${!RESULTS[@]}"; do
        if [[ $i -lt $((${#RESULTS[@]}-1)) ]]; then
            echo "    ${RESULTS[$i]},"
        else
            echo "    ${RESULTS[$i]}"
        fi
    done
    echo "  ]"
    echo "}"
else
    echo ""
    echo "=== Summary: $PASS/$TOTAL pass ($FAIL fail) ==="
    if [[ $FAIL -gt 0 ]]; then
        echo "Note: Failed files require <string.h>/<stdlib.h>/<stdio.h>"
        echo "      Install wasi-sdk for full wasm32-wasi sysroot support."
    fi
fi
