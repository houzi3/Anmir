// Render the Finder installation background without third-party dependencies.
import AppKit

let size = NSSize(width: 600, height: 330)
guard CommandLine.arguments.count == 2,
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 660,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
        bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Usage: swift macos-dmg-background.swift <output.png>")
}
bitmap.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.cgContext.scaleBy(x: 2, y: 2)

NSColor(calibratedRed: 0.965, green: 0.973, blue: 0.977, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

func text(_ value: String, x: CGFloat = 44, y: CGFloat, size: CGFloat,
          weight: NSFont.Weight, gray: CGFloat,
          alignment: NSTextAlignment = .left, width: CGFloat? = nil) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    (value as NSString).draw(
        in: NSRect(x: x, y: y, width: width ?? 600 - x * 2, height: 30),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor(calibratedWhite: gray, alpha: 1),
            .paragraphStyle: paragraph,
        ])
}

text("Anmir", y: 270, size: 22, weight: .semibold, gray: 0.14)
text("Drag to Applications to install.", y: 244, size: 12,
     weight: .regular, gray: 0.43)

// One shared surface ties the source and destination into a single action.
let tray = NSBezierPath(roundedRect: NSRect(x: 32, y: 120, width: 536, height: 118),
                        xRadius: 20, yRadius: 20)
NSColor.white.setFill()
tray.fill()
NSColor(calibratedRed: 0.90, green: 0.92, blue: 0.93, alpha: 1).setStroke()
tray.lineWidth = 0.75
tray.stroke()

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 282, y: 190))
arrow.line(to: NSPoint(x: 318, y: 190))
arrow.move(to: NSPoint(x: 311, y: 197))
arrow.line(to: NSPoint(x: 318, y: 190))
arrow.line(to: NSPoint(x: 311, y: 183))
arrow.lineWidth = 1.5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
NSColor(calibratedRed: 0.22, green: 0.56, blue: 0.42, alpha: 1).setStroke()
arrow.stroke()

// Finder supplies a real shortcut icon beside this secondary help area.
let help = NSBezierPath(roundedRect: NSRect(x: 32, y: 6, width: 536, height: 96),
                        xRadius: 16, yRadius: 16)
NSColor.white.withAlphaComponent(0.6).setFill()
help.fill()
text("Can't open? Privacy & Security → Open Anyway.", x: 48, y: 58, size: 10.5,
     weight: .regular, gray: 0.43, width: 330)
text("无法打开？双击右侧入口 → 仍要打开。", x: 48, y: 32, size: 10.5,
     weight: .regular, gray: 0.43, width: 330)

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode the installation background")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
