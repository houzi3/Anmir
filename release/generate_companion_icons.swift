// Export the approved Connect artwork as independent adaptive-icon layers.
// Run: swift release/generate_companion_icons.swift [source.png] [resource-dir]
import Foundation
import CoreGraphics
import ImageIO

func require<T>(_ value: T?, _ message: String) -> T {
    guard let value else { fatalError(message) }
    return value
}

let root = URL(fileURLWithPath: #filePath).standardizedFileURL
    .deletingLastPathComponent().deletingLastPathComponent()
let arguments = Array(CommandLine.arguments.dropFirst())
precondition(arguments.count <= 2, "Usage: generate_companion_icons.swift [source.png] [resource-dir]")
let sourceURL = arguments.isEmpty
    ? root.appendingPathComponent("design/icon-assets/anmir-family-2026-11/connect-app.png")
    : URL(fileURLWithPath: arguments[0])
let resources = arguments.count > 1
    ? URL(fileURLWithPath: arguments[1])
    : root.appendingPathComponent("companion/src/main/res")
let source = require(CGImageSourceCreateWithURL(sourceURL as CFURL, nil), "Cannot read approved artwork")
let image = require(CGImageSourceCreateImageAtIndex(source, 0, nil), "Cannot decode artwork")
precondition(image.width == image.height, "Artwork must be square")
let width = image.width
let height = image.height
let colorSpace = require(CGColorSpace(name: CGColorSpace.sRGB), "Cannot create sRGB space")
let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
let context = require(CGContext(data: nil, width: width, height: height,
    bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
    bitmapInfo: bitmapInfo), "Cannot decode RGBA pixels")
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
let pixels = require(context.data, "Missing pixels").bindMemory(to: UInt8.self, capacity: width * height * 4)

// The approved master already has alpha. Preserve black device frames;
// only transparent pixels connected to the outside are backdrop.
func isBackground(_ index: Int) -> Bool {
    let offset = index * 4
    return pixels[offset + 3] < 8
}
var outside = [Bool](repeating: false, count: width * height)
var queue: [Int] = []
func enqueue(_ index: Int) {
    if !outside[index] && isBackground(index) {
        outside[index] = true
        queue.append(index)
    }
}
for x in 0..<width { enqueue(x); enqueue((height - 1) * width + x) }
for y in 0..<height { enqueue(y * width); enqueue(y * width + width - 1) }
var cursor = 0
while cursor < queue.count {
    let index = queue[cursor]
    cursor += 1
    let x = index % width
    let y = index / width
    if x > 0 { enqueue(index - 1) }
    if x + 1 < width { enqueue(index + 1) }
    if y > 0 { enqueue(index - width) }
    if y + 1 < height { enqueue(index + width) }
}
var minX = width, minY = height, maxX = 0, maxY = 0
for index in 0..<(width * height) {
    let offset = index * 4
    if outside[index] {
        for channel in 0..<4 { pixels[offset + channel] = 0 }
    } else {
        minX = min(minX, index % width); maxX = max(maxX, index % width)
        minY = min(minY, index / width); maxY = max(maxY, index / width)
    }
}
let foreground = require(context.makeImage(), "Cannot export cutout")
let centerX = Double(minX + maxX) / 2
let centerY = Double(minY + maxY) / 2
var radius = 0.0
for index in 0..<(width * height) where !outside[index] {
    radius = max(radius, hypot(Double(index % width) - centerX, Double(index / width) - centerY))
}
// 108dp canvas at xxxhdpi. Keep the complete phone and monitor within the
// central 64dp circle, so circular and other launcher masks preserve the art.
let size = 432
let scale = 128.0 / radius
let destination = CGRect(x: 216 - centerX * scale,
    y: 216 - centerY * scale, width: Double(width) * scale, height: Double(height) * scale)

func render(_ artwork: CGImage) -> CGImage {
    let output = require(CGContext(data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace,
        bitmapInfo: bitmapInfo), "Cannot create adaptive layer")
    output.interpolationQuality = .high
    output.draw(artwork, in: destination)
    return require(output.makeImage(), "Cannot export adaptive layer")
}
func writePNG(_ image: CGImage, name: String) throws {
    let directory = resources.appendingPathComponent("drawable-nodpi")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name + ".png")
    let output = require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil), "Cannot write PNG")
    CGImageDestinationAddImage(output, image, nil)
    precondition(CGImageDestinationFinalize(output), "Cannot finalize PNG")
    print(url.path)
}
try writePNG(render(foreground), name: "icon_foreground")

// The in-app header must show the approved artwork itself, without an
// adaptive-icon background or launcher mask. Crop the same cutout into a
// compact transparent square so it remains legible at 64dp.
let headerSize = 320
let headerPadding = 20.0
let artworkWidth = Double(maxX - minX + 1)
let artworkHeight = Double(maxY - minY + 1)
let headerScale = min((Double(headerSize) - headerPadding * 2) / artworkWidth,
    (Double(headerSize) - headerPadding * 2) / artworkHeight)
let headerDestination = CGRect(
    x: Double(headerSize) / 2 - centerX * headerScale,
    y: Double(headerSize) / 2 - centerY * headerScale,
    width: Double(width) * headerScale,
    height: Double(height) * headerScale)
let headerContext = require(CGContext(data: nil, width: headerSize, height: headerSize,
    bitsPerComponent: 8, bytesPerRow: headerSize * 4, space: colorSpace,
    bitmapInfo: bitmapInfo), "Cannot create header artwork")
headerContext.interpolationQuality = .high
headerContext.draw(foreground, in: headerDestination)
try writePNG(require(headerContext.makeImage(), "Cannot export header artwork"), name: "header_logo")

// A themed icon uses shape alpha only: silver outlines and the green Android
// become white, while screens and white eye cutouts remain transparent.
for index in 0..<(width * height) {
    let offset = index * 4
    let r = Int(pixels[offset]), g = Int(pixels[offset + 1]), b = Int(pixels[offset + 2])
    let isAndroid = g > 90 && Double(g) > Double(r) * 1.8 && Double(g) > Double(b) * 1.2
    let isFrame = max(r, g, b) < 225 && max(r, g, b) - min(r, g, b) < 80
    let isEye = min(r, g, b) > 225
    let alpha: UInt8 = !outside[index] && (isAndroid || isFrame) && !isEye ? 255 : 0
    for channel in 0..<4 { pixels[offset + channel] = alpha }
}
try writePNG(render(require(context.makeImage(), "Cannot export monochrome art")), name: "icon_monochrome")
print("Complete foreground fits the central 64dp safe circle on a 108dp adaptive canvas.")
