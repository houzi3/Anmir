# Anmir

[简体中文](README.md) · [English](README.en.md)

<img src="app/data/scrcpy.png" width="112" height="112" alt="Anmir" align="right" />

**在 Mac 上连接与控制 Android。**

Anmir 是基于 [scrcpy](https://github.com/Genymobile/scrcpy) 开发的独立 macOS 应用，提供原生设备管理、USB 与无线连接、多设备投屏，以及截图和录屏。下载后拖入“应用程序”即可使用，无需另行安装 Homebrew、Android SDK 或 adb。

当前版本：**0.1.3**。提供 Apple Silicon 和 Intel 两种原生版本。

## 下载

| Mac 芯片 | 推荐安装包 | ZIP |
| --- | --- | --- |
| Apple Silicon（M 系列） | [Anmir 0.1.3 · arm64 DMG](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-arm64.dmg) | [arm64 ZIP](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-arm64.zip) |
| Intel | [Anmir 0.1.3 · x86_64 DMG](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-x86_64.dmg) | [x86_64 ZIP](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-x86_64.zip) |

[全部版本](https://github.com/laobie/Anmir/releases) · [SHA-256 校验文件](https://github.com/laobie/Anmir/releases/download/v0.1.3/SHA256SUMS)

系统要求：**macOS 11 或更新版本**。USB 投屏支持 Android 5.0+；无线扫码和配对码连接需要 Android 11+。音频转发通常需要 Android 11+，部分设备存在额外限制。

## 安装与连接

1. 打开 DMG，将 **Anmir** 拖入 **Applications（应用程序）**，再从“应用程序”打开。
2. 首次启动选择语言和外观；之后可在设置中随时更改。
3. 在 Android 设备上开启“开发者选项 → USB 调试”。
4. 用 USB 数据线连接 Mac，在手机上允许 USB 调试授权。一台可用设备时会直接投屏；多台设备时可在设备列表中选择。

**无线连接：**让手机和 Mac 处于可互通的网络，点击设备列表中的 Wi-Fi 加号。在手机的“开发者选项 → 无线调试 → 使用二维码配对设备”中扫码，也可切换为六位配对码或手动地址连接。

0.1.3 使用本地 ad hoc 签名，**尚未经过 Apple 公证**。首次打开若被系统拦截，请确认下载来源后，按 [Apple 官方说明](https://support.apple.com/102445)前往“系统设置 → 隐私与安全性 → 仍要打开”。

## 功能

- **原生设备管理**：自动发现设备，显示型号和连接状态；同一手机的 USB 与无线连接合并展示。
- **多设备投屏**：每台设备拥有独立窗口和 Dock 入口，可从任一投屏窗口返回设备列表。
- **无线配对**：支持二维码、配对码和手动地址。
- **操作工具栏**：返回、主页、最近任务、截图和录屏，提供就近操作反馈。
- **截图与录屏**：截图复制到剪贴板；录制时显示时长，并可选择保存位置。
- **即时设置**：浅色、深色、跟随系统；简体中文、繁体中文、英文和跟随系统语言。
- **本地连接**：无需账号，不依赖云端转发；ADB 连接仍可用于调试和日志采集。

## 命令行与构建

应用内保留兼容 scrcpy 参数的命令行入口：

```sh
/Applications/Anmir.app/Contents/MacOS/scrcpy --help
/Applications/Anmir.app/Contents/MacOS/scrcpy --serial <设备序列号>
```

构建和 LGPL 库重新链接方法见[构建说明](doc/build-anmir.md)。[Release](https://github.com/laobie/Anmir/releases) 提供包含应用源码和第三方库原始源码的完整源码包。

[窗口与快捷键](doc/window.md) · [键盘](doc/keyboard.md) · [鼠标](doc/mouse.md) · [音频](doc/audio.md) · [连接](doc/connection.md) · [macOS 架构](doc/macos-architecture.md)

底层 scrcpy 保留跨平台能力；Anmir 当前发布的图形应用面向 macOS。部分继承的技术文档仍使用 scrcpy 名称描述底层功能。

## 反馈

请通过 [Anmir Issues](https://github.com/laobie/Anmir/issues) 报告问题，并附上 Anmir 版本、Mac 芯片、macOS/Android 版本和连接方式。

## 开源许可与致谢

Anmir 基于 **scrcpy v4.1**，独立维护，与 Genymobile 及 scrcpy 维护者无隶属或背书关系。

原始 scrcpy 版权归 Genymobile、Romain Vimont 及相应贡献者所有，原有声明保留在 [LICENSE](LICENSE) 和 [NOTICE](NOTICE) 中。Anmir 的修改按 **Apache License 2.0** 分发；第三方依赖遵循各自许可证，详见 [THIRD_PARTY.md](THIRD_PARTY.md)。

感谢 [scrcpy](https://github.com/Genymobile/scrcpy)、[SDL](https://www.libsdl.org/)、[FFmpeg](https://ffmpeg.org/)、[dav1d](https://code.videolan.org/videolan/dav1d) 和 [libusb](https://libusb.info/) 项目及其贡献者。

Android is a trademark of Google LLC.
