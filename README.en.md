# Anmir

[简体中文](README.md) · [English](README.en.md)

Mirror and control Android from your Mac. Built on [scrcpy](https://github.com/Genymobile/scrcpy), with adb included.

> /ˈæn.mɪr/ (AN-mir) · An(droid) + mir(ror)

## Highlights

- **USB and wireless:** QR codes, pairing codes and manual addresses.
- **Multiple devices:** independent windows and Dock entries.
- **Screenshots and recording:** quick captures, recording timer and save options.
- **Native macOS interface:** floating controls, light and dark themes.
- **Languages:** English, Simplified Chinese and Traditional Chinese.
- **Local connections:** no account or cloud relay.

## Download

**v0.1.3** · macOS 11+

| Mac processor | DMG | ZIP |
| --- | --- | --- |
| Apple Silicon (M series) | [arm64](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-arm64.dmg) | [arm64](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-arm64.zip) |
| Intel | [x86_64](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-x86_64.dmg) | [x86_64](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-x86_64.zip) |

[All releases](https://github.com/laobie/Anmir/releases) · [SHA-256 checksums](https://github.com/laobie/Anmir/releases/download/v0.1.3/SHA256SUMS)

USB mirroring requires Android 5.0+; wireless pairing requires Android 11+.

## Quick start

1. Open the DMG, drag Anmir into Applications and open it.
2. Enable **Developer options → USB debugging** on your phone.
3. Connect via USB and allow debugging on the phone to start mirroring.

**Wireless:** connect both devices to the same network, enable Wireless debugging on the phone, then click the Wi-Fi add button in Anmir and follow the pairing instructions.

Version 0.1.3 is not notarized by Apple. If macOS blocks the first launch, follow [Apple's instructions](https://support.apple.com/102445).

## Command line

Builds from source use `anmir` and accept scrcpy options:

```sh
/Applications/Anmir.app/Contents/MacOS/anmir --help
/Applications/Anmir.app/Contents/MacOS/anmir --serial DEVICE_SERIAL
```

For the published v0.1.3 installers, replace the final `anmir` in these paths with `scrcpy`.

## Documentation and feedback

[Building and LGPL relinking](doc/build-anmir.md) · [Shortcuts](doc/shortcuts.md) · [Connections](doc/connection.md) · [Audio](doc/audio.md) · [macOS architecture](doc/macos-architecture.md)

Report issues in [Issues](https://github.com/laobie/Anmir/issues), including the version, operating systems and connection method.

## License

Independently maintained, based on scrcpy v4.1. Not an official Genymobile project.

Licensed under [Apache 2.0](LICENSE), with [upstream attribution](NOTICE) preserved. Dependency licenses are listed in [THIRD_PARTY.md](THIRD_PARTY.md).

Android is a trademark of Google LLC.
