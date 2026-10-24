ScrcpyX @VERSION@ — macOS @ARCH@

系统要求
- macOS @MINIMUM_SYSTEM_VERSION@ 或更新版本。
- 本包架构：@ARCH@。arm64 适用于 Apple Silicon（M 系列芯片）。
- 已内置 adb、Android 服务端和所需媒体库，无需安装 Homebrew 或 Android SDK。

安装与使用
1. 打开 DMG，将左侧 ScrcpyX 拖到右侧 Applications（应用程序），完成后推出磁盘映像。
   从“应用程序”打开 ScrcpyX；若使用 ZIP，则先解压再将 ScrcpyX.app 拖入“应用程序”。
   首次打开可选择跟随系统、简体中文、繁体中文或 English，并预览浅色、深色或跟随系统主题。
   点击“继续”保存。之后可点设备列表和投屏窗口右上角的设置齿轮，或按 ⌘, 打开设置。
   主题、显示语言和悬浮工具栏开关即时生效，自动保存，所有投屏窗口同步更新。
   悬浮工具栏默认显示；此前明确关闭的选择会保留。系统权限提示和文件对话框按钮跟随 macOS 语言。
2. 在 Android 手机上打开“开发者选项”中的“USB 调试”。
3. 用支持数据传输的 USB 线连接手机，解锁手机并允许此电脑进行 USB 调试。
4. 双击打开 ScrcpyX。一台可用设备时直接投屏；多台设备时显示设备窗口。
5. 设备行右侧点 Mirror 开始投屏，可同时投屏多台。Starting… 表示投屏窗口正在启动，
   Show 可以切回已打开的投屏窗口。序列号、IP 和 API 位于设备详情中。
   同一台手机的多条 ADB 连接识别后合并为一行，已有投屏窗口会复用。
   新投屏窗口启动完成后会自动到前台。
   投屏标题和 Dock 名称显示品牌、型号；投屏图标带手机角标。
6. 设备会自动发现。设备未出现时，可点右上角扫描图标或按 ⌘R 手动扫描。
   未授权设备需先在手机上允许 USB 调试；离线设备需检查连接。
7. 投屏窗口右上角的设备列表按钮可打开或唤起已有列表，也可从菜单“ScrcpyX → Devices…”打开设备窗口，快捷键为 ⌘⇧D。
   设备窗口没有取消按钮，使用窗口左上角的关闭按钮关闭。
8. 右上角 Wi-Fi 加号图标或无设备时的“Scan QR code →”打开无线连接。
   可扫码或输入六位配对码，配对后自动投屏。
   已配对设备也可从 Manual connection 输入 IP 和连接端口。

首次打开
签名状态：@SIGNING_STATUS@
若 macOS 提示无法验证开发者，在尝试打开后，进入“系统设置 → 隐私与安全性”，
确认应用来自你信任的提供者后，点击该应用对应的“仍要打开”，再确认打开。
无需关闭系统整体安全保护。
Apple 官方说明：https://support.apple.com/102445

命令行
  /Applications/ScrcpyX.app/Contents/MacOS/scrcpy --help
  /Applications/ScrcpyX.app/Contents/MacOS/scrcpy --serial <设备序列号>
显式指定设备、ANDROID_SERIAL、无窗口模式和独立命令行版本保留原有选择行为。

ScrcpyX 基于 scrcpy 开源项目开发。
项目许可见 ScrcpyX.app/Contents/Resources/LICENSE。
