#!/bin/bash
# Modified for Anmir; see NOTICE for downstream changes.
set -ex
cd "$(dirname ${BASH_SOURCE[0]})"
. build_common
cd .. # root project dir

if [[ $# != 1 ]]
then
    echo "Syntax: $0 <arch>" >&2
    exit 1
fi

ARCH="$1"
[[ "$ARCH" != aarch64 ]] || ARCH=arm64
[[ "$ARCH" = arm64 || "$ARCH" = x86_64 ]] || {
    echo "Unsupported macOS architecture: $ARCH" >&2; exit 1;
}
[[ "$(uname -m)" = "$ARCH" ]] || {
    echo "Build $ARCH on a native $ARCH runner; this script does not cross-compile." >&2
    exit 1
}
MACOS_BUILD_DIR="$WORK_DIR/build-macos-$ARCH"

export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"

app/deps/adb_macos.sh
app/deps/sdl.sh macos native static
app/deps/dav1d.sh macos native static
app/deps/ffmpeg.sh macos native static
app/deps/libusb.sh macos native static

DEPS_INSTALL_DIR="$PWD/app/deps/work/install/macos-native-static"
ADB_INSTALL_DIR="$PWD/app/deps/work/install/adb-macos"

# Never fall back to system libs
unset PKG_CONFIG_PATH
export PKG_CONFIG_LIBDIR="$DEPS_INSTALL_DIR/lib/pkgconfig"

# Persist the deployment target in Meson so incremental builds do not silently
# use the build machine's newer macOS version when this environment is absent.
DEPLOYMENT_FLAG="-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"

rm -rf "$MACOS_BUILD_DIR"
meson setup "$MACOS_BUILD_DIR" \
    -Dc_args="-I$DEPS_INSTALL_DIR/include $DEPLOYMENT_FLAG" \
    -Dobjc_args="$DEPLOYMENT_FLAG" \
    -Dc_link_args="-L$DEPS_INSTALL_DIR/lib $DEPLOYMENT_FLAG" \
    -Dobjc_link_args="-L$DEPS_INSTALL_DIR/lib $DEPLOYMENT_FLAG" \
    --buildtype=release \
    --strip \
    -Db_lto=true \
    -Dcompile_server=false \
    -Dportable=true \
    -Dstatic=true
ninja -C "$MACOS_BUILD_DIR"

# Group intermediate outputs into a 'dist' directory
mkdir -p "$MACOS_BUILD_DIR/dist"
cp "$MACOS_BUILD_DIR"/app/anmir "$MACOS_BUILD_DIR/dist/"
cp app/data/scrcpy.png "$MACOS_BUILD_DIR/dist/"
cp app/data/disconnected.png "$MACOS_BUILD_DIR/dist/"
cp -r app/data/toolbar-icons "$MACOS_BUILD_DIR/dist/"
cp app/anmir.1 "$MACOS_BUILD_DIR/dist/"
cp LICENSE "$MACOS_BUILD_DIR/dist"
cp NOTICE THIRD_PARTY.md "$MACOS_BUILD_DIR/dist"
cp -r "$ADB_INSTALL_DIR"/. "$MACOS_BUILD_DIR/dist/"
release/collect_macos_licenses.sh "$MACOS_BUILD_DIR/dist/licenses"
