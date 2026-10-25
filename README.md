# Anmir

**在 Mac 上连接与控制 Android。**

[简体中文](README.md) · [English](README.en.md)

读音：**/ˈæn.mɪr/**，近似“**安米尔**”，重音在前。谐音仅用于帮助发音，品牌名统一为 **Anmir**。

Anmir 是基于 [scrcpy](https://github.com/Genymobile/scrcpy) 开发的独立 macOS 应用。它将 Android 投屏、控制和设备连接整合到原生 Mac 界面中。

## 特色功能

- **开箱即用**：拖入“应用程序”即可启动，内置 adb，无需另装 Homebrew 或 Android SDK。
- **USB + 无线连接**：自动发现设备，支持二维码、六位配对码和手动地址；同一手机的 USB 与无线连接合并展示。
- **多设备独立投屏**：每台设备拥有独立窗口和 Dock 入口，可从任一投屏窗口返回设备列表。
- **截图与录屏触手可及**：悬浮工具栏提供返回、主页、最近任务、截图和录屏；截图复制到剪贴板，录屏显示时长并可选择保存位置。
- **原生外观，多语言切换**：支持浅色、深色和跟随系统；简体中文、繁体中文、英文即时切换。
- **本地直连**：无需账号，不依赖云端转发；ADB 连接仍可用于调试和日志采集。

## 下载

当前已发布版本：**0.1.3**。提供 Apple Silicon 和 Intel 两种原生版本。

| Mac 芯片 | DMG 安装包 | ZIP 压缩包 |
| --- | --- | --- |
| Apple Silicon（M 系列） | [arm64 DMG](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-arm64.dmg) | [arm64 ZIP](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-arm64.zip) |
| Intel | [x86_64 DMG](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-x86_64.dmg) | [x86_64 ZIP](https://github.com/laobie/Anmir/releases/download/v0.1.3/Anmir-0.1.3-x86_64.zip) |

[全部版本](https://github.com/laobie/Anmir/releases) · [SHA-256 校验文件](https://github.com/laobie/Anmir/releases/download/v0.1.3/SHA256SUMS)

**系统要求**：macOS 11 或更新版本。USB 投屏支持 Android 5.0+；无线扫码和配对码连接需要 Android 11+。音频转发通常需要 Android 11+，部分设备存在额外限制。

## 安装与连接

1. 打开 DMG，将 **Anmir** 拖入 **Applications（应用程序）**，再从“应用程序”打开。
2. 首次启动选择语言和外观；之后可在设置中随时更改。
3. 在 Android 设备上开启“开发者选项 → USB 调试”。
4. 用 USB 数据线连接 Mac，在手机上允许 USB 调试授权。一台可用设备时会直接投屏；多台设备时可在设备列表中选择。

**无线连接**：让手机和 Mac 处于可互通的网络，点击设备列表中的 Wi-Fi 加号。在手机的“开发者选项 → 无线调试 → 使用二维码配对设备”中扫码，也可切换为六位配对码或手动地址连接。

**首次打开**：0.1.3 使用本地 ad hoc 签名，尚未经过 Apple 公证。若被系统拦截，请确认下载来源后，按 [Apple 官方说明](https://support.apple.com/102445)前往“系统设置 → 隐私与安全性 → 仍要打开”。

## 命令行

当前源码将命令名统一为 **`anmir`**，兼容 scrcpy 的命令行参数。应用内入口为：

```sh
/Applications/Anmir.app/Contents/MacOS/anmir --help
/Applications/Anmir.app/Contents/MacOS/anmir --serial DEVICE_SERIAL
```

已发布的 **v0.1.3** 安装包仍使用 `Contents/MacOS/scrcpy` 文件名。上面的 `anmir` 入口适用于更新后的源码构建；旧版本请将路径最后的 `anmir` 改为 `scrcpy`。

若希望直接输入 `anmir`，可将对应的应用内可执行文件链接到自己的 PATH 目录，并将链接命名为 `anmir`。它可以与原版 `scrcpy` 并存。

## 构建与技术文档

构建和 LGPL 库重新链接方法见[构建说明](doc/build-anmir.md)。[Release](https://github.com/laobie/Anmir/releases) 提供包含应用源码和第三方库原始源码的完整源码包。

[窗口与快捷键](doc/window.md) · [键盘](doc/keyboard.md) · [鼠标](doc/mouse.md) · [音频](doc/audio.md) · [连接](doc/connection.md) · [macOS 架构](doc/macos-architecture.md)

底层代码保留跨平台能力；Anmir 当前发布的图形应用面向 macOS。继承自上游的技术文档仍可能使用 `scrcpy` 名称；在 Anmir 的新命令行入口中使用同样的参数即可。

## 反馈

请通过 [Anmir Issues](https://github.com/laobie/Anmir/issues) 报告问题，并附上 Anmir 版本、Mac 芯片、macOS/Android 版本和连接方式。

## 开源许可与致谢

Anmir 基于 **scrcpy v4.1**，独立维护，与 Genymobile 及 scrcpy 维护者无隶属或背书关系。

原始 scrcpy 版权归 Genymobile、Romain Vimont 及相应贡献者所有，原有声明保留在 [LICENSE](LICENSE) 和 [NOTICE](NOTICE) 中。Anmir 的修改按 **Apache License 2.0** 分发；第三方依赖遵循各自许可证，详见 [THIRD_PARTY.md](THIRD_PARTY.md)。

感谢 [scrcpy](https://github.com/Genymobile/scrcpy)、[SDL](https://www.libsdl.org/)、[FFmpeg](https://ffmpeg.org/)、[dav1d](https://code.videolan.org/videolan/dav1d) 和 [libusb](https://libusb.info/) 项目及其贡献者。

Android is a trademark of Google LLC.
