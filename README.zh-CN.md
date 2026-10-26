<p align="center">
  <img src="app/data/anmir.png" alt="Anmir 应用图标" width="128" height="128" />
</p>

<h1 align="center">Anmir</h1>

<p align="center"><strong>在 Mac 上投屏并控制安卓设备。</strong></p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a>
</p>

基于 [scrcpy](https://github.com/Genymobile/scrcpy)，将扫码配对、设备管理与悬浮操作集成到原生 macOS 界面。

内置 adb，无需另装 Homebrew 或 Android SDK。投屏通过本地连接完成，无需账号或云端转发。

> /ˈæn.mɪr/（安米尔）· An(droid) + mir(ror)

[下载](#下载) · [界面预览](#界面预览) · [快速开始](#快速开始) · [更新记录](#更新记录)

## 特色功能

- **内置无线配对**：用安卓设备扫描 Anmir 的二维码，或在 Anmir 中输入配对码；支持手动连接已配对设备。
- **统一设备管理**：自动发现安卓设备，合并同一设备的 USB 与无线连接；每台设备拥有独立投屏窗口与 Dock 入口。
- **悬浮工具栏**：在投屏窗口旁快速返回、打开主页、切换最近任务、截图和录屏。
- **截图与录屏**：一键截图到 Mac 剪贴板；投屏中启停录屏，显示录制时长，并通过保存对话框选择位置。
- **外观与语言**：浅色、深色或跟随系统；简体中文、繁体中文与英文即时切换，设置同步到投屏窗口。

## 下载

[最新版本](https://github.com/houzi3/Anmir/releases/latest) · macOS 11+ · Apple Silicon / Intel

安装包架构：Apple Silicon 选择 **arm64**，Intel 选择 **x86_64**。

## 界面预览

<table>
  <tr>
    <th>设备列表</th>
    <th>设备投屏与悬浮工具栏</th>
  </tr>
  <tr>
    <td valign="top"><img src="doc/images/devices.png" alt="Anmir 设备列表" width="480" /></td>
    <td valign="top"><img src="doc/images/mirroring.png" alt="Anmir 设备投屏与悬浮工具栏" width="250" /></td>
  </tr>
</table>

## 快速开始

### 安装应用

打开 DMG，将 Anmir 拖入“应用程序”并打开。

<details>
<summary>首次打开被 macOS 拦截</summary>

1. 双击 DMG 窗口或 ZIP 解压目录中的 **Privacy & Security** 快捷入口。
2. 在“隐私与安全性”中，选择 Anmir 对应的“仍要打开”。

安装包尚未经过 Apple 公证，详见 [Apple 说明](https://support.apple.com/102445)。

</details>

### USB 连接 · Android 5.0+

1. 在安卓设备上开启“开发者选项 → USB 调试”。
2. 用 USB 数据线连接设备和 Mac，并在设备上允许 USB 调试。

一台可用设备时自动投屏；多台时从设备列表选择。

### 无线连接 · Android 11+

1. 设备与 Mac 连到可互通的网络，在设备上开启“开发者选项 → 无线调试”。
2. 点击 Anmir 的 **Wi-Fi 加号**，选择连接方式：

<table>
  <tr>
    <th nowrap>方式</th>
    <th>操作</th>
  </tr>
  <tr>
    <td nowrap>二维码配对</td>
    <td>在设备上选择“使用二维码配对设备”，扫描 Anmir 显示的二维码。</td>
  </tr>
  <tr>
    <td nowrap>配对码配对</td>
    <td>选择发现的设备并输入配对码；未发现设备时，手动输入配对地址和端口。</td>
  </tr>
  <tr>
    <td nowrap>连接已配对设备</td>
    <td>手动输入设备的 IP 地址和连接端口。</td>
  </tr>
</table>

### 公司内网扫码 · Android 11+

公司网络扫码一直转圈时，可用 **Anmir Connect** 辅助连接，无需输入 IP 和端口。手机与 Mac 需能通过内网互通。

1. 在 Mac 扫码窗口切换到公司网络方案，在手机[下载安装 Anmir Connect](https://github.com/houzi3/Anmir/releases/tag/v0.1.2)。
2. 打开手机上的 Anmir Connect，点击 **启动辅助连接**，等待自动进入开发者选项。
3. 进入 **无线调试 → 使用二维码配对设备**，扫描 Mac 上的二维码，即可投屏。

保持两端 App 运行和无线调试开启，Wi-Fi 恢复后会自动重连。更多说明见[公司网络扫码连接](doc/company-network.zh-CN.md)。

### 常用操作

| 操作 | 入口 |
| --- | --- |
| 返回、主页、最近任务 | 投屏窗口旁的悬浮工具栏。 |
| 截图、录屏 | 悬浮工具栏；截图复制到 Mac 剪贴板，录屏可选择保存位置。 |
| 外观、语言、工具栏设置 | 设备列表或投屏窗口右上角的齿轮，或按 `⌘,`。 |
| 重新打开窗口 | 从 Spotlight 或访达打开 Anmir；已有窗口会恢复并置前，否则显示设备列表。 |
| 完全退出 | 按 `⌘Q`，关闭 Anmir 和投屏窗口，同时停止后台重连。 |

关闭全部窗口后，Anmir 隐藏 Dock 图标并继续后台重连；最小化窗口会保留 Dock 图标。

## 命令行

应用内的 `anmir` 命令兼容 scrcpy 参数：

```sh
/Applications/Anmir.app/Contents/MacOS/anmir --help
/Applications/Anmir.app/Contents/MacOS/anmir --serial DEVICE_SERIAL
```

## 文档与反馈

- 使用指南：[快捷键](doc/shortcuts.md) · [连接](doc/connection.md) · [音频](doc/audio.md)
- 开发文档：[构建与 LGPL 重新链接](doc/build-anmir.md) · [macOS 架构](doc/macos-architecture.md)

反馈请到 [Issues](https://github.com/houzi3/Anmir/issues)，附上：

- Anmir 版本、Mac 芯片与 macOS 版本。
- 安卓设备的系统版本、连接方式及复现步骤。

## 更新记录

<table>
  <tr>
    <th nowrap>版本</th>
    <th nowrap>日期</th>
    <th>更新内容</th>
    <th>发布页</th>
  </tr>
  <tr>
    <td nowrap>v0.1.3</td>
    <td nowrap>2026-10-27</td>
    <td>更新 macOS 应用图标，采用安卓机器人照 Mac 镜子的设计；投屏窗口保留小手机角标。</td>
    <td><a href="https://github.com/houzi3/Anmir/releases/tag/v0.1.3">Release</a></td>
  </tr>
  <tr>
    <td nowrap>v0.1.2</td>
    <td nowrap>2026-10-26</td>
    <td>新增 Anmir Connect，支持公司内网跨网段扫码与自动重连；修复 Dock 和窗口恢复；改进更新检查，使用静态更新清单。</td>
    <td><a href="https://github.com/houzi3/Anmir/releases/tag/v0.1.2">Release</a></td>
  </tr>
  <tr>
    <td nowrap>v0.1.1</td>
    <td nowrap>2026-10-26</td>
    <td>支持应用内检查、下载和安装更新；改进“关于”窗口，增加项目、反馈和许可证入口。</td>
    <td><a href="https://github.com/houzi3/Anmir/releases/tag/v0.1.1">Release</a></td>
  </tr>
  <tr>
    <td nowrap>v0.1.0</td>
    <td nowrap>2026-10-25</td>
    <td>首次发布：原生设备管理、USB/无线投屏、截图录屏与多语言。</td>
    <td><a href="https://github.com/houzi3/Anmir/releases/tag/v0.1.0">Release</a></td>
  </tr>
</table>

## 特别感谢

特别感谢 [@ztygalaxy](https://github.com/ztygalaxy) 参与早期测试，并提出改进建议。

## 开源许可

基于上游 scrcpy v4.1 独立维护，非 Genymobile 官方项目。

采用 [Apache 2.0](LICENSE)，保留[上游署名](NOTICE)；依赖许可证见 [THIRD_PARTY.md](THIRD_PARTY.md)。

Android is a trademark of Google LLC.
