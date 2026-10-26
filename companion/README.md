# Anmir Connect

Native Android 11+ companion for Anmir’s company-network QR pairing.

- Application ID and namespace: `io.github.houzi3.anmir.connect`.
- UI: compact charcoal / mint layout, English and Chinese resources.
- Start helper → actual local listener readiness → brief success dialog → Android Developer options.
- Developer options opens in Settings’ own task; Anmir Connect keeps its own Activity stack.
- Anmir Connect asks Settings to scroll to and highlight Wireless debugging; vendor Settings may ignore the optional hints and open the usual developer page.
- The system wireless-debugging scanner performs QR pairing; this app has no camera or screen-capture access.
- Before pairing, a helper run lasts up to five minutes. After a Mac is registered, the connected-device foreground service stays running until stopped.
- Wi-Fi changes rebuild local discovery; fresh connection ports are reported to the remembered Mac without rescanning.
- Retry now bypasses retry backoff. Stop retains the saved Mac; Forget saved Mac removes its callback credentials.
- Requires Anmir 0.1.2 or later on the Mac. Wireless debugging must remain enabled; a changed Mac address requires a new QR scan. Reboot or force-stop requires starting the helper again.

User setup: [English](../doc/company-network.md) · [中文](../doc/company-network.zh-CN.md).

Release APK: [GitHub download page](https://github.com/houzi3/Anmir/releases/tag/v0.1.2).
The phone instructions use `1.` and `2.`; the Mac download link opens this page in
the browser beside its installation caption.

## Build

Use Java 17+ and the repository’s existing Android SDK / Gradle wrapper:

```sh
./gradlew :companion:assembleDebug :companion:lintDebug
```

APK: `build/outputs/apk/debug/companion-debug.apk`.

The release uses the maintainer's fixed Android signing key; see [release signing](../doc/build-anmir.md#anmir-connect-release-signing). Uninstall earlier debug-signed previews once before installing the release APK.

Package changes create a separate Android application. Remove the old
`io.github.laobie.anmir.connect` test build after installing this package.

## Verification

Pure Java protocol tests and connected-device startup/lifecycle smoke-test commands
are documented in [company-network.md](../doc/company-network.md#build-and-test).
The smoke test opens Developer options, returns to the helper, and verifies stop /
restart. It does not pair a device or change wireless debugging.

Some OEMs require a normal on-device installation confirmation even for ADB
installs. Confirm installation of both the app and its test APK before running the
test. Notification permission, if requested, is handled through the standard
system permission UI. No permission-grant shell override is required.

## Assets

The launcher foreground is a transparent PNG generated from the approved compact
design and packaged as an
Android adaptive icon. The UI uses native Android widgets and actual text.

The success check drawable is from the Android Open Source Project
(`platforms/android-36/data/res/drawable/ic_check_24dp.xml`, Apache 2.0); its
copyright and license notice are retained in the resource file.
