#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${1:-$ROOT/release/output}"
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
VERSION="$(sed -n "s/^ *version: *'\([^']*\)'.*/\1/p" "$ROOT/meson.build" | head -n 1)"
NAME="Anmir-$VERSION-source"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/anmir-source.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
git -C "$ROOT" archive --format=tar --prefix="$NAME/" HEAD | tar -xf - -C "$WORK"
SOURCES="$WORK/$NAME/app/deps/work/sources"
mkdir -p "$SOURCES"
for archive in sdl-3.4.12.tar.gz ffmpeg-8.1.2.tar.xz dav1d-1.5.3.tar.gz libusb-1.0.30.tar.gz; do
    install -m 644 "$ROOT/app/deps/work/sources/$archive" "$SOURCES/"
done
git -C "$ROOT" rev-parse HEAD > "$WORK/$NAME/SOURCE_COMMIT"
tar -czf "$OUTPUT/$NAME.tar.gz" -C "$WORK" "$NAME"
echo "Created: $OUTPUT/$NAME.tar.gz"
