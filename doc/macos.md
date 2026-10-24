# On macOS

## Install

### From the official release

Download a static build of the [latest release]:

 - [`scrcpy-macos-aarch64-v4.1.tar.gz`][direct-macos-aarch64] (aarch64)  
   <sub>SHA-256: `20fd47c9014dd5e0fa77091f3cb7adbda8445a360c4584aeaa0150b5b3988ff3`</sub>
 - [`scrcpy-macos-x86_64-v4.1.tar.gz`][direct-macos-x86_64] (x86_64)  
   <sub>SHA-256: `ee2a7223bc8dbdc4f482db1134bcf441178dafb833492b71ca4c22090c58ce72`</sub>

[latest release]: https://github.com/Genymobile/scrcpy/releases/latest
[direct-macos-aarch64]: https://github.com/Genymobile/scrcpy/releases/download/v4.1/scrcpy-macos-aarch64-v4.1.tar.gz
[direct-macos-x86_64]: https://github.com/Genymobile/scrcpy/releases/download/v4.1/scrcpy-macos-x86_64-v4.1.tar.gz

and extract it.


### From a package manager

Scrcpy is available in [Homebrew]:

```bash
brew install scrcpy
```

[Homebrew]: https://brew.sh/

You need `adb`, accessible from your `PATH`. If you don't have it yet:

```bash
brew install --cask android-platform-tools
```

Alternatively, Scrcpy is also available in [MacPorts], which sets up `adb` for you:

```bash
sudo port install scrcpy
```

[MacPorts]: https://www.macports.org/

_See [build.md](build.md) to build and install the app manually._


### As a macOS application

Build a static release distribution, then package it as a regular `.app`
bundle with an icon:

```bash
release/build_macos.sh "$(uname -m)"
release/build_server.sh
release/build_macos_app.sh --zip \
    "release/work/build-macos-$(uname -m)"
```

This creates `dist/ScrcpyX.app` and a zipped copy. Use `--dmg` instead of
`--zip` to create a disk image. Copy the application to `/Applications`, or
open the disk image and drag it there. It then appears in Launchpad and
Spotlight, and can be opened by double-clicking.

The archive also includes `README.txt` with installation, USB debugging and
first-launch instructions. The application connects automatically when exactly
one ready device is attached. With multiple devices it shows a native device
window with the device name, Android version and connection type. Serial number,
IP address, API level and status are available from each row's details button.
**Mirror** starts an independent mirror of an already connected device, so
multiple devices can run at once. **Starting…** remains disabled until the
mirror window appears; **Show** then activates that window. Unauthorized and
offline devices cannot start mirroring. Device changes are detected
automatically. The scan icon at the top right (Cmd+R) is a manual fallback:
“Device not showing up? Scan again.” Close the window with its normal
close button. The ScrcpyX > Devices… menu (Cmd+Shift+D) opens the device window
from any mirror, including single-device launches. With no usable device, the
application shows setup guidance. Explicit
selectors (`-s`, `-d`, `-e`, `ANDROID_SERIAL`), `--tcpip=<address>`, list and
headless modes retain their command line behavior. The standalone CLI is
unaffected.

The default device window is 760 × 500 points with compact, single-line rows.
The title bar has scan, Wi-Fi-add and theme icons. The sun or moon switches
between Light and Dark in one click, and is also available in mirror windows.
The first-launch chooser offers System (the default), Light and Dark. The System
symbol is a circle split diagonally from bottom-left to top-right. The compact
400 × 260 point chooser has three selectable rows. System
follows macOS appearance automatically; the title-bar shortcut selects a fixed
appearance. Return to System through ScrcpyX > Theme > System. Theme choices are
saved and shared across the manager and independent mirrors.

Multiple ADB transports for one phone (USB, mDNS or IP) are grouped using its
physical serial number, while different phones remain separate. A newly seen
address waits for identity lookup before appearing, preventing duplicate rows
during asynchronous discovery. An existing mirror is reused across those transports. This only groups the UI and leaves
ADB connections available for debugging and log collection. Reopening the
manager also recognizes mirrors that were started independently or before it.

Mirror windows display the manufacturer and full model name. The Android version
is a smaller secondary title. A roomier unified titlebar keeps the controls
aligned and uses theme-specific text colors for readable active and inactive
windows. Newly opened mirrors move to the foreground. Each GUI mirror has a phone badge on its Dock icon
and uses the device name as its Dock display name; the manager remains ScrcpyX.
Disposable per-device app launchers share the installed application’s theme and
ADB settings and are removed when the mirror exits. Opening Devices from a
mirror activates the main manager instead of creating another manager instance.

The Wi-Fi guide’s **Scan QR code →** action opens the QR connection flow directly.
The Wi-Fi connection window starts with a QR code. On an Android 11+ phone,
open Developer options > Wireless debugging > Pair device with QR code and
scan it. The app pairs using the discovered pairing service, finds the phone's
connection service and opens mirroring. The ADB connection remains available
for commands such as `adb -s <serial> logcat` and `adb -s <serial> shell`.
Use **Use pairing code** for code-based pairing or manual address entry when
automatic discovery is unavailable. QR pairing requires mDNS and network access
between the phone and Mac; a QR code expires after two minutes and can be
replaced with **New QR code**.

The compact pairing-code field accepts exactly six ASCII digits and preserves
leading zeros. After pairing, ScrcpyX discovers the separate connection service
and opens mirroring automatically. If it cannot discover that service, the same
window asks for the connection IP and port without pairing again. **Manual
connection** is a secondary entry for already paired devices. Pairing codes are
passed to ADB through standard input rather than command-line arguments.

The release workflow statically links SDL, FFmpeg and libusb. The packaging
script rejects builds that depend on libraries outside the bundle and macOS.
If the server is already available, pass it with `--server <path>` and skip
`release/build_server.sh`.

The bundle embeds `adb` and `scrcpy-server`, so it does not depend on the
`PATH` of a terminal. Command line options are not available when the app is
started from Finder; run the executable directly instead:

```bash
/Applications/ScrcpyX.app/Contents/MacOS/scrcpy --help
```

Only the native executables are placed in `Contents/MacOS`; the Android server,
icons and documentation live in `Contents/Resources`. This preserves the code
signature when an archive is extracted without extended attributes.

The native application requires macOS 11 or later. See
[macOS architecture](macos-architecture.md) for workflow ownership, cancellation,
mirror preparation and regression coverage.

The bundle is ad-hoc signed by default. If you distribute it to other Macs,
sign it with a Developer ID (`--identity "Developer ID Application: ..."`) and
notarize it, otherwise Gatekeeper blocks it.


## Run

_Make sure that your device meets the [prerequisites](/README.md#prerequisites)._

If you installed it as an application bundle, double-click `ScrcpyX` in
Applications or Launchpad.

Once installed, run from a terminal:

```bash
scrcpy
```

or with arguments (here to disable audio and record to `file.mkv`):

```bash
scrcpy --no-audio --record=file.mkv
```

Documentation for command line arguments is available:
 - `man scrcpy`
 - `scrcpy --help`
 - on [github](/README.md)
