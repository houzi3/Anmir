#!/usr/bin/env bash
set -e

# Build a macOS .app bundle from a meson build directory or from a portable
# distribution directory (the content of a release archive).
#
# Usage: release/build_macos_app.sh [options] <build-dir|dist-dir>
#
# The resulting bundle can be opened from Finder/Launchpad, or copied to
# /Applications. A drag-to-Applications DMG is created by default.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Anmir"

usage() {
    cat <<EOF
Usage: $0 [options] <build-dir|dist-dir>

Build an Anmir.app bundle from:
 - a meson build directory (containing app/anmir), or
 - a portable distribution directory (containing anmir, adb and
   scrcpy-server, as in a release archive).

Options:
    -o, --output <dir>    Output directory (default: <project>/dist)
        --dmg             Create a drag-to-Applications disk image (default)
        --zip             Create a .zip archive instead (combine with --dmg for both)
        --app-only        Build only the .app bundle
        --adb <path>      Use this adb executable
        --server <path>   Use this scrcpy-server
        --companion <apk> Bundle the optional Anmir Connect phone companion
        --identity <id>   Code signing identity (default: \$CODESIGN_IDENTITY
                          or "-" for ad-hoc signing)
        --no-sign         Do not code sign the bundle
    -h, --help            Print this help

Examples:
    # Build a static release distribution first:
    release/build_macos.sh "\$(uname -m)"
    release/build_server.sh
    $0 release/work/build-macos-"\$(uname -m)"

    # Include a ZIP alongside the default disk image
    $0 --dmg --zip release/work/build-macos-"\$(uname -m)"
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

external_libraries() {
    otool -L "$1" |
        awk '$0 ~ /^\t/ { print $1 }' |
        while IFS= read -r lib; do
            case "$lib" in
                /System/Library/*|/usr/lib/*|@executable_path/*|@loader_path/*)
                    ;;
                *)
                    printf '%s ' "$lib"
                    ;;
            esac
        done
}

OUTPUT_DIR="$ROOT_DIR/dist"
CREATE_DMG=false
CREATE_ZIP=false
APP_ONLY=false
SIGN=true
IDENTITY="${CODESIGN_IDENTITY:--}"
ADB=""
SERVER=""
COMPANION=""
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
        --zip)
            CREATE_ZIP=true
            shift
            ;;
        --app-only)
            APP_ONLY=true
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
        --companion)
            [[ $# -ge 2 ]] || die "missing value for $1"
            COMPANION="$2"
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

if $APP_ONLY && { $CREATE_DMG || $CREATE_ZIP; }; then
    die "--app-only cannot be combined with --dmg or --zip"
fi
if ! $APP_ONLY && ! $CREATE_ZIP; then
    CREATE_DMG=true
fi

[[ -n "$SRC" ]] || { usage >&2; exit 1; }
[[ -d "$SRC" ]] || die "directory not found: $SRC"
SRC="$(cd "$SRC" && pwd)"

if [[ -x "$SRC/app/anmir" ]]; then
    MODE=build
    BIN="$SRC/app/anmir"
elif [[ -x "$SRC/anmir" ]]; then
    MODE=dist
    BIN="$SRC/anmir"
else
    die "no anmir executable found in $SRC (expected app/anmir or anmir)"
fi

VERSION="$(sed -n "s/^ *version: *'\([^']*\)'.*/\1/p" "$ROOT_DIR/meson.build" | head -n 1)"
[[ -n "$VERSION" ]] || die "could not read the project version from meson.build"

# A bundle uses the portable build: adb stays next to the executable, while
# the server and icons are resolved from Contents/Resources on macOS.
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

# The script only copies the executables, not third-party dylibs. Reject a
# dynamically linked build so that a successful package is actually portable.
for executable in "$BIN" "$ADB"; do
    external_lib_paths="$(external_libraries "$executable")"
    [[ -z "$external_lib_paths" ]] || die \
        "$executable depends on external libraries: $external_lib_paths
Build a static distribution with release/build_macos.sh first"
done

ARCH="$(lipo -archs "$BIN" 2>/dev/null || true)"
ARCH="${ARCH// /-}"
if [[ -z "$ARCH" ]]; then
    ARCH="$(uname -m)"
fi

APP="$OUTPUT_DIR/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

install -m 755 "$BIN" "$APP/Contents/MacOS/anmir"
install -m 755 "$ADB" "$APP/Contents/MacOS/adb"
install -m 644 "$SERVER" "$APP/Contents/Resources/scrcpy-server"
if [[ -n "$COMPANION" ]]; then
    [[ -f "$COMPANION" ]] || die "companion APK not found: $COMPANION"
    install -m 644 "$COMPANION" "$APP/Contents/Resources/AnmirConnect.apk"
fi
install -m 644 "$ROOT_DIR/NOTICE" "$ROOT_DIR/THIRD_PARTY.md" "$APP/Contents/Resources/"
if [[ -d "$SRC/licenses" ]]; then
    cp -R "$SRC/licenses" "$APP/Contents/Resources/"
else
    bash "$SCRIPT_DIR/collect_macos_licenses.sh" "$APP/Contents/Resources/licenses"
fi

copy_data() {
    local src="$1"
    local dst="$2"
    if [[ -e "$src" ]]; then
        cp -R "$src" "$dst/"
    fi
}

if [[ "$MODE" = dist ]]; then
    copy_data "$SRC/anmir.png" "$APP/Contents/Resources"
    copy_data "$SRC/disconnected.png" "$APP/Contents/Resources"
    copy_data "$SRC/toolbar-icons" "$APP/Contents/Resources"
    copy_data "$SRC/anmir.1" "$APP/Contents/Resources"
    copy_data "$SRC/LICENSE" "$APP/Contents/Resources"
else
    copy_data "$ROOT_DIR/app/data/anmir.png" "$APP/Contents/Resources"
    copy_data "$ROOT_DIR/app/data/disconnected.png" "$APP/Contents/Resources"
    copy_data "$ROOT_DIR/app/data/toolbar-icons" "$APP/Contents/Resources"
    copy_data "$ROOT_DIR/app/anmir.1" "$APP/Contents/Resources"
    copy_data "$ROOT_DIR/LICENSE" "$APP/Contents/Resources"
fi

install -m 644 "$ROOT_DIR/app/data/anmir.icns" "$APP/Contents/Resources/anmir.icns"
install -m 644 "$ROOT_DIR/app/data/anmir-dock.icns" "$APP/Contents/Resources/anmir-dock.icns"
install -m 644 "$ROOT_DIR/app/data/anmir-mirror.icns" "$APP/Contents/Resources/anmir-mirror.icns"
install -m 644 "$ROOT_DIR/app/data/anmir-mirror-bundle.icns" "$APP/Contents/Resources/anmir-mirror-bundle.icns"

# Language-specific resources are also copied into every mirror launcher.
for localization in "$ROOT_DIR"/app/data/locales/*.lproj; do
    copy_data "$localization" "$APP/Contents/Resources"
done

# Take the highest minimum OS version declared by any bundled architecture.
# Apple Silicon starts at macOS 11 even when the x86_64 deployment target is
# lower.
# The native application uses SF Symbols and unified toolbars (macOS 11+).
# Standalone CLI deployment targets can be older than the GUI bundle.
MINIMUM_SYSTEM_VERSION=11.0
BUILD_VERSIONS="$(vtool -show-build "$BIN" && vtool -show-build "$ADB")" \
    || die "could not inspect the bundled executables' minimum macOS versions"
while IFS= read -r binary_min_version; do
    [[ -n "$binary_min_version" ]] || continue
    if awk -v current="$MINIMUM_SYSTEM_VERSION" -v candidate="$binary_min_version" '
        function rank(version, parts) {
            split(version, parts, ".")
            return (parts[1] + 0) * 10000 + (parts[2] + 0) * 100 + (parts[3] + 0)
        }
        BEGIN {
            exit rank(candidate) > rank(current) ? 0 : 1
        }
    '; then
        MINIMUM_SYSTEM_VERSION="$binary_min_version"
    fi
done < <(printf '%s\n' "$BUILD_VERSIONS" |
    awk '$1 == "minos" { print $2 }')

# Finder contextual menus run in a separate extension process. Build the
# extension for every architecture carried by the host application, then
# embed it before signing the outer bundle.
FINDER_EXTENSION="$APP/Contents/PlugIns/AnmirFinder.appex"
FINDER_BUILD="$ROOT_DIR/release/work/finder-extension"
rm -rf "$FINDER_BUILD"
mkdir -p "$FINDER_BUILD" "$FINDER_EXTENSION/Contents/MacOS" \
    "$FINDER_EXTENSION/Contents/Resources"
FINDER_BINARIES=()
for extension_arch in $(lipo -archs "$BIN"); do
    extension_binary="$FINDER_BUILD/AnmirFinder-$extension_arch"
    xcrun clang -fobjc-arc -fmodules \
        -fmodules-cache-path="$FINDER_BUILD/module-cache" \
        -fapplication-extension -arch "$extension_arch" \
        -mmacosx-version-min="$MINIMUM_SYSTEM_VERSION" \
        -framework Cocoa -framework FinderSync \
        -Wl,-e,_NSExtensionMain \
        "$ROOT_DIR/app/src/sys/macos/finder_extension.m" \
        "$ROOT_DIR/app/src/sys/macos/finder_device_menu.m" \
        -o "$extension_binary"
    FINDER_BINARIES+=("$extension_binary")
done
if [[ ${#FINDER_BINARIES[@]} -eq 1 ]]; then
    install -m 755 "${FINDER_BINARIES[0]}" \
        "$FINDER_EXTENSION/Contents/MacOS/AnmirFinder"
else
    lipo -create "${FINDER_BINARIES[@]}" \
        -output "$FINDER_EXTENSION/Contents/MacOS/AnmirFinder"
fi
sed -e "s/@SCRCPY_VERSION@/$VERSION/g" \
    -e "s/@SCRCPY_MINIMUM_SYSTEM_VERSION@/$MINIMUM_SYSTEM_VERSION/g" \
    "$ROOT_DIR/app/FinderExtension-Info.plist.in" \
    > "$FINDER_EXTENSION/Contents/Info.plist"
for localization in "$ROOT_DIR"/app/data/locales/*.lproj; do
    cp -R "$localization" "$FINDER_EXTENSION/Contents/Resources/"
done

sed -e "s/@SCRCPY_VERSION@/$VERSION/g" \
    -e "s/@SCRCPY_MINIMUM_SYSTEM_VERSION@/$MINIMUM_SYSTEM_VERSION/g" \
    -e "s/@SCRCPY_APP_NAME@/$APP_NAME/g" \
    "$ROOT_DIR/app/Info.plist.in" \
    > "$APP/Contents/Info.plist"
cp "$ROOT_DIR/app/data/install-update.sh" "$APP/Contents/Resources/install-update.sh"
printf 'APPL????' > "$APP/Contents/PkgInfo"

SIGNING_STATUS="未签名，未经过 Apple 公证。"
if $SIGN; then
    if [[ "$IDENTITY" = "-" ]]; then
        SIGNING_STATUS="本地 ad-hoc 签名，未经过 Apple 公证。"
    else
        SIGNING_STATUS="证书签名，未经过 Apple 公证。"
    fi
fi
sed -e "s/@VERSION@/$VERSION/g" \
    -e "s/@ARCH@/$ARCH/g" \
    -e "s/@MINIMUM_SYSTEM_VERSION@/$MINIMUM_SYSTEM_VERSION/g" \
    -e "s/@SIGNING_STATUS@/$SIGNING_STATUS/g" \
    "$SCRIPT_DIR/macos-app-readme.txt" > "$APP/Contents/Resources/README.txt"
cp "$APP/Contents/Resources/README.txt" "$OUTPUT_DIR/README.txt"
for language in en zh-Hans zh-Hant; do
    localized_signing_status="$SIGNING_STATUS"
    if [[ "$language" = en ]]; then
        if ! $SIGN; then localized_signing_status="Unsigned; not notarized by Apple."
        elif [[ "$IDENTITY" = "-" ]]; then localized_signing_status="Local ad hoc signature; not notarized by Apple."
        else localized_signing_status="Certificate signature; not notarized by Apple."; fi
    elif [[ "$language" = zh-Hant ]]; then
        if ! $SIGN; then localized_signing_status="尚未簽署，未經 Apple 公證。"
        elif [[ "$IDENTITY" = "-" ]]; then localized_signing_status="本機 ad hoc 簽署，未經 Apple 公證。"
        else localized_signing_status="憑證簽署，未經 Apple 公證。"; fi
    fi
    template="$SCRIPT_DIR/macos-app-readme-$language.txt"
    if [[ "$language" = zh-Hans ]]; then
        template="$SCRIPT_DIR/macos-app-readme.txt"
    fi
    sed -e "s/@VERSION@/$VERSION/g" -e "s/@ARCH@/$ARCH/g" \
        -e "s/@MINIMUM_SYSTEM_VERSION@/$MINIMUM_SYSTEM_VERSION/g" \
        -e "s/@SIGNING_STATUS@/$localized_signing_status/g" \
        "$template" > "$APP/Contents/Resources/$language.lproj/README.txt"
done

if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$APP/Contents/Info.plist" >/dev/null
    plutil -lint "$FINDER_EXTENSION/Contents/Info.plist" >/dev/null
fi

if $SIGN; then
    SIGN_OPTIONS=()
    if [[ "$IDENTITY" != "-" ]]; then
        SIGN_OPTIONS=(--options runtime --timestamp)
    fi
    codesign --force "${SIGN_OPTIONS[@]}" --sign "$IDENTITY" \
        "$APP/Contents/MacOS/adb"
    codesign --force "${SIGN_OPTIONS[@]}" --sign "$IDENTITY" \
        --entitlements "$ROOT_DIR/app/FinderExtension.entitlements" \
        "$FINDER_EXTENSION"
    codesign --force "${SIGN_OPTIONS[@]}" --sign "$IDENTITY" "$APP"
    codesign --verify --deep --strict "$APP"
fi

echo "Created: $APP"
echo "Minimum macOS: $MINIMUM_SYSTEM_VERSION"

if $CREATE_ZIP; then
    ZIP="$OUTPUT_DIR/$APP_NAME-$VERSION-$ARCH.zip"
    rm -f "$ZIP"
    ZIP_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/anmir-zip.XXXXXX")"
    trap 'rm -rf "$ZIP_STAGE"' EXIT
    ditto "$APP" "$ZIP_STAGE/$APP_NAME.app"
    ln -s /System/Library/PreferencePanes/Security.prefPane \
        "$ZIP_STAGE/Privacy & Security"
    cp "$OUTPUT_DIR/README.txt" "$ZIP_STAGE/README.txt"
    ditto -c -k --norsrc --noextattr "$ZIP_STAGE" "$ZIP"
    if $SIGN; then
        ditto -x -k "$ZIP" "$ZIP_STAGE/verification"
        [[ "$(readlink "$ZIP_STAGE/verification/Privacy & Security")" = \
            /System/Library/PreferencePanes/Security.prefPane ]]
        codesign --verify --deep --strict \
            "$ZIP_STAGE/verification/$APP_NAME.app"
    fi
    rm -rf "$ZIP_STAGE"
    trap - EXIT
    echo "Created: $ZIP"
fi

if $CREATE_DMG; then
    DMG="$OUTPUT_DIR/$APP_NAME-$VERSION-$ARCH.dmg"
    bash "$SCRIPT_DIR/create_macos_dmg.sh" "$APP" "$APP_NAME $VERSION" "$DMG"
fi

if $CREATE_DMG || $CREATE_ZIP; then
    ARCHIVES=()
    for extension in dmg zip; do
        archive="$APP_NAME-$VERSION-$ARCH.$extension"
        if [[ -f "$OUTPUT_DIR/$archive" ]]; then
            ARCHIVES+=("$archive")
        fi
    done
    (cd "$OUTPUT_DIR" && shasum -a 256 "${ARCHIVES[@]}") \
        > "$OUTPUT_DIR/SHA256SUMS"
fi

if $CREATE_DMG; then
    cat <<EOF

Install:
    Open "$DMG" and drag $APP_NAME onto Applications.
    Then open $APP_NAME from Applications and eject the disk image.
EOF
else
cat <<EOF

Install and run:
    cp -R "$APP" /Applications/
    open "/Applications/$APP_NAME.app"

Or run it directly:
    open "$APP"
EOF
fi
