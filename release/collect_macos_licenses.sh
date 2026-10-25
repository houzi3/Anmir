#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# = 1 ]] || { echo "Usage: $0 <output-directory>" >&2; exit 1; }
SOURCES="$ROOT/app/deps/work/sources"
OUTPUT="$1"
mkdir -p "$OUTPUT"
install -m 644 "$SOURCES/sdl-3.4.12/LICENSE.txt" "$OUTPUT/SDL-LICENSE.txt"
install -m 644 "$SOURCES/ffmpeg-8.1.2/LICENSE.md" "$OUTPUT/FFmpeg-LICENSE.md"
install -m 644 "$SOURCES/ffmpeg-8.1.2/COPYING.LGPLv2.1" "$OUTPUT/LGPL-2.1.txt"
install -m 644 "$SOURCES/dav1d-1.5.3/COPYING" "$OUTPUT/dav1d-COPYING.txt"
install -m 644 "$SOURCES/libusb-1.0.30/COPYING" "$OUTPUT/libusb-COPYING.txt"
mkdir -p "$OUTPUT/SDL-third-party"
for source in "$SOURCES/sdl-3.4.12/src/hidapi"/LICENSE*.txt; do
    install -m 644 "$source" "$OUTPUT/SDL-third-party/"
done
install -m 644 "$SOURCES/sdl-3.4.12/src/video/yuv2rgb/LICENSE" \
    "$OUTPUT/SDL-third-party/yuv2rgb-LICENSE.txt"
unzip -p "$SOURCES/platform-tools-37.0.0-darwin.zip" platform-tools/NOTICE.txt \
    > "$OUTPUT/Android-Platform-Tools-NOTICE.txt"
[[ -s "$OUTPUT/Android-Platform-Tools-NOTICE.txt" ]]
