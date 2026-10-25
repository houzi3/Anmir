#!/usr/bin/env bash
set -euo pipefail

# Modified for Anmir: write Finder metadata without automating Finder.
[[ $# = 3 ]] || { echo "Usage: $0 <app> <volume-name> <output.dmg>" >&2; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$1"
VOLUME_NAME="$2"
OUTPUT="$3"
[[ -d "$APP/Contents" ]] || { echo "Not an app bundle: $APP" >&2; exit 1; }
DMGBUILD="${DMGBUILD:-dmgbuild}"
command -v "$DMGBUILD" >/dev/null || {
    echo "Install dmgbuild 1.6.7 in a virtual environment; see doc/build-anmir.md" >&2
    exit 1
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/anmir-dmg.XXXXXX")"
MOUNT="$WORK/mount"
MOUNTED=false
cleanup() {
    if $MOUNTED && ! hdiutil detach "$MOUNT" >/dev/null; then
        echo "Could not eject $MOUNT; temporary image retained in $WORK" >&2
        return
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$MOUNT"
xcrun swift "$SCRIPT_DIR/macos-dmg-background.swift" "$WORK/install.png"
"$DMGBUILD" -s "$SCRIPT_DIR/macos-dmg-settings.py" \
    -D "app=$APP" -D "background=$WORK/install.png" \
    "$VOLUME_NAME" "$WORK/installer.dmg"
hdiutil verify "$WORK/installer.dmg" >/dev/null
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$MOUNT" \
    "$WORK/installer.dmg" >/dev/null
MOUNTED=true
[[ "$(readlink "$MOUNT/Applications")" = /Applications ]]
[[ -s "$MOUNT/.DS_Store" ]]
diff -qr "$APP" "$MOUNT/$(basename "$APP")" >/dev/null
if [[ -d "$APP/Contents/_CodeSignature" ]]; then
    codesign --verify --deep --strict "$MOUNT/$(basename "$APP")"
fi
hdiutil detach "$MOUNT" >/dev/null
MOUNTED=false
mv -f "$WORK/installer.dmg" "$OUTPUT"
echo "Created: $OUTPUT"
