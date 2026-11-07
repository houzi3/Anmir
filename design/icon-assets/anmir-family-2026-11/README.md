# Anmir icon family

Approved source assets for the Mac app, the Anmir Connect Android app, and
APK documents. These are integrated into the application and release packages.

| Asset | Mac app | Android app | APK file |
| --- | --- | --- | --- |
| PNG master | `mac-app.png` | `connect-app.png` | `connect-apk-file.png` |

The Mac and Connect PNGs are the approved transparent masters. About, update
prompts and READMEs reuse `app/data/anmir.png`; application launchers use the
platform-specific backgrounds and safe margins generated from these masters.
The APK document keeps its separate green-and-white artwork.

Rebuild the Mac app, Dock, mirror, generic PNG and Windows icons with:

```sh
swift release/generate_macos_icons.swift
```

Rebuild the dedicated Finder APK icon with:

```sh
swift release/generate_apk_icon.swift
```

Rebuild the Android foreground and monochrome layers with:

```sh
swift release/generate_companion_icons.swift
```

The APK ICNS is bundled as `anmir-apk.icns`, referenced by the host app's APK
document type, and used in the APK installation windows. Success and failure
indicators retain their status symbols. Android uses separate adaptive
foreground, background and monochrome layers with a launcher-safe inset.

The Mac concept includes an Apple logo at the user's request. Apple states that
use of its logo in connection with third-party products requires an express
written trademark license; remove or replace it for distribution unless the
appropriate rights are in place. See [Apple's trademark guidelines](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html).
