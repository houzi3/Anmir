# Anmir icon family

Design assets for the Mac app, the Anmir Connect Android app, and an Anmir
Connect APK file. These are concepts; they do not replace the icons used by the
build or change how an APK appears in Finder.

| Asset | Mac app | Android app | APK file |
| --- | --- | --- | --- |
| Editable vector | `mac-app.svg` | `connect-app.svg` | `connect-apk-file.svg` |
| 1024×1024 preview | `mac-app.png` | `connect-app.png` | `connect-apk-file.png` |
| Original image generation output | `mac-app-source.png` | `connect-app-source.png` | `connect-apk-file-source.png` |

The image-generation output was raster, not SVG. Each SVG is an editable
vector reconstruction of the selected PNG using independent shapes and paths;
it is not a pixel-identical original or an embedded raster. The APK file PNG and
SVG have transparent backgrounds. The other icons use opaque backgrounds.

The Android concept needs separate adaptive-icon foreground, background, and
optional monochrome layers, plus device-mask and safe-area verification before
it is used as a launcher icon. The APK file concept needs a separate file-icon
integration for the intended distribution environment.

The Mac concept includes an Apple logo at the user's request. Apple states that
use of its logo in connection with third-party products requires an express
written trademark license; remove or replace it for distribution unless the
appropriate rights are in place. See [Apple's trademark guidelines](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html).
