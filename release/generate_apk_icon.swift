// Convert the approved APK document artwork into Finder's multi-resolution icon.
// swift release/generate_apk_icon.swift [source.png] [output.icns] [preview-dir]
import Foundation
import CoreGraphics
import ImageIO

func require<T>(_ value: T?, _ message: String) -> T {
    guard let value else { fatalError(message) }
    return value
}

let files = FileManager.default
let root = URL(fileURLWithPath: #filePath).standardizedFileURL
    .deletingLastPathComponent().deletingLastPathComponent()
let paths = Array(CommandLine.arguments.dropFirst())
precondition(paths.count <= 3, "Usage: generate_apk_icon.swift [source.png] [output.icns] [preview-dir]")
let assets = root.appendingPathComponent("design/icon-assets/anmir-family-2026-11")
let sourceURL = paths.count > 0 ? URL(fileURLWithPath: paths[0])
    : assets.appendingPathComponent("connect-apk-file-source.png")
let outputURL = paths.count > 1 ? URL(fileURLWithPath: paths[1])
    : root.appendingPathComponent("app/data/anmir-apk.icns")
let previews = paths.count > 2 ? URL(fileURLWithPath: paths[2])
    : root.appendingPathComponent("output/icon-family-integration")
let source = require(CGImageSourceCreateWithURL(sourceURL as CFURL, nil), "Cannot read APK artwork")
let artwork = require(CGImageSourceCreateImageAtIndex(source, 0, nil), "Cannot decode APK artwork")
precondition(artwork.width == artwork.height, "APK artwork must be square")
let colorSpace = require(CGColorSpace(name: CGColorSpace.sRGB), "Cannot create sRGB space")

func resized(to size: Int) -> CGImage {
    let context = require(CGContext(data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), "Cannot resize APK artwork")
    context.interpolationQuality = .high
    // Preserve the document's transparent margins and approved proportions.
    context.draw(artwork, in: CGRect(x: 0, y: 0, width: size, height: size))
    return require(context.makeImage(), "Cannot export APK artwork")
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = require(CGImageDestinationCreateWithURL(url as CFURL,
        "public.png" as CFString, 1, nil), "Cannot write PNG")
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination), "Cannot finalize PNG")
}

try files.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try files.createDirectory(at: previews, withIntermediateDirectories: true)
let temporary = files.temporaryDirectory.appendingPathComponent("AnmirAPK-" + UUID().uuidString)
let iconset = temporary.appendingPathComponent("anmir-apk.iconset")
try files.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? files.removeItem(at: temporary) }
var images: [Int: CGImage] = [:]
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        if images[pixels] == nil { images[pixels] = resized(to: pixels) }
        let suffix = scale == 2 ? "@2x" : ""
        writePNG(images[pixels]!, to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
let tool = Process()
tool.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
tool.arguments = ["-c", "icns", iconset.path, "-o", outputURL.path]
try tool.run()
tool.waitUntilExit()
precondition(tool.terminationStatus == 0, "iconutil failed")
for pixels in [32, 64, 256, 1024] {
    writePNG(images[pixels]!, to: previews.appendingPathComponent("anmir-apk-\(pixels).png"))
}
writePNG(images[1024]!, to: assets.appendingPathComponent("connect-apk-file.png"))
print(outputURL.path)
