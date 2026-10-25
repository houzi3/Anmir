# Third-party software

Anmir is based on [scrcpy v4.1](https://github.com/Genymobile/scrcpy/tree/v4.1),
licensed under Apache License 2.0. Original copyright notices are retained in
[LICENSE](LICENSE) and [NOTICE](NOTICE).

The macOS releases bundle these dependencies:

| Component | Version | License | Source |
| --- | --- | --- | --- |
| SDL | 3.4.12 | zlib, with bundled third-party notices | https://github.com/libsdl-org/SDL/tree/release-3.4.12 |
| FFmpeg | 8.1.2 | LGPL-2.1-or-later for the configured build | https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz |
| dav1d | 1.5.3 | BSD-2-Clause | https://code.videolan.org/videolan/dav1d/-/tree/1.5.3 |
| libusb | 1.0.30 | LGPL-2.1-or-later | https://github.com/libusb/libusb/tree/v1.0.30 |
| Android Debug Bridge | Platform Tools 37.0.0 | Apache-2.0 and notices in the upstream distribution | https://android.googlesource.com/platform/packages/modules/adb/ |
| Google Material Icons | Icons adapted in this repository | Apache-2.0 | https://github.com/google/material-design-icons |

`Anmir.app/Contents/Resources/licenses/` contains the redistributed license
texts, including the unmodified Android Platform Tools notice file. FFmpeg is
built without `--enable-gpl`, `--enable-version3` or `--enable-nonfree`.

Each release also provides `Anmir-<version>-source.tar.gz`: the complete Anmir
source, build scripts, applied dependency patches, and original source archives
for SDL, FFmpeg, dav1d and libusb. The source package can be used to rebuild the
application with modified LGPL libraries. See [doc/build-anmir.md](doc/build-anmir.md)
for the build and relinking instructions. Apple system libraries and SDK tools
are supplied by macOS and Xcode.

The Android helper keeps its upstream Java package name for compatibility;
the desktop application's independent bundle identifier is
`io.github.laobie.anmir`.
