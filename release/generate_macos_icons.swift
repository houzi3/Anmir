// Build macOS presentation icons from the approved full-size artwork.
// Run: swift release/generate_macos_icons.swift [source.png] [output-dir] [preview-dir]
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
let sourceURL = !paths.isEmpty ? URL(fileURLWithPath: paths[0]) : root.appendingPathComponent("design/icon-assets/anmir-family-2026-11/mac-app.png")
let output = paths.count > 1 ? URL(fileURLWithPath: paths[1]) : root.appendingPathComponent("app/data")
let previews = paths.count > 2 ? URL(fileURLWithPath: paths[2]) : root.appendingPathComponent("output/icon-diagnostics")

func require<T>(_ value: T?, _ message: String) -> T {
    guard let value else { fatalError(message) }
    return value
}
let colorSpace = require(CGColorSpace(name: CGColorSpace.sRGB), "Cannot create sRGB space")

func foreground(_ url: URL) -> CGImage {
    let source = require(CGImageSourceCreateWithURL(url as CFURL, nil), "Cannot read source artwork")
    let largest = (0..<CGImageSourceGetCount(source)).max { a, b in
        let first = CGImageSourceCopyPropertiesAtIndex(source, a, nil) as? [CFString: Any]
        let second = CGImageSourceCopyPropertiesAtIndex(source, b, nil) as? [CFString: Any]
        return (first?[kCGImagePropertyPixelWidth] as? Int ?? 0) < (second?[kCGImagePropertyPixelWidth] as? Int ?? 0)
    }
    let image = require(CGImageSourceCreateImageAtIndex(source, require(largest, "Empty source artwork"), nil), "Cannot decode artwork")
    precondition(image.width == image.height, "Artwork must be square")
    let context = require(CGContext(data: nil, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: colorSpace,
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue), "Cannot decode pixels")
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let pixels = require(context.data, "Missing pixels").bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
    var left = image.width, top = image.height, right = -1, bottom = -1
    for y in 0..<image.height {
        for x in 0..<image.width where pixels[(y * image.width + x) * 4 + 3] > 8 {
            left = min(left, x); right = max(right, x)
            top = min(top, y); bottom = max(bottom, y)
        }
    }
    precondition(right >= left && bottom >= top, "Empty artwork")
    return require(context.makeImage()?.cropping(to: CGRect(x: left, y: top,
        width: right - left + 1, height: bottom - top + 1)), "Cannot crop artwork")
}
let artwork = foreground(sourceURL)

func framed(_ image: CGImage, fraction: Double, background: Bool = true, bundle: Bool = false) -> CGImage {
    let size = 1024
    let context = require(CGContext(data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace,
        bitmapInfo: (bundle ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue), "Cannot create bitmap")
    context.interpolationQuality = .high
    if background {
        context.setFillColor(CGColor(srgbRed: 241 / 255, green: 243 / 255, blue: 245 / 255, alpha: 1))
        if bundle {
            // Icon Services applies the system mask to full-bleed launch assets.
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        } else {
            let tile = CGRect(x: 102.4, y: 102.4, width: 819.2, height: 819.2)
            context.addPath(CGPath(roundedRect: tile, cornerWidth: 184.32, cornerHeight: 184.32, transform: nil))
            context.fillPath()
        }
    }
    let scale = Double(size) * fraction / Double(max(image.width, image.height))
    let width = Double(image.width) * scale, height = Double(image.height) * scale
    context.draw(image, in: CGRect(x: (Double(size) - width) / 2,
        y: (Double(size) - height) / 2, width: width, height: height))
    return require(context.makeImage(), "Cannot export bitmap")
}

func render(mirror: Bool, bundle: Bool = false) -> CGImage {
    let size = 1024
    let base = framed(artwork, fraction: bundle ? 0.75 : 0.60, bundle: bundle)
    guard mirror else { return base }
    let context = require(CGContext(data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace,
        bitmapInfo: (bundle ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue), "Cannot create bitmap")
    context.interpolationQuality = .high
    context.draw(base, in: CGRect(x: 0, y: 0, width: size, height: size))
    // A compact circular badge reads as window metadata instead of another app.
    // The bundle variant stays farther inside the system mask used at launch.
    let badge = bundle ? CGRect(x: 792, y: 92, width: 168, height: 168)
        : CGRect(x: 790, y: 50, width: 200, height: 200)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -5), blur: 16,
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.22))
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fillEllipse(in: badge)
    context.restoreGState()
    context.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.12))
    context.setLineWidth(4)
    context.strokeEllipse(in: badge.insetBy(dx: 2, dy: 2))

    let phoneWidth = badge.width * 0.40
    let phoneHeight = badge.height * 0.64
    let phone = CGRect(x: badge.midX - phoneWidth / 2, y: badge.midY - phoneHeight / 2,
        width: phoneWidth, height: phoneHeight)
    let dark = CGColor(srgbRed: 0.07, green: 0.09, blue: 0.12, alpha: 1)
    context.setFillColor(dark)
    context.addPath(CGPath(roundedRect: phone, cornerWidth: phoneWidth * 0.23,
        cornerHeight: phoneWidth * 0.23, transform: nil))
    context.fillPath()
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.addPath(CGPath(roundedRect: phone.insetBy(dx: phoneWidth * 0.18, dy: phoneHeight * 0.13),
        cornerWidth: phoneWidth * 0.08, cornerHeight: phoneWidth * 0.08, transform: nil))
    context.fillPath()
    context.setStrokeColor(dark)
    context.setLineWidth(max(5, phoneWidth * 0.08))
    context.setLineCap(.round)
    for y in [phone.maxY - phoneHeight * 0.16, phone.minY + phoneHeight * 0.16] {
        context.move(to: CGPoint(x: phone.midX - phoneWidth * 0.12, y: y))
        context.addLine(to: CGPoint(x: phone.midX + phoneWidth * 0.12, y: y))
    }
    context.strokePath()
    return require(context.makeImage(), "Cannot export bitmap")
}

func resized(_ image: CGImage, to size: Int) -> CGImage {
    let opaque = image.alphaInfo == .none || image.alphaInfo == .noneSkipFirst || image.alphaInfo == .noneSkipLast
    let context = require(CGContext(data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace,
        bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue), "Cannot resize bitmap")
    context.interpolationQuality = .high
    // Resample the completed master so all representations share one silhouette.
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return require(context.makeImage(), "Cannot export resized bitmap")
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil), "Cannot write PNG")
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination), "Cannot finalize PNG")
}

func encodedPNG(_ image: CGImage) -> Data {
    let data = NSMutableData()
    let destination = require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil), "Cannot encode PNG")
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination), "Cannot finalize PNG")
    return data as Data
}

func appendBigEndian(_ value: UInt32, to data: inout Data) {
    var encoded = value.bigEndian
    withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
}

func writeICNS(_ images: [Int: CGImage], to url: URL) throws {
    let representations: [(String, Int)] = [
        ("icp4", 16), ("ic11", 32),
        ("icp5", 32), ("ic12", 64),
        ("ic07", 128), ("ic13", 256),
        ("ic08", 256), ("ic14", 512),
        ("ic09", 512), ("ic10", 1024),
    ]
    var chunks = Data()
    for (type, pixels) in representations {
        let png = encodedPNG(require(images[pixels], "Missing \(pixels)-pixel representation"))
        chunks.append(contentsOf: type.utf8)
        appendBigEndian(UInt32(png.count + 8), to: &chunks)
        chunks.append(png)
    }
    var icon = Data("icns".utf8)
    appendBigEndian(UInt32(chunks.count + 8), to: &icon)
    icon.append(chunks)
    try icon.write(to: url, options: .atomic)
}

try files.createDirectory(at: output, withIntermediateDirectories: true)
try files.createDirectory(at: previews, withIntermediateDirectories: true)
var masters: [(String, CGImage)] = [("anmir", render(mirror: false, bundle: true))]
do {
    let pngURL = output.appendingPathComponent("anmir.png")
    writePNG(resized(framed(artwork, fraction: 0.9, background: false), to: 256), to: pngURL)
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
    var images: [Int: CGImage] = [1024: master]
    for pixels in [16, 32, 64, 128, 256, 512] { images[pixels] = resized(master, to: pixels) }
    try writeICNS(images, to: output.appendingPathComponent(name + ".icns"))
    for pixels in [64, 256, 1024] {
        writePNG(images[pixels]!, to: previews.appendingPathComponent("\(name)-\(pixels).png"))
    }
    print(output.appendingPathComponent(name + ".icns").path)
}
