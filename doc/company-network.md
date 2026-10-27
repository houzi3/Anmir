# Company-network QR pairing

[中文说明](company-network.zh-CN.md)

Verified on 2026-10-26 with OnePlus KB2000 / Android 14 and a Mac on different
company subnets. The existing Wi-Fi ADB transport was disconnected before the
system QR scan. The new session then performed ADB pairing, connected using the
discovered connection port, and opened mirroring without typing an IP or port.
Local builds, Android lint and the targeted regression tests also passed.

This optional flow uses Anmir Connect on Android 11 or later when the phone and
Mac can communicate by IP but the network does not forward mDNS between their
subnets. It requires no network configuration, root, camera permission or
accessibility service. It uses Android's system wireless-debugging scanner.

## Use

The release APK uses a fixed signing key. Uninstall earlier preview builds once before installing the release; their debug signatures cannot update to this signing identity in place. Later release updates retain the same key.

The Android application ID is `io.github.houzi3.anmir.connect`. This is a separate
application from the earlier `io.github.laobie.anmir.connect` test build; remove
that old helper after installing the new one to avoid duplicate launcher icons.

1. In Anmir's Wi-Fi dialog, choose **Company network connection** and click **Open download page**.
   Select the Anmir Connect APK matching your Mac version from the release page, or find it in the
   [release list](https://github.com/houzi3/Anmir/releases). Transfer the APK to your phone and open it with the system file manager, allowing
   installation from that source if prompted. Alternatively, with an existing
   USB or Wi-Fi ADB connection, use `adb -s DEVICE install -r APK`. Skip installation if the helper is already installed.
2. Keep the company-network QR window open. If the Mac has multiple physical network addresses,
   select the address reachable from the phone.
3. On the phone, open the **Anmir Connect** app, then tap **Start helper**. After the local listener is
   ready, **Helper started** appears briefly and Developer options opens automatically.
4. Open **Wireless debugging → Pair device with QR code**, and scan the Mac's code.
   Anmir receives the current ports, pairs and opens mirroring automatically.

Keep wireless debugging enabled. Each company-network QR expires after five minutes. Before pairing,
the helper also stops after five minutes. Once Anmir Connect receives the Mac’s verified registration,
it keeps the foreground helper running for automatic reconnection. When notifications are
allowed, its notification offers a Stop action; stopping from the app is always
available. It does not start on boot. If a code expires, refresh it and scan again.
Changing the phone's IP or debugging ports does not require updating a saved
address: automatic callbacks report the current values after registration, with QR scanning retained as a recovery option.

Anmir Connect passes AOSP Settings’ optional preference-highlight arguments for `toggle_adb_wireless`, bringing Wireless debugging into view on supported devices. Vendor Settings may ignore these hints; the ordinary Developer options page remains available.

Developer options opens in Settings’ own task, keeping Anmir Connect’s Activity
stack separate. Returning to Anmir Connect does not open Settings again. While the helper runs,
**Open Developer options** and **Stop helper** remain available. Stopping the helper
does not disable wireless debugging or disconnect an established mirror. If startup
fails, the app stays on its page and shows the error instead of claiming success.

Both directions must be reachable: phone → Mac for the callback, and Mac → phone
for ADB. A network that blocks incoming connections on the Mac, translates the
phone's source address, or isolates clients can still prevent this flow. This
version advertises a physical-interface IPv4 address. IPv6-only networks are not
supported by the callback flow; standard pairing remains available.

If standard QR pairing does not discover the phone, the waiting screen offers
**Company network connection** and **Fix connection**. The latter asks before
restarting the Mac's shared ADB service, which may interrupt other mirroring and
debugging sessions. After a restart, scan the new QR code. An empty discovery
list alone does not prove that the network blocks mDNS.

## Protocol and boundaries

The QR remains an Android `WIFI:T:ADB;S:…;P:…;;` payload. Its service instance name
has the form `studio-anmir1-<8 hex IPv4>-<4 hex port>-<32 hex session>` (60 bytes,
within the DNS label limit). Android starts its standard pairing server. The
helper discovers `_adb-tls-pairing._tcp` and `_adb-tls-connect._tcp` **on the phone**,
using a Wi-Fi-bound multicast listener and a bounded multicast lock. Only packets
sent from the phone's own Wi-Fi address are accepted. Reading SRV records directly
avoids waiting for framework NSD resolution callbacks that did not arrive on the
tested Android 14 device. Current connection ports are checked locally before
being reported, so stale advertisements do not choose a closed port.

The helper POSTs bounded JSON metadata to `/v1/relay/<session>` on the Mac. It
reports the exact QR service name, pairing port, and connection service names and
ports. The Mac derives the phone's IP from the TCP peer, never a supplied address.
It matches the connection service to the GUID returned by successful ADB pairing.
The callback does not carry the ADB pairing password, host private keys, screen
contents or shell commands. Its session identifier correlates the QR and callback;
ADB's password-authenticated pairing and TLS remain the authentication boundary.

Before pairing, the callback listener is active only in company QR mode and stops on code refresh, expiry, mode switch or dialog close. After verified ADB pairing, connection and physical-device identification, the Mac hands the listener to a reconnect coordinator independent of the QR window. It rotates the bootstrap token into an independent 128-bit reconnect token bound to the paired GUID and physical identity. For 30 seconds the original route returns `201` with `{reconnect:{port,token,guid}}` only to the initial phone’s TCP address. After that it returns `410`; the new `/v1/reconnect/<token>` route accepts only connection services matching the paired GUID, or an empty list while wireless debugging is unavailable.

The phone saves the numeric host from its original QR plus the issued port, token and GUID in app-private preferences with backup disabled. The Mac saves the registered route, physical identity and last verified endpoint in its app preferences, and reopens the same port on restart. It never persists the pairing password or host private keys in these preferences. A fresh scan of the same physical phone revokes its old callback route. No company subnets or port ranges are scanned.

The phone uses a Wi-Fi NetworkCallback to rebuild its local listener and discard old-port caches when the Network or IPv4 address changes. Stable reports run every 15 seconds and local queries every 10 seconds; failures back off at 2, 4, 8, 16 and at most 30 seconds. A new observed endpoint resets this wait. Retry now sends a bounded authenticated `retry:true` report and bypasses both phone and Mac retry deadlines. The Mac checks the ADB transport, reconnects to fresh reported ports and verifies the physical identity again before restoring an interrupted mirror. An intentional successful mirror exit clears the restore intent; restarting the Mac app restores registrations, not an old window-opening intent. An active reconnect registration keeps the host app’s event loop alive when its device window closes; Quit stops runtime listeners.

Stopping the phone helper retains the saved Mac but pauses all callbacks. Forget saved Mac clears the phone’s callback credentials without revoking Android’s ADB pairing. The phone remembers one Mac, and the Mac remembers up to eight phones. There is no boot receiver or automatic foreground-service resurrection after force-stop. Android may disable wireless debugging or defer networking in Doze; users must enable debugging themselves and may wake the phone or tap Retry now. A changed Mac IP, occupied callback port or blocked LAN still requires intervention.

## Build and test

```sh
# Java 17+ and the existing Android SDK / Gradle wrapper are required.
./gradlew :companion:assembleDebug
# Output: companion/build/outputs/apk/debug/companion-debug.apk

# Connected-device UI smoke test (opens Developer options; does not pair a device).
./gradlew :companion:assembleDebugAndroidTest
adb -s DEVICE install -r companion/build/outputs/apk/debug/companion-debug.apk
adb -s DEVICE install -r companion/build/outputs/apk/androidTest/debug/companion-debug-androidTest.apk
adb -s DEVICE shell am instrument -w io.github.houzi3.anmir.connect.test/io.github.houzi3.anmir.connect.CompanionSmokeTest

meson test -C build-debug test_device_relay test_device_reconnect test_device_wifi \
    test_device_pairing test_device_connection test_localization --print-errorlogs

mkdir -p build-company-validation/java-tests
javac -d build-company-validation/java-tests \
    companion/src/main/java/io/github/houzi3/anmir/connect/RelaySession.java \
    companion/src/main/java/io/github/houzi3/anmir/connect/LocalMdns.java \
    companion/src/main/java/io/github/houzi3/anmir/connect/ReconnectTarget.java \
    companion/src/main/java/io/github/houzi3/anmir/connect/RelayHttp.java \
    companion/tests/RelaySessionTest.java companion/tests/LocalMdnsTest.java \
    companion/tests/ReconnectTest.java
java -ea -cp build-company-validation/java-tests \
    io.github.houzi3.anmir.connect.RelaySessionTest
java -ea -cp build-company-validation/java-tests \
    io.github.houzi3.anmir.connect.LocalMdnsTest
java -ea -cp build-company-validation/java-tests \
    io.github.houzi3.anmir.connect.ReconnectTest
```

Pass `--companion PATH_TO_APK` to `release/build_macos_app.sh` to bundle an APK.
The debug APK is for local validation. Release signing and CI configuration are described in [the build guide](build-anmir.md#anmir-connect-release-signing).

For real-device acceptance, an existing ADB connection may be used to install the
helper. Disconnect that phone before the scan. Verify that the new QR triggers
an actual `adb pair`, followed by `adb connect`, device verification and mirroring.
An existing Wi-Fi connection alone is not evidence that this flow works. Repeat
with a refreshed QR, and after the phone's wireless debugging port changes.
