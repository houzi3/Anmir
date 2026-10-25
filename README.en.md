# Anmir

**Connect to and control Android from your Mac.**

[简体中文](README.md) · [English](README.en.md)

Pronounced **AN-mir** (/ˈæn.mɪr/), with the stress on the first syllable.

Anmir is an independently maintained macOS application based on [scrcpy](https://github.com/Genymobile/scrcpy). It brings Android mirroring, control and device connections into a native Mac interface.

## Highlights

- **Ready to use:** drag the app into Applications. adb is included; no separate Homebrew or Android SDK installation is needed.
- **USB and wireless connections:** discover devices automatically, pair with a QR code or six-digit code, or enter an address. USB and wireless connections for the same phone are grouped together.
- **Independent device windows:** each mirror has its own window and Dock entry, with access to the device list from any mirror.
- **Screenshots and recording at hand:** floating controls provide Back, Home, Recents, screenshots and recording. Copy screenshots to the clipboard, see recording duration and choose where to save recordings.
- **Native appearance and live language switching:** light, dark and system appearance; English, Simplified Chinese and Traditional Chinese.
- **Direct local connections:** no account or cloud relay required. ADB connections remain available for debugging and logs.

## Download

Current published version: **0.1.3**, with native builds for Apple Silicon and Intel Macs.

| Mac processor | DMG installer | ZIP archive |
| --- | --- | --- |
| Apple Silicon (M series) | [arm64 DMG](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-arm64.dmg) | [arm64 ZIP](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-arm64.zip) |
| Intel | [x86_64 DMG](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-x86_64.dmg) | [x86_64 ZIP](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-x86_64.zip) |

[All releases](https://github.com/laobie/Anmir/releases) · [SHA-256 checksums](https://github.com/laobie/Anmir/releases/download/v0.1.3/SHA256SUMS)

**Requirements:** macOS 11 or later. USB mirroring supports Android 5.0+; wireless QR and pairing-code setup require Android 11+. Audio forwarding generally requires Android 11+, with additional restrictions on some devices.

## Install and connect

1. Open the DMG, drag **Anmir** into **Applications**, then open it from Applications.
2. Choose your language and appearance on first launch. You can change both in Settings.
3. Enable **Developer options → USB debugging** on the Android device.
4. Connect it with a USB data cable and allow USB debugging on the phone. A single ready device opens directly; with multiple devices, choose one from the device list.

**Wireless:** put the phone and Mac on a network where they can reach each other, then click the Wi-Fi add button in the device window. On the phone, open **Developer options → Wireless debugging → Pair device with QR code** and scan the code. Six-digit pairing codes and manual addresses are also supported.

**First launch:** version 0.1.3 has a local ad hoc signature and is not notarized by Apple. If macOS blocks the app, verify the download source and follow [Apple's instructions](https://support.apple.com/102445) to use **System Settings → Privacy & Security → Open Anyway**.

## Command line

The current source uses **`anmir`** as the command name and accepts scrcpy command-line options. Its bundled entry point is:

```sh
/Applications/Anmir.app/Contents/MacOS/anmir --help
/Applications/Anmir.app/Contents/MacOS/anmir --serial DEVICE_SERIAL
```

The published **v0.1.3** installers still use the filename `Contents/MacOS/scrcpy`. The `anmir` entry point above applies to builds from the updated source; for v0.1.3, replace the final `anmir` in the path with `scrcpy`.

To run it as `anmir`, link the appropriate bundled executable into a directory on your PATH, naming the link `anmir`. It can coexist with the original `scrcpy` command.

## Building and technical documentation

See [Build Anmir](doc/build-anmir.md) for build and LGPL relinking instructions. Each [release](https://github.com/laobie/Anmir/releases) includes a complete source package containing the application and original third-party library source archives.

[Windows and shortcuts](doc/window.md) · [Keyboard](doc/keyboard.md) · [Mouse](doc/mouse.md) · [Audio](doc/audio.md) · [Connections](doc/connection.md) · [macOS architecture](doc/macos-architecture.md)

The underlying code retains its cross-platform capabilities. Anmir's current graphical releases target macOS. Inherited technical documentation may still use the name `scrcpy`; the same options apply to Anmir's new command-line entry point.

## Feedback

Report issues in [Anmir Issues](https://github.com/laobie/Anmir/issues), including the Anmir version, Mac processor, macOS/Android versions and connection method.

## License and acknowledgments

Anmir is based on **scrcpy v4.1** and is independently maintained. It is not affiliated with or endorsed by Genymobile or scrcpy's maintainers.

Original scrcpy copyright belongs to Genymobile, Romain Vimont and the respective contributors. Original notices are preserved in [LICENSE](LICENSE) and [NOTICE](NOTICE). Anmir's modifications are distributed under **Apache License 2.0**; third-party components retain their own licenses, listed in [THIRD_PARTY.md](THIRD_PARTY.md).

Thanks to [scrcpy](https://github.com/Genymobile/scrcpy), [SDL](https://www.libsdl.org/), [FFmpeg](https://ffmpeg.org/), [dav1d](https://code.videolan.org/videolan/dav1d) and [libusb](https://libusb.info/), and their contributors.

Android is a trademark of Google LLC.
