#!/usr/bin/env bash
set -euo pipefail

# Finder owns .DS_Store: save the layout on the writable image, then preserve
# that volume while converting it to the read-only distributable image.
[[ $# = 3 ]] || { echo "Usage: $0 <app> <volume-name> <output.dmg>" >&2; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$1"
VOLUME_NAME="$2"
OUTPUT="$3"
APP_FILE="$(basename "$APP")"
[[ -d "$APP/Contents" ]] || { echo "Not an app bundle: $APP" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scrcpy-dmg.XXXXXX")"
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

mkdir -p "$WORK/stage/.background" "$MOUNT"
ditto "$APP" "$WORK/stage/$APP_FILE"
ln -s /Applications "$WORK/stage/Applications"
xcrun swift "$SCRIPT_DIR/macos-dmg-background.swift" \
    "$WORK/stage/.background/install.png"

# Leave room for HFS+ metadata and Finder's view settings.
SIZE_MB=$(( $(du -sm "$WORK/stage" | awk '{print $1}') + 32 ))
hdiutil create -size "${SIZE_MB}m" -fs HFS+ -volname "$VOLUME_NAME" \
    -srcfolder "$WORK/stage" -format UDRW "$WORK/writable.dmg" >/dev/null
hdiutil attach -nobrowse -noautoopen -mountpoint "$MOUNT" \
    "$WORK/writable.dmg" >/dev/null
MOUNTED=true

osascript - "$MOUNT" "$APP_FILE" <<'APPLESCRIPT'
on run argv
    set installationFolder to (POSIX file (item 1 of argv)) as alias
    set appFile to item 2 of argv
    tell application id "com.apple.finder"
        tell folder installationFolder
            open
            tell container window
                set current view to icon view
                set toolbar visible to false
                set statusbar visible to false
                set pathbar visible to false
                set bounds to {280, 180, 880, 548}
            end tell
            set viewOptions to icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 88
            set text size of viewOptions to 12
            set shows item info of viewOptions to false
            set label position of viewOptions to bottom
            set background picture of viewOptions to file ".background:install.png"
            set position of item appFile to {154, 170}
            set position of item "Applications" to {446, 170}
            update without registering applications
            delay 1
            close
        end tell
    end tell
end run
APPLESCRIPT

# Finder flushes view settings asynchronously when the window closes.
for ((attempt = 0; attempt < 50; attempt++)); do
    [[ ! -f "$MOUNT/.DS_Store" ]] || break
    sleep 0.1
done
[[ -s "$MOUNT/.DS_Store" ]] || { echo "Finder did not save the DMG layout" >&2; exit 1; }
sync
hdiutil detach "$MOUNT" >/dev/null
MOUNTED=false
hdiutil convert "$WORK/writable.dmg" -format UDZO \
    -imagekey zlib-level=9 -o "$WORK/installer.dmg" >/dev/null
hdiutil verify "$WORK/installer.dmg" >/dev/null

# Verify the final read-only image, not just the staging copy.
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$MOUNT" \
    "$WORK/installer.dmg" >/dev/null
MOUNTED=true
[[ "$(readlink "$MOUNT/Applications")" = /Applications ]]
[[ -s "$MOUNT/.DS_Store" && -s "$MOUNT/.background/install.png" ]]
diff -qr "$APP" "$MOUNT/$APP_FILE" >/dev/null
if [[ -d "$APP/Contents/_CodeSignature" ]]; then
    codesign --verify --deep --strict "$MOUNT/$APP_FILE"
fi
hdiutil detach "$MOUNT" >/dev/null
MOUNTED=false

# Replace an older installer only after the new image passes verification.
mv -f "$WORK/installer.dmg" "$OUTPUT"
echo "Created: $OUTPUT"
