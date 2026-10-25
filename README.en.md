# Anmir

[简体中文](README.md) · [English](README.en.md)

<img src="app/data/scrcpy.png" width="112" height="112" alt="Anmir" align="right" />

**Connect to and control Android from your Mac.**

Anmir is an independently maintained macOS application based on [scrcpy](https://github.com/Genymobile/scrcpy). It adds native device management, USB and wireless connections, multiple mirror windows, screenshots and recording. Drag it into Applications to get started; Homebrew, the Android SDK and a separate adb installation are not required.

Current version: **0.1.3**, with native builds for Apple Silicon and Intel Macs.

## Download

| Mac processor | Recommended installer | ZIP |
| --- | --- | --- |
| Apple Silicon (M series) | [Anmir 0.1.3 · arm64 DMG](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-arm64.dmg) | [arm64 ZIP](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-arm64.zip) |
| Intel | [Anmir 0.1.3 · x86_64 DMG](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-x86_64.dmg) | [x86_64 ZIP](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-x86_64.zip) |

[All releases](https://github.com/laobie/Anmir/releases) · [SHA-256 checksums](https://github.com/laobie/Anmir/releases/download/v0.1.3/SHA256SUMS)

Requires **macOS 11 or later**. USB mirroring supports Android 5.0+; wireless QR and pairing-code setup require Android 11+. Audio forwarding generally requires Android 11+, with additional restrictions on some devices.

## Install and connect

1. Open the DMG, drag **Anmir** into **Applications**, then open it from Applications.
2. Choose your language and appearance on first launch. You can change both in Settings.
3. Enable **Developer options → USB debugging** on the Android device.
4. Connect it with a USB data cable and allow USB debugging on the phone. A single ready device opens directly; with multiple devices, choose one from the device list.

**Wireless:** put the phone and Mac on a network where they can reach each other, then click the Wi-Fi add button in the device window. On the phone, open **Developer options → Wireless debugging → Pair device with QR code** and scan the code. Six-digit pairing codes and manual addresses are also supported.

Version 0.1.3 has a local ad hoc signature and **is not notarized by Apple**. If macOS blocks the first launch, verify the download source and follow [Apple's instructions](https://support.apple.com/102445) to use **System Settings → Privacy & Security → Open Anyway**.

## Features

- **Native device management:** automatic discovery, device models and connection status; USB and wireless transports for the same phone are grouped together.
- **Multiple mirrors:** independent windows and Dock entries for each device, with access to the device list from any mirror.
- **Wireless pairing:** QR codes, pairing codes and manual addresses.
- **Floating controls:** Back, Home, Recents, screenshots and recording, with feedback beside the controls.
- **Screenshots and recording:** copy screenshots to the clipboard, see recording duration and choose where to save recordings.
- **Live settings:** light, dark and system appearance; English, Simplified Chinese, Traditional Chinese and system language.
- **Local connections:** no account or cloud relay required; ADB connections remain available for debugging and logs.

## Command line and building

The app includes a command-line entry point compatible with scrcpy options:

```sh
/Applications/Anmir.app/Contents/MacOS/scrcpy --help
/Applications/Anmir.app/Contents/MacOS/scrcpy --serial <device-serial>
```

See [Build Anmir](doc/build-anmir.md) for build and LGPL relinking instructions. Each [release](https://github.com/laobie/Anmir/releases) includes a complete source package containing the application and original third-party library source archives.

[Windows and shortcuts](doc/window.md) · [Keyboard](doc/keyboard.md) · [Mouse](doc/mouse.md) · [Audio](doc/audio.md) · [Connections](doc/connection.md) · [macOS architecture](doc/macos-architecture.md)

The underlying scrcpy code retains its cross-platform capabilities. Anmir's current graphical releases target macOS; inherited technical documentation may refer to scrcpy when describing the underlying functionality.

## Feedback

Report issues in [Anmir Issues](https://github.com/laobie/Anmir/issues), including the Anmir version, Mac processor, macOS/Android versions and connection method.

## License and acknowledgments

Anmir is based on **scrcpy v4.1** and is independently maintained. It is not affiliated with or endorsed by Genymobile or scrcpy's maintainers.

Original scrcpy copyright belongs to Genymobile, Romain Vimont and the respective contributors. Original notices are preserved in [LICENSE](LICENSE) and [NOTICE](NOTICE). Anmir's modifications are distributed under **Apache License 2.0**; third-party components retain their own licenses, listed in [THIRD_PARTY.md](THIRD_PARTY.md).

Thanks to [scrcpy](https://github.com/Genymobile/scrcpy), [SDL](https://www.libsdl.org/), [FFmpeg](https://ffmpeg.org/), [dav1d](https://code.videolan.org/videolan/dav1d) and [libusb](https://libusb.info/), and their contributors.

Android is a trademark of Google LLC.
