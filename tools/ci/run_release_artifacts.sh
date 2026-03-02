#!/usr/bin/env bash
# run_release_artifacts.sh — deterministic release artifact + integrity bundles (bd-56t.1)
#
# Produces:
#   - asx-<target>.tar.xz
#   - asx-<target>.tar.xz.sha256
#   - asx-<target>.tar.xz.sigstore.json
#   - asx-<target>.provenance.json
#
# Supports:
#   - binary package (libasx.a + public headers + docs)
#   - source package (tracked source snapshot)
#
# SPDX-License-Identifier: MIT

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

VERSION=""
TARGET=""
KIND="binary"
PROFILE="CORE"
CODEC="BIN"
DETERMINISTIC="1"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-}"
OUT_DIR="${REPO_ROOT}/build/release/dist"
MANIFEST_DIR="${REPO_ROOT}/build/release/manifests"
SKIP_BUILD=0
ASX_USE_RCH="${ASX_USE_RCH:-auto}"
ASX_ENABLE_SIGSTORE="${ASX_ENABLE_SIGSTORE:-0}"
ASX_RELEASE_TAG="${ASX_RELEASE_TAG:-}"

usage() {
    cat <<'USAGE'
Usage: tools/ci/run_release_artifacts.sh [options]

Required:
  --version <x.y.z>             Semantic version (without leading v)
  --target <id>                 Artifact target id (e.g. linux-x86_64, source)

Options:
  --kind <binary|source>        Artifact kind (default: binary)
  --profile <PROFILE>           Build profile for binary artifacts (default: CORE)
  --codec <CODEC>               Build codec for binary artifacts (default: BIN)
  --deterministic <0|1>         Deterministic build flag (default: 1)
  --source-date-epoch <secs>    Reproducible timestamp seed
  --out-dir <dir>               Output directory (default: build/release/dist)
  --manifest-dir <dir>          Manifest directory (default: build/release/manifests)
  --skip-build                  Reuse existing build outputs for binary artifacts
  -h, --help                    Show this help

Environment:
  ASX_USE_RCH=1|0|auto          Offload make build via rch when available
  ASX_ENABLE_SIGSTORE=1|0       Generate Sigstore bundle with cosign (default: 0)
  ASX_RELEASE_TAG=<tag>         Optional tag to record in provenance metadata
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --target) TARGET="$2"; shift 2 ;;
        --kind) KIND="$2"; shift 2 ;;
        --profile) PROFILE="$2"; shift 2 ;;
        --codec) CODEC="$2"; shift 2 ;;
        --deterministic) DETERMINISTIC="$2"; shift 2 ;;
        --source-date-epoch) SOURCE_DATE_EPOCH="$2"; shift 2 ;;
        --out-dir) OUT_DIR="$2"; shift 2 ;;
        --manifest-dir) MANIFEST_DIR="$2"; shift 2 ;;
        --skip-build) SKIP_BUILD=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage; exit 2 ;;
    esac
done

if [ -z "$VERSION" ] || [ -z "$TARGET" ]; then
    echo "missing required --version/--target arguments" >&2
    usage
    exit 2
fi

case "$KIND" in
    binary|source) ;;
    *) echo "invalid --kind: $KIND (expected binary|source)" >&2; exit 2 ;;
esac

if [ -z "$SOURCE_DATE_EPOCH" ]; then
    SOURCE_DATE_EPOCH="$(git -C "$REPO_ROOT" log -1 --format=%ct 2>/dev/null || date +%s)"
fi

run_make_cmd() {
    if [ "${ASX_USE_RCH}" = "1" ]; then
        if ! command -v rch >/dev/null 2>&1; then
            echo "ASX_USE_RCH=1 but rch is not available on PATH" >&2
            return 1
        fi
        rch exec -- make -C "$REPO_ROOT" "$@"
        return $?
    fi

    if [ "${ASX_USE_RCH}" = "0" ]; then
        make -C "$REPO_ROOT" "$@"
        return $?
    fi

    if command -v rch >/dev/null 2>&1; then
        rch exec -- make -C "$REPO_ROOT" "$@"
    else
        make -C "$REPO_ROOT" "$@"
    fi
}

sha256_file() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
        return
    fi
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
        return
    fi
    echo "missing sha256 tool (need sha256sum or shasum)" >&2
    return 1
}

write_sigstore_bundle() {
    local artifact_path="$1"
    local bundle_path="$2"
    local generated_at="$3"

    if [ "$ASX_ENABLE_SIGSTORE" != "1" ]; then
        jq -n \
            --arg status "skipped" \
            --arg reason "ASX_ENABLE_SIGSTORE!=1" \
            --arg artifact "$(basename "$artifact_path")" \
            --arg generated_at "$generated_at" \
            '{
              schema: "asx.sigstore.bundle.stub.v1",
              status: $status,
              reason: $reason,
              artifact: $artifact,
              generated_at: $generated_at
            }' >"$bundle_path"
        return 0
    fi

    if ! command -v cosign >/dev/null 2>&1; then
        echo "ASX_ENABLE_SIGSTORE=1 but cosign is not available on PATH" >&2
        return 1
    fi

    cosign sign-blob --yes --bundle "$bundle_path" "$artifact_path" >/dev/null
}

mkdir -p "$OUT_DIR" "$MANIFEST_DIR"

artifact_base="asx-${TARGET}"
archive_path="${OUT_DIR}/${artifact_base}.tar.xz"
sha_path="${archive_path}.sha256"
sigstore_path="${archive_path}.sigstore.json"
provenance_path="${OUT_DIR}/${artifact_base}.provenance.json"
manifest_path="${MANIFEST_DIR}/${artifact_base}.manifest.json"

generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
git_sha="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
git_ref="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
release_tag="$ASX_RELEASE_TAG"
if [ -z "$release_tag" ] && [ "${GITHUB_REF_TYPE:-}" = "tag" ]; then
    release_tag="${GITHUB_REF_NAME:-}"
fi

if [ "$KIND" = "binary" ]; then
    if [ "$SKIP_BUILD" != "1" ]; then
        run_make_cmd release PROFILE="$PROFILE" CODEC="$CODEC" DETERMINISTIC="$DETERMINISTIC"
    fi

    lib_path="${REPO_ROOT}/build/lib/libasx.a"
    if [ ! -f "$lib_path" ]; then
        echo "missing $lib_path (run build/release first or remove --skip-build)" >&2
        exit 1
    fi

    stage_root="${REPO_ROOT}/build/release/stage/${artifact_base}-${SOURCE_DATE_EPOCH}-$$"
    package_root="${stage_root}/${artifact_base}"
    mkdir -p "${package_root}/lib" "${package_root}/include"

    cp "$lib_path" "${package_root}/lib/libasx.a"
    cp -R "${REPO_ROOT}/include/asx" "${package_root}/include/"
    cp "${REPO_ROOT}/LICENSE" "${package_root}/LICENSE"
    cp "${REPO_ROOT}/README.md" "${package_root}/README.md"

    tar \
        --sort=name \
        --owner=0 \
        --group=0 \
        --numeric-owner \
        --mtime="@${SOURCE_DATE_EPOCH}" \
        -C "$stage_root" \
        -cJf "$archive_path" \
        "$artifact_base"
else
    mapfile -t tracked_files < <(git -C "$REPO_ROOT" ls-files)
    if [ "${#tracked_files[@]}" -eq 0 ]; then
        echo "no tracked files found for source package" >&2
        exit 1
    fi

    tar \
        --sort=name \
        --owner=0 \
        --group=0 \
        --numeric-owner \
        --mtime="@${SOURCE_DATE_EPOCH}" \
        -C "$REPO_ROOT" \
        --transform "s|^|${artifact_base}/|" \
        -cJf "$archive_path" \
        "${tracked_files[@]}"
fi

sha256_value="$(sha256_file "$archive_path")"
printf '%s  %s\n' "$sha256_value" "$(basename "$archive_path")" >"$sha_path"

write_sigstore_bundle "$archive_path" "$sigstore_path" "$generated_at"

jq -n \
    --arg schema "asx.release.artifact.v1" \
    --arg artifact "$(basename "$archive_path")" \
    --arg artifact_kind "$KIND" \
    --arg target "$TARGET" \
    --arg version "$VERSION" \
    --arg release_tag "$release_tag" \
    --arg git_sha "$git_sha" \
    --arg git_ref "$git_ref" \
    --arg profile "$PROFILE" \
    --arg codec "$CODEC" \
    --arg deterministic "$DETERMINISTIC" \
    --arg generated_at "$generated_at" \
    --arg sha256 "$sha256_value" \
    --arg sha_file "$(basename "$sha_path")" \
    --arg sigstore_file "$(basename "$sigstore_path")" \
    --argjson source_date_epoch "$SOURCE_DATE_EPOCH" \
    --arg asx_enable_sigstore "$ASX_ENABLE_SIGSTORE" \
    '{
      schema: $schema,
      artifact: $artifact,
      artifact_kind: $artifact_kind,
      target: $target,
      version: $version,
      release_tag: (if $release_tag == "" then null else $release_tag end),
      git: {sha: $git_sha, ref: $git_ref},
      build: {
        profile: $profile,
        codec: $codec,
        deterministic: ($deterministic == "1"),
        source_date_epoch: $source_date_epoch
      },
      integrity: {
        sha256: $sha256,
        sha256_file: $sha_file,
        sigstore_bundle: $sigstore_file,
        sigstore_requested: ($asx_enable_sigstore == "1")
      },
      generated_at: $generated_at
    }' >"$provenance_path"

jq -n \
    --arg lane "release-artifacts" \
    --arg status "pass" \
    --arg artifact "$(basename "$archive_path")" \
    --arg sha_file "$(basename "$sha_path")" \
    --arg sigstore_file "$(basename "$sigstore_path")" \
    --arg provenance_file "$(basename "$provenance_path")" \
    --arg target "$TARGET" \
    --arg version "$VERSION" \
    --arg kind "$KIND" \
    --arg generated_at "$generated_at" \
    '{
      lane: $lane,
      status: $status,
      target: $target,
      version: $version,
      kind: $kind,
      outputs: {
        artifact: $artifact,
        sha256: $sha_file,
        sigstore: $sigstore_file,
        provenance: $provenance_file
      },
      generated_at: $generated_at
    }' >"$manifest_path"

cat <<EOF
[asx] release-artifacts: created
artifact=${archive_path}
sha256=${sha_path}
sigstore=${sigstore_path}
provenance=${provenance_path}
manifest=${manifest_path}
EOF
