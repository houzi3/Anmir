#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${1:-$ROOT/release/work/build-companion}"
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
cd "$ROOT"
# CI never receives the user's shared signing key. Sign the verified artifact locally.
ANMIR_UNSIGNED_BUILD=true ./gradlew :companion:assembleRelease :companion:lintRelease --console=plain
install -m 644 companion/build/outputs/apk/release/companion-release-unsigned.apk "$OUTPUT/AnmirConnect-unsigned.apk"
