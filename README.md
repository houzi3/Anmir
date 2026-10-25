# Anmir

[English](README.md) · [简体中文](README.zh-CN.md)

**Mirror and control Android devices on your Mac.**

Built on [scrcpy](https://github.com/Genymobile/scrcpy), with QR pairing, device management and floating controls in a native macOS interface.

adb is included, with no separate Homebrew or Android SDK installation needed. Mirroring stays local and requires no account or cloud relay.

> /ˈæn.mɪr/ (AN-mir) · An(droid) + mir(ror)

[Download](#download) · [Screenshots](#screenshots) · [Quick start](#quick-start) · [Release history](#release-history)

## Highlights

- **Built-in wireless pairing:** scan Anmir's QR code with your Android device, or enter a pairing code. Connect paired devices by IP address and port.
- **Unified device management:** discover Android devices and group each device's USB and wireless connections. Each mirror has its own window and Dock entry.
- **Floating controls:** Back, Home, Recents, screenshots and recording beside the mirror window.
- **Screenshots and recording:** copy device screenshots to your Mac's clipboard. Start and stop recording while mirroring, check elapsed time and choose a save location.
- **Appearance and language:** light, dark or system appearance; live switching between English, Simplified Chinese and Traditional Chinese. Settings apply to mirror windows too.

## Download

[Latest release](https://github.com/laobie/Anmir/releases/latest) · macOS 11+ · Apple Silicon / Intel

Choose **arm64** for Apple Silicon or **x86_64** for Intel.

## Screenshots

<table>
  <tr>
    <th>Device list</th>
    <th>Screen mirroring and floating controls</th>
  </tr>
  <tr>
    <td valign="top"><img src="doc/images/devices.png" alt="Anmir device list" width="480" /></td>
    <td valign="top"><img src="doc/images/mirroring.png" alt="Anmir screen mirroring and floating controls" width="250" /></td>
  </tr>
</table>

## Quick start

### Install the app

Open the DMG, drag Anmir into Applications and open it.

<details>
<summary>If macOS blocks the first launch</summary>

1. Double-click the **Privacy & Security** shortcut in the DMG window or extracted ZIP folder.
2. In Privacy & Security, choose **Open Anyway** for Anmir.

The app is not notarized; see [Apple's instructions](https://support.apple.com/102445).

</details>

### USB connection · Android 5.0+

1. Enable **Developer options → USB debugging** on your Android device.
2. Connect it to your Mac with a USB data cable and allow USB debugging on the device.

A single ready device opens directly; with multiple devices, choose one from the device list.

### Wireless connection · Android 11+

1. Connect your device and Mac to the same network. Enable **Developer options → Wireless debugging** on the Android device.
2. Click the **Wi-Fi add button** in Anmir and choose a connection method:

| Method | Action |
| --- | --- |
| QR pairing | Select **Pair device with QR code** on the Android device and scan the code shown in Anmir. |
| Pairing code | Select the discovered device and enter its pairing code. If discovery fails, enter the pairing address and port manually. |
| Already paired device | Enter the device's IP address and connection port manually. |

### Everyday controls

| Action | Where |
| --- | --- |
| Back, Home and Recents | Floating toolbar beside the mirror window. |
| Screenshots and recording | Floating toolbar. Screenshots go to your Mac's clipboard; recordings can be saved to a chosen location. |
| Appearance, language and toolbar settings | Gear in the device list or mirror window, or `⌘,`. |

## Command line

The bundled `anmir` command accepts scrcpy options:

```sh
/Applications/Anmir.app/Contents/MacOS/anmir --help
/Applications/Anmir.app/Contents/MacOS/anmir --serial DEVICE_SERIAL
```

## Documentation and feedback

- User guides: [Shortcuts](doc/shortcuts.md) · [Connections](doc/connection.md) · [Audio](doc/audio.md)
- Developer docs: [Building and LGPL relinking](doc/build-anmir.md) · [macOS architecture](doc/macos-architecture.md)

Report problems in [Issues](https://github.com/laobie/Anmir/issues), including:

- Anmir version, Mac processor and macOS version.
- Android version, connection method and steps to reproduce.

## Release history

| Version | Date | Changes | Release |
| --- | --- | --- | --- |
| v0.1.0 | 2026-10-25 | Initial release: native device management, USB/wireless mirroring, screenshots, recording and localization. | [Release](https://github.com/laobie/Anmir/releases/tag/v0.1.0) |

## Special thanks

Special thanks to [@ztygalaxy](https://github.com/ztygalaxy) for early testing and helpful suggestions.

## License

Independently maintained, based on upstream scrcpy v4.1. Not an official Genymobile project.

Licensed under [Apache 2.0](LICENSE), with [upstream attribution](NOTICE) preserved. Dependency licenses are listed in [THIRD_PARTY.md](THIRD_PARTY.md).

Android is a trademark of Google LLC.
