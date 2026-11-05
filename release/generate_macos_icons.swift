// Build macOS presentation icons from the approved full-size artwork.
// Run: swift release/generate_macos_icons.swift [source.icns] [output-dir] [preview-dir]
// Import approved artwork and rebuild the macOS, generic PNG and Windows icons:
//   swift release/generate_macos_icons.swift --import-png artwork.png [output-dir] [preview-dir]
// CoreGraphics/ImageIO render pixels locally: no AppKit, Dock or Icon Services cache.
import Foundation
import CoreGraphics
import ImageIO

let files = FileManager.default
let root = URL(fileURLWithPath: #filePath).standardizedFileURL
    .deletingLastPathComponent().deletingLastPathComponent()
let args = CommandLine.arguments
let importing = args.dropFirst().first == "--import-png"
let paths = Array(args.dropFirst(importing ? 2 : 1))
if paths.count > 3 || (importing && paths.isEmpty) {
    fatalError("Usage: swift generate_macos_icons.swift [--import-png] [source] [output-dir] [preview-dir]")
}
let sourceURL = !paths.isEmpty ? URL(fileURLWithPath: paths[0]) : root.appendingPathComponent("app/data/anmir.icns")
let output = paths.count > 1 ? URL(fileURLWithPath: paths[1]) : root.appendingPathComponent("app/data")
let previews = paths.count > 2 ? URL(fileURLWithPath: paths[2]) : root.appendingPathComponent("output/icon-diagnostics")

func require<T>(_ value: T?, _ message: String) -> T {
    guard let value else { fatalError(message) }
    return value
}
let source = require(CGImageSourceCreateWithURL(sourceURL as CFURL, nil), "Cannot read source artwork")
let largest = (0..<CGImageSourceGetCount(source)).max { a, b in
    let first = CGImageSourceCopyPropertiesAtIndex(source, a, nil) as? [CFString: Any]
    let second = CGImageSourceCopyPropertiesAtIndex(source, b, nil) as? [CFString: Any]
    return (first?[kCGImagePropertyPixelWidth] as? Int ?? 0) < (second?[kCGImagePropertyPixelWidth] as? Int ?? 0)
}
let decoded = require(CGImageSourceCreateImageAtIndex(source, require(largest, "Empty source artwork"), nil), "Cannot decode source artwork")
precondition(decoded.width == decoded.height, "Artwork must be square")
let colorSpace = require(CGColorSpace(name: CGColorSpace.sRGB), "Cannot create sRGB space")
let artwork = importing ? resized(decoded, to: 1024) : decoded
precondition(artwork.width == 1024 && artwork.height == 1024, "Expected 1024 × 1024 source artwork")
// Keep the established 20-pixel source margin trim when applying the runtime
// alpha mask. The approved white artwork uses the same foreground framing;
// trimming only this background margin preserves its scale and geometry.
let cropped = require(artwork.cropping(to: CGRect(x: 20, y: 20, width: 984, height: 984)), "Cannot crop artwork")
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 184, cornerHeight: 184, transform: nil)

func render(mirror: Bool, bundle: Bool = false) -> CGImage {
    let size = 1024
    let context = require(CGContext(data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace,
        bitmapInfo: (bundle ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue), "Cannot create bitmap")
    context.interpolationQuality = .high
    if bundle {
        // Icon Services on macOS 26+ encloses non-square legacy artwork in a
        // gray tile. Keep this launch/fallback icon full bleed with an inset
        // phone, so its system-normalized result retains the original scale.
        context.draw(artwork, in: CGRect(x: 0, y: 0, width: size, height: size))
    } else {
        // Every direct-drawing representation has the same transparent silhouette.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 20,
            color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.16))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.addPath(tilePath)
        context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(tilePath)
        context.clip()
        context.draw(cropped, in: tile)
        context.restoreGState()
    }

    if mirror {
        if bundle {
            context.translateBy(x: 704, y: 80)
            context.scaleBy(x: 256.0 / 304, y: 256.0 / 304)
            context.translateBy(x: -704, y: -16)
        }
        // Preserve the existing phone badge geometry on a 1024-pixel canvas.
        // Both the bundle fallback and the runtime image contain the phone.
        let badge = CGPath(roundedRect: CGRect(x: 704, y: 16, width: 304, height: 304),
            cornerWidth: 72, cornerHeight: 72, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -4), blur: 20,
            color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.2))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.addPath(badge)
        context.fillPath()
        context.restoreGState()
        context.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.12))
        context.setLineWidth(4)
        context.addPath(badge)
        context.strokePath()
        context.setStrokeColor(CGColor(srgbRed: 0.07, green: 0.09, blue: 0.12, alpha: 1))
        context.setLineWidth(12)
        context.addPath(CGPath(roundedRect: CGRect(x: 804, y: 72, width: 104, height: 192),
            cornerWidth: 20, cornerHeight: 20, transform: nil))
        context.strokePath()
        context.setLineWidth(8)
        context.setLineCap(.round)
        for y in [244.0, 92.0] {
            context.move(to: CGPoint(x: 840, y: y))
            context.addLine(to: CGPoint(x: 872, y: y))
        }
        context.strokePath()
    }
    return require(context.makeImage(), "Cannot export bitmap")
}

func resized(_ image: CGImage, to size: Int) -> CGImage {
    let opaque = image.alphaInfo == .none || image.alphaInfo == .noneSkipFirst || image.alphaInfo == .noneSkipLast
    let context = require(CGContext(data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace,
        bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue), "Cannot resize bitmap")
    context.interpolationQuality = .high
    // CGContext shadows are specified in device space. Resample the completed
    // master so the shadow and subpixel badge strokes scale with the artwork.
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return require(context.makeImage(), "Cannot export resized bitmap")
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil), "Cannot write PNG")
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination), "Cannot finalize PNG")
}

try files.createDirectory(at: output, withIntermediateDirectories: true)
try files.createDirectory(at: previews, withIntermediateDirectories: true)
let temporary = files.temporaryDirectory.appendingPathComponent("AnmirIcons-" + UUID().uuidString)
try files.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? files.removeItem(at: temporary) }
var masters: [(String, CGImage)] = []
if importing {
    masters.append(("anmir", artwork))
    let pngURL = output.appendingPathComponent("anmir.png")
    writePNG(resized(artwork, to: 256), to: pngURL)
    // The existing Windows resource is a one-frame 256px PNG-backed ICO.
    // Rewrap the identical generic PNG bytes; do not rasterize it a second time.
    let png = try Data(contentsOf: pngURL)
    var ico = Data([0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 32, 0])
    for value in [UInt32(png.count), UInt32(22)] {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { ico.append(contentsOf: $0) }
    }
    ico.append(png)
    try ico.write(to: output.appendingPathComponent("icon.ico"), options: .atomic)
}
masters += [("anmir-dock", render(mirror: false)),
            ("anmir-mirror", render(mirror: true)),
            ("anmir-mirror-bundle", render(mirror: true, bundle: true))]
for (name, master) in masters {
    let iconset = temporary.appendingPathComponent(name + ".iconset")
    try files.createDirectory(at: iconset, withIntermediateDirectories: true)
    var images: [Int: CGImage] = [1024: master]
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = points * scale
            if images[pixels] == nil { images[pixels] = resized(master, to: pixels) }
            let suffix = scale == 2 ? "@2x" : ""
            writePNG(images[pixels]!, to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
        }
    }
    let tool = Process()
    tool.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    tool.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent(name + ".icns").path]
    try tool.run()
    tool.waitUntilExit()
    precondition(tool.terminationStatus == 0, "iconutil failed")
    for pixels in [64, 256, 1024] {
        writePNG(images[pixels]!, to: previews.appendingPathComponent("\(name)-\(pixels).png"))
    }
    print(output.appendingPathComponent(name + ".icns").path)
}
