# Build Anmir on macOS

Build each architecture on a matching Mac or GitHub Actions runner. The release
script rejects an architecture that does not match the host; renaming an ARM
binary does not produce an Intel build.

## Requirements

- Xcode Command Line Tools and macOS 11 or later.
- Homebrew: `brew install meson ninja cmake nasm pkg-config zlib automake autoconf libtool wget`.
- Java 17, Android SDK platform 36 and build-tools 36.0.0 to build the Android helper.
- Python 3 and `dmgbuild==1.6.7` to produce the installer.

```sh
git clone https://github.com/laobie/Anmir.git
cd Anmir
git checkout v0.1.0

python3 -m venv release/work/dmgbuild-env
release/work/dmgbuild-env/bin/pip install dmgbuild==1.6.7
export DMGBUILD="$PWD/release/work/dmgbuild-env/bin/dmgbuild"

# Set ANDROID_HOME to your installed Android SDK.
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
mkdir -p release/work/build-server
BUILD_DIR="$PWD/release/work/build-server" bash server/build_without_gradle.sh

bash release/build_macos.sh "$(uname -m)"
bash release/build_macos_app.sh --dmg --zip \
    --server "$PWD/release/work/build-server/scrcpy-server" \
    "release/work/build-macos-$(uname -m)"
```

The output is `dist/Anmir.app`, architecture-specific DMG and ZIP files, and
`dist/SHA256SUMS`. The bundled command is `Contents/MacOS/anmir`.
Bundles use a local ad hoc signature unless a signing identity
is supplied. An ad hoc signature is not Apple notarization.

The DMG and ZIP include a **Privacy & Security** shortcut. If the first launch
is blocked, double-click it to open macOS security settings, then choose
**Open Anyway** for Anmir. The shortcut only navigates to settings; approval
remains in the system dialog.

## Rebuild with modified LGPL libraries

Download `Anmir-0.1.0-source.tar.gz` from the release and extract it. This source
package includes the application and the original source archives for FFmpeg,
libusb, SDL and dav1d at `app/deps/work/sources/`. Each dependency script verifies
its archive checksum before extraction. Dependency patches are under
`app/deps/patches/`; the build configuration is in `app/deps/*.sh`.

1. Run the normal build once to unpack and configure dependencies.
2. Edit the extracted dependency source under `app/deps/work/sources/`.
3. Rerun `bash release/build_macos.sh "$(uname -m)"`. The dependency scripts rebuild
   and install the edited libraries; the client is then linked again against
   those static libraries.
4. Package the rebuilt client with `release/build_macos_app.sh` as above. Its
   default ad hoc signature can be regenerated locally without the publisher's
   signing key.

If you change dependency configuration flags, remove only that dependency's
matching build directory under `app/deps/work/build/` before rebuilding. The
source archive includes no private application code or unavailable link inputs.
ADB is a separate executable; its upstream notices are included in the app.

The Android helper's version must match the client version. Both are `0.1.0`
for this release. Its Java namespace remains `com.genymobile.scrcpy`.
