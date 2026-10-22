#!/usr/bin/env bash
set -e

# Build a macOS .app bundle from a meson build directory or from a portable
# distribution directory (the content of a release archive).
#
# Usage: release/build_macos_app.sh [options] <build-dir|dist-dir>
#
# The resulting bundle can be opened from Finder/Launchpad, or copied to
# /Applications. Use --dmg to also generate a drag-and-drop disk image.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

usage() {
    cat <<EOF
Usage: $0 [options] <build-dir|dist-dir>

Build a scrcpy.app bundle from:
 - a meson build directory (containing app/scrcpy), or
 - a portable distribution directory (containing scrcpy, adb and
   scrcpy-server, as in a release archive).

Options:
    -o, --output <dir>    Output directory (default: <project>/dist)
        --dmg             Also create a .dmg disk image
        --adb <path>      Use this adb executable
        --server <path>   Use this scrcpy-server
        --identity <id>   Code signing identity (default: \$CODESIGN_IDENTITY
                          or "-" for ad-hoc signing)
        --no-sign         Do not code sign the bundle
    -h, --help            Print this help

Examples:
    # After: meson setup build-auto -Dportable=true && ninja -C build-auto
    $0 build-auto
    open dist/scrcpy.app

    # Build a distributable disk image
    $0 --dmg build-auto
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

OUTPUT_DIR="$ROOT_DIR/dist"
CREATE_DMG=false
SIGN=true
IDENTITY="${CODESIGN_IDENTITY:--}"
ADB=""
SERVER=""
SRC=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output)
            [[ $# -ge 2 ]] || die "missing value for $1"
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --dmg)
            CREATE_DMG=true
            shift
            ;;
        --adb)
            [[ $# -ge 2 ]] || die "missing value for $1"
            ADB="$2"
            shift 2
            ;;
        --server)
            [[ $# -ge 2 ]] || die "missing value for $1"
            SERVER="$2"
            shift 2
            ;;
        --identity)
            [[ $# -ge 2 ]] || die "missing value for $1"
            IDENTITY="$2"
            shift 2
            ;;
        --no-sign)
            SIGN=false
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            die "unknown option: $1"
            ;;
        *)
            [[ -z "$SRC" ]] || die "unexpected argument: $1"
            SRC="$1"
            shift
            ;;
    esac
done

[[ -n "$SRC" ]] || { usage >&2; exit 1; }
[[ -d "$SRC" ]] || die "directory not found: $SRC"
SRC="$(cd "$SRC" && pwd)"

if [[ -x "$SRC/app/scrcpy" ]]; then
    MODE=build
    BIN="$SRC/app/scrcpy"
elif [[ -x "$SRC/scrcpy" ]]; then
    MODE=dist
    BIN="$SRC/scrcpy"
else
    die "no scrcpy executable found in $SRC (expected app/scrcpy or scrcpy)"
fi

VERSION="$(sed -n "s/^ *version: *'\([^']*\)'.*/\1/p" "$ROOT_DIR/meson.build" | head -n 1)"
[[ -n "$VERSION" ]] || die "could not read the project version from meson.build"

# A bundle relies on the portable layout: scrcpy looks for scrcpy-server, adb
# and its icons next to the executable.
if [[ "$MODE" = build ]]; then
    CONFIG_H="$SRC/app/config.h"
    if [[ -f "$CONFIG_H" ]] && ! grep -q '^#define PORTABLE' "$CONFIG_H"; then
        die "the build is not portable; reconfigure with -Dportable=true"
    fi
fi

if [[ -z "$SERVER" ]]; then
    if [[ "$MODE" = dist ]]; then
        SERVER="$SRC/scrcpy-server"
    else
        for candidate in "$SRC/server/scrcpy-server" \
                         "$SRC/scrcpy-server" \
                         "$ROOT_DIR/scrcpy-server" \
                         "$ROOT_DIR/release/work/build-server/server/scrcpy-server"
        do
            if [[ -f "$candidate" ]]; then
                SERVER="$candidate"
                break
            fi
        done
    fi
fi
[[ -n "$SERVER" && -f "$SERVER" ]] \
    || die "scrcpy-server not found; build it or pass --server <path>"

if [[ -z "$ADB" ]]; then
    if [[ "$MODE" = dist ]]; then
        ADB="$SRC/adb"
    else
        ADB="$ROOT_DIR/app/deps/work/install/adb-macos/adb"
        if [[ ! -x "$ADB" ]]; then
            ADB="$(command -v adb || true)"
        fi
    fi
fi
[[ -n "$ADB" && -x "$ADB" ]] || die "adb not found; install it or pass --adb <path>"

ARCH="$(lipo -archs "$BIN" 2>/dev/null || true)"
ARCH="${ARCH// /-}"
if [[ -z "$ARCH" ]]; then
    ARCH="$(uname -m)"
fi

APP="$OUTPUT_DIR/scrcpy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

install -m 755 "$BIN" "$APP/Contents/MacOS/scrcpy"
install -m 755 "$ADB" "$APP/Contents/MacOS/adb"
install -m 644 "$SERVER" "$APP/Contents/MacOS/scrcpy-server"

copy_data() {
    local src="$1"
    local dst="$2"
    if [[ -e "$src" ]]; then
        cp -R "$src" "$dst/"
    fi
}

if [[ "$MODE" = dist ]]; then
    copy_data "$SRC/scrcpy.png" "$APP/Contents/MacOS"
    copy_data "$SRC/disconnected.png" "$APP/Contents/MacOS"
    copy_data "$SRC/toolbar-icons" "$APP/Contents/MacOS"
    copy_data "$SRC/scrcpy.1" "$APP/Contents/Resources"
    copy_data "$SRC/LICENSE" "$APP/Contents/Resources"
else
    copy_data "$ROOT_DIR/app/data/scrcpy.png" "$APP/Contents/MacOS"
    copy_data "$ROOT_DIR/app/data/disconnected.png" "$APP/Contents/MacOS"
    copy_data "$ROOT_DIR/app/data/toolbar-icons" "$APP/Contents/MacOS"
    copy_data "$ROOT_DIR/app/scrcpy.1" "$APP/Contents/Resources"
    copy_data "$ROOT_DIR/LICENSE" "$APP/Contents/Resources"
fi

install -m 644 "$ROOT_DIR/app/data/scrcpy.icns" "$APP/Contents/Resources/scrcpy.icns"

sed "s/@SCRCPY_VERSION@/$VERSION/g" "$ROOT_DIR/app/Info.plist.in" \
    > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$APP/Contents/Info.plist" >/dev/null
fi

if $SIGN; then
    if [[ "$IDENTITY" = "-" ]]; then
        codesign --force --deep --sign - "$APP"
    else
        codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" \
            "$APP"
    fi
    codesign --verify --deep --strict "$APP"
fi

echo "Created: $APP"

if $CREATE_DMG; then
    DMG="$OUTPUT_DIR/scrcpy-$VERSION-$ARCH.dmg"
    STAGE="$(mktemp -d "${TMPDIR:-/tmp}/scrcpy-dmg.XXXXXX")"
    trap 'rm -rf "$STAGE"' EXIT
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    rm -f "$DMG"
    hdiutil create -volname "scrcpy $VERSION" -srcfolder "$STAGE" \
        -ov -format UDZO "$DMG" >/dev/null
    rm -rf "$STAGE"
    trap - EXIT
    echo "Created: $DMG"
fi

cat <<EOF

Install and run:
    cp -R "$APP" /Applications/
    open "/Applications/scrcpy.app"

Or run it directly:
    open "$APP"
EOF
