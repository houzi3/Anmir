# Anmir icon family

Approved source assets for the Mac app, the Anmir Connect Android app, and
APK documents. These are integrated into the application and release packages.

| Asset | Mac app | Android app | APK file |
| --- | --- | --- | --- |
| Editable vector | `mac-app.svg` | `connect-app.svg` | `connect-apk-file.svg` |
| 1024×1024 preview | `mac-app.png` | `connect-app.png` | `connect-apk-file.png` |
| Original image generation output | `mac-app-source.png` | `connect-app-source.png` | `connect-apk-file-source.png` |

The final APK artwork uses a folded document, Android head and APK lettering in
jade green and white. `connect-apk-file-source.png` and
`connect-apk-file-flat.png` preserve the exact user-approved attachment;
`connect-apk-file.png` is its 1024px export. The image was edited with the built-in
image generation tool; the final prompt is in `connect-apk-file-flat-prompt.txt`.

The image-generation output was raster, not SVG. Each SVG is an editable
vector reconstruction of the selected PNG using independent shapes and paths;
it is not a pixel-identical original or an embedded raster. The APK file PNG and
SVG have transparent backgrounds. The other icons use opaque backgrounds.

Rebuild the Mac app, Dock, mirror and generic icons with:

```sh
swift release/generate_macos_icons.swift --import-png design/icon-assets/anmir-family-2026-11/mac-app.png
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
