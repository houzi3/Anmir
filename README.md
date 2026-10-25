# Anmir

[简体中文](README.md) · [English](README.en.md)

在 Mac 上投屏和控制 Android。基于 [scrcpy](https://github.com/Genymobile/scrcpy)，内置 adb，开箱即用。

> /ˈæn.mɪr/（安米尔）· An(droid) + mir(ror)

## 特色功能

- **USB 与无线连接**：支持扫码、配对码和手动地址。
- **多设备投屏**：独立窗口与 Dock 入口。
- **截图与录屏**：一键截图、录制计时与保存。
- **原生 macOS 体验**：悬浮工具栏、浅色与深色主题。
- **多语言**：简体中文、繁体中文、英文。
- **本地直连**：无需账号或云端转发。

## 下载

**v0.1.3** · macOS 11+

| Mac 芯片 | DMG | ZIP |
| --- | --- | --- |
| Apple Silicon（M 系列） | [arm64](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-arm64.dmg) | [arm64](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-arm64.zip) |
| Intel | [x86_64](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-x86_64.dmg) | [x86_64](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-x86_64.zip) |

[全部版本](https://github.com/laobie/Anmir/releases) · [SHA-256 校验](https://github.com/laobie/Anmir/releases/download/v0.1.3/SHA256SUMS)

USB 投屏需 Android 5.0+，无线配对需 Android 11+。

## 快速开始

1. 打开 DMG，将 Anmir 拖入“应用程序”并打开。
2. 在手机上开启“开发者选项 → USB 调试”。
3. 连接 USB，在手机上允许调试授权，即可投屏。

**无线连接**：手机与 Mac 连到同一网络，开启手机“无线调试”，点击设备列表的 Wi-Fi 加号，按提示配对。

v0.1.3 未经 Apple 公证；首次打开被拦截时，参阅 [Apple 说明](https://support.apple.com/102445)。

## 命令行

兼容 scrcpy 参数，源码构建的入口为：

```sh
/Applications/Anmir.app/Contents/MacOS/anmir --help
/Applications/Anmir.app/Contents/MacOS/anmir --serial DEVICE_SERIAL
```

v0.1.3 安装包请将上述路径末尾的 `anmir` 替换为 `scrcpy`。

## 文档与反馈

[构建与 LGPL 重新链接](doc/build-anmir.md) · [快捷键](doc/shortcuts.md) · [连接](doc/connection.md) · [音频](doc/audio.md) · [macOS 架构](doc/macos-architecture.md)

反馈请到 [Issues](https://github.com/laobie/Anmir/issues)，附上版本、系统和连接方式。

## 开源许可

基于 scrcpy v4.1 独立维护，非 Genymobile 官方项目。

采用 [Apache 2.0](LICENSE)，保留[上游署名](NOTICE)；依赖许可证见 [THIRD_PARTY.md](THIRD_PARTY.md)。

Android is a trademark of Google LLC.
