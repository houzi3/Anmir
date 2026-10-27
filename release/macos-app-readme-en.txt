Anmir @VERSION@ — macOS @ARCH@

Requirements
- macOS @MINIMUM_SYSTEM_VERSION@ or later; @ARCH@ build.
- Includes adb, the Android server and media libraries. No Homebrew or SDK required.

Install and connect
1. Open the DMG and drag Anmir to Applications, then eject the disk image.
   For a ZIP, extract it and move Anmir.app to Applications.
2. On first launch, choose Follow System, 简体中文, 繁體中文 or English and preview
   Follow System, Light or Dark appearance. Continue saves your choices.
3. Enable USB debugging in Android Developer options, connect a data-capable
   USB cable, unlock the phone and allow debugging from this Mac.
4. One ready device opens automatically; multiple devices open the device list.
   Mirror starts an independent mirror; Starting… waits for its window; Show
   activates an existing mirror. Multiple connections to one phone share a row.
   Device details contain serial number, IP address and API level.
5. Devices are detected automatically. Use the scan icon or Cmd+R to rescan.
   The device-list button in the mirror title bar raises the existing manager.
   Anmir > Devices… (Cmd+Shift+D) opens it as well.
6. Use the Wi-Fi-add icon or Scan QR code → for wireless pairing on Android 11+.
   Scan with Wireless debugging > Pair device with QR code, or use pairing code.
   Paired devices can use Manual connection with the connection IP and port.
7. In Finder, right-click one APK, choose Install on phone, then select a device
   from the submenu. Anmir must be in Applications. If the item is missing, enable
   Anmir Finder in System Settings > General > Login Items & Extensions > Finder.

Settings
The gear in the device list and mirror title bars, or Command-comma, opens Settings.
Theme, display language and floating toolbar visibility update immediately,
save automatically and sync across mirrors. The toolbar is on by default;
an existing saved off choice is preserved. App text switches without losing
pairing input, connections or recordings. macOS permission prompts and native
file dialog controls follow the system language.

First opening
Signing: @SIGNING_STATUS@
Double-click the Privacy & Security shortcut in the DMG or extracted ZIP to open security settings.
If macOS cannot verify the developer, first try opening the app, then use
System Settings > Privacy & Security > Open Anyway if you trust its source.
Apple guidance: https://support.apple.com/102445

Command line
  /Applications/Anmir.app/Contents/MacOS/anmir --help
  /Applications/Anmir.app/Contents/MacOS/anmir --serial <serial>
Explicit selectors, ANDROID_SERIAL and headless modes retain their behavior.
The standalone CLI keeps its English command-line interface.

Anmir is based on scrcpy. See Contents/Resources/LICENSE.
