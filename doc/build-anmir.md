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
git clone https://github.com/houzi3/Anmir.git
cd Anmir
git checkout v0.1.2

python3 -m venv release/work/dmgbuild-env
release/work/dmgbuild-env/bin/pip install dmgbuild==1.6.7
export DMGBUILD="$PWD/release/work/dmgbuild-env/bin/dmgbuild"

# Set ANDROID_HOME to your installed Android SDK.
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
mkdir -p release/work/build-server
BUILD_DIR="$PWD/release/work/build-server" bash server/build_without_gradle.sh

./gradlew :companion:assembleDebug
bash release/build_macos.sh "$(uname -m)"
bash release/build_macos_app.sh --dmg --zip \
    --companion "$PWD/companion/build/outputs/apk/debug/companion-debug.apk" \
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

Download `Anmir-0.1.2-source.tar.gz` from the release and extract it. This source
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

The Android helper's version must match the client version. Both are `0.1.2`
for this release. Its Java namespace remains `com.genymobile.scrcpy`.

## In-app updates

The host application checks GitHub's latest stable release seven seconds after
normal GUI startup, at most once per local calendar day. Settings-only launches
and disposable mirror processes do not schedule a check. Attempts (including
failures and manual requests) persist their date, so relaunching does not repeat
a background request that day. There is no periodic polling while the app stays
open. Automatic checks show no progress, up-to-date notices or error dialogs.

Before showing a new release, the updater rechecks running mirror sessions and
the saved skipped version. If either suppresses the automatic prompt, it is
silently discarded for that startup, rather than queued to interrupt the user
later. **Skip This Version** affects that version only. The **Anmir → Check for
Updates…** menu remains available on demand, including for skipped versions and
while mirroring. It bypasses the daily limit and can adopt an in-flight
background request instead of duplicating it. Installation still requires all
mirror windows to close and an explicit user choice.

Release metadata comes from the static manifest at
`https://github.com/houzi3/Anmir/releases/latest/download/update.json`, avoiding
GitHub REST API rate limits. Only strict `MAJOR.MINOR.PATCH` versions are
accepted; numeric comparison prevents downgrades. The manifest contains no
download URLs. The updater constructs version-pinned URLs in the fixed
`houzi3/Anmir` repository after validating the architecture-specific filename
and SHA-256 checksum.

Publish `Anmir-VERSION-arm64.zip`, `Anmir-VERSION-x86_64.zip` and `update.json`
as assets of every stable `vVERSION` Release. After both ZIP files are in one directory,
generate the manifest with optional Markdown release notes:

```sh
bash release/generate_update_manifest.sh dist release-notes.md
```

The `anmir-release` CI artifact combines both architectures, the unsigned companion APK,
and the static update manifest. CI does not receive the Android signing key and does not
publish automatically: the key is shared with other applications and remains on the
maintainer's machine.

After the PR merges, let the main-branch build complete. Download its `anmir-release`
artifact and sign its APK locally:

```sh
python3 release/sign_companion.py \
  release-artifacts/AnmirConnect-0.1.2-unsigned.apk \
  release-artifacts/AnmirConnect-0.1.2.apk
```

Create a **draft** `vVERSION` release targeting that successful build's exact commit,
and upload only the signed APK to the draft. Then dispatch `anmir-release.yml` on
`main` with `publish=true` and `build_run_id=THE_COMPLETED_RUN_ID`. This reuses the
completed build instead of rebuilding. The publisher requires a successful main
build, a matching release tag, an unchanged APK payload and the pinned release
certificate before uploading the Mac packages, APK, checksums and `update.json`.
Published releases are never overwritten.

After publication succeeds, the workflow runs `bump_version` and commits the next
patch version to `main`, including both Android modules. Forks still build artifacts
but never publish or change their branches.

Drafts and prereleases are not selected by GitHub's `releases/latest` redirect.
Missing, malformed or incomplete manifests fail closed. The updater verifies
the downloaded ZIP hash, bundle identity, version, minimum macOS and code
signature integrity. Ad hoc signatures remain supported: this is not a
publisher-signature trust mechanism independent of GitHub. A compromised
publisher account is outside this update trust model.

All mirror windows must be closed before installation. The installed app must
be in a writable folder, outside a mounted disk image; the updater never asks
for administrator privileges. After download, confirmation is required to quit
and restart. The packaged `install-update.sh` waits up to 60 seconds for the host
to exit, then replaces it using a staged app on the same volume. A failed move
or Launch Services open restores the previous app. The old bundle remains as
`Anmir.previous-TIMESTAMP-PID.app` after success for manual recovery; a crash
following a successful launch is not automatically detected. System security
prompts remain under macOS control.

Updater checks can be run without phones or network:

```sh
meson test -C build-debug test_updater test_updater_automatic --print-errorlogs
python3 app/tests/test_update_installer.py
```

The installer tests replace only the OS launch and move entry points with
fixtures; all application folders are disposable. A real released ZIP, GUI
confirmation and relaunch still require an end-to-end manual test.


## Anmir Connect release signing

The maintainer's signing material stays outside this repository at
`~/important_key/android_keystore/`, with directory permissions `700` and file
permissions `600`. `signing.properties` specifies `storeFile`, `storeType`,
`storePassword`, `keyAlias` and `keyPassword`; a relative `storeFile` is resolved
beside that properties file. `ANMIR_CONNECT_SIGNING_PROPERTIES` may point to a
different local properties file for Gradle builds.

Gradle release builds use this local configuration when available. CI explicitly
sets `ANMIR_UNSIGNED_BUILD=true` and builds an unsigned APK. Local signing uses
`release/sign_companion.py`; verification compares every APK payload file before
and after signing and pins the public certificate digest recorded in
`companion/release-certificate.sha256`. Private keys and passwords are never
committed, uploaded as artifacts, or stored as GitHub Actions secrets.

Back up the private signing directory securely. Future APK updates must use the
same signing key. Earlier debug-signed preview APKs must be uninstalled once before
installing the official APK. The package ID remains `io.github.houzi3.anmir.connect`.
