#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${1:-$ROOT_DIR/dist}"
NOTES_FILE="${2:-}"

die() {
    echo "error: $*" >&2
    exit 1
}

command -v jq >/dev/null || die "jq is required to generate update.json"
[[ -d "$OUTPUT_DIR" ]] || die "directory not found: $OUTPUT_DIR"
if [[ -n "$NOTES_FILE" ]]; then
    [[ -f "$NOTES_FILE" ]] || die "release notes not found: $NOTES_FILE"
    NOTES="$(<"$NOTES_FILE")"
else
    NOTES="${RELEASE_NOTES:-}"
fi

VERSION="$(sed -n "s/^ *version: *'\([^']*\)'.*/\1/p" "$ROOT_DIR/meson.build" | head -n 1)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid project version: $VERSION"

checksum() {
    if command -v shasum >/dev/null; then
        shasum -a 256 "$1" | awk '{print $1}'
    elif command -v sha256sum >/dev/null; then
        sha256sum "$1" | awk '{print $1}'
    else
        die "shasum or sha256sum is required"
    fi
}

ARM_NAME="Anmir-$VERSION-arm64.zip"
INTEL_NAME="Anmir-$VERSION-x86_64.zip"
[[ -f "$OUTPUT_DIR/$ARM_NAME" ]] || die "missing update archive: $ARM_NAME"
[[ -f "$OUTPUT_DIR/$INTEL_NAME" ]] || die "missing update archive: $INTEL_NAME"
ARM_SHA256="$(checksum "$OUTPUT_DIR/$ARM_NAME")"
INTEL_SHA256="$(checksum "$OUTPUT_DIR/$INTEL_NAME")"

TEMP="$(mktemp "$OUTPUT_DIR/.update.json.XXXXXX")"
trap 'rm -f "$TEMP"' EXIT
jq -n \
    --argjson schema 1 \
    --arg version "$VERSION" \
    --arg notes "$NOTES" \
    --arg arm_name "$ARM_NAME" \
    --arg arm_sha256 "$ARM_SHA256" \
    --arg intel_name "$INTEL_NAME" \
    --arg intel_sha256 "$INTEL_SHA256" \
    '{schema:$schema, version:$version, notes:$notes, assets:{
        arm64:{name:$arm_name, sha256:$arm_sha256},
        x86_64:{name:$intel_name, sha256:$intel_sha256}
    }}' > "$TEMP"
mv -f "$TEMP" "$OUTPUT_DIR/update.json"
trap - EXIT
echo "Created: $OUTPUT_DIR/update.json"
