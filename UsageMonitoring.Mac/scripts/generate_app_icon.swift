import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? ""
guard !outputPath.isEmpty else {
    fputs("Usage: generate_app_icon.swift <output-png-path>\n", stderr)
    exit(1)
}

let canvasSize = CGSize(width: 1024, height: 1024)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bitmapFormat: [],
    bytesPerRow: 0,
    bitsPerPixel: 0)
else {
    fputs("Failed to create bitmap image\n", stderr)
    exit(1)
}

bitmap.size = canvasSize

guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Failed to create graphics context\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
defer {
    NSGraphicsContext.restoreGraphicsState()
}

let context = graphicsContext.cgContext

context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let bounds = CGRect(origin: .zero, size: canvasSize)
let tileRect = bounds.insetBy(dx: 72, dy: 72)
let shadowRect = tileRect.offsetBy(dx: 0, dy: -18)
let roundedRect = NSBezierPath(roundedRect: tileRect, xRadius: 220, yRadius: 220)
let shadowPath = NSBezierPath(roundedRect: shadowRect, xRadius: 220, yRadius: 220)

NSColor(calibratedWhite: 0, alpha: 0.16).setFill()
shadowPath.fill()

let backgroundGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.17, green: 0.18, blue: 0.20, alpha: 1),
    NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.13, alpha: 1)
])!
backgroundGradient.draw(in: roundedRect, angle: -90)

NSColor(calibratedWhite: 1, alpha: 0.06).setStroke()
roundedRect.lineWidth = 6
roundedRect.stroke()

func drawRing(center: CGPoint, diameter: CGFloat, lineWidth: CGFloat, start: CGFloat, end: CGFloat, color: NSColor, track: NSColor, glowAlpha: CGFloat) {
    let rect = CGRect(
        x: center.x - diameter / 2,
        y: center.y - diameter / 2,
        width: diameter,
        height: diameter)

    let trackPath = NSBezierPath()
    trackPath.appendArc(
        withCenter: center,
        radius: diameter / 2,
        startAngle: 0,
        endAngle: 360,
        clockwise: false)
    track.setStroke()
    trackPath.lineWidth = lineWidth
    trackPath.lineCapStyle = .round
    trackPath.stroke()

    let startAngle = 90 - (start * 360)
    let endAngle = 90 - (end * 360)

    let glowPath = NSBezierPath()
    glowPath.appendArc(
        withCenter: center,
        radius: diameter / 2,
        startAngle: startAngle,
        endAngle: endAngle,
        clockwise: true)
    color.withAlphaComponent(glowAlpha).setStroke()
    glowPath.lineWidth = lineWidth + 18
    glowPath.lineCapStyle = .round
    context.saveGState()
    context.setShadow(offset: .zero, blur: 28, color: color.withAlphaComponent(glowAlpha * 0.9).cgColor)
    glowPath.stroke()
    context.restoreGState()

    let arcPath = NSBezierPath()
    arcPath.appendArc(
        withCenter: center,
        radius: diameter / 2,
        startAngle: startAngle,
        endAngle: endAngle,
        clockwise: true)
    color.setStroke()
    arcPath.lineWidth = lineWidth
    arcPath.lineCapStyle = .round
    arcPath.stroke()

    _ = rect
}

drawRing(
    center: CGPoint(x: 512, y: 568),
    diameter: 404,
    lineWidth: 54,
    start: 0.10,
    end: 0.78,
    color: NSColor(calibratedRed: 18.0 / 255.0, green: 1.0, blue: 166.0 / 255.0, alpha: 1),
    track: NSColor(calibratedRed: 50.0 / 255.0, green: 117.0 / 255.0, blue: 90.0 / 255.0, alpha: 1),
    glowAlpha: 0.34)

drawRing(
    center: CGPoint(x: 512, y: 568),
    diameter: 244,
    lineWidth: 44,
    start: 0.34,
    end: 0.97,
    color: NSColor(calibratedRed: 95.0 / 255.0, green: 232.0 / 255.0, blue: 1.0, alpha: 1),
    track: NSColor(calibratedRed: 45.0 / 255.0, green: 101.0 / 255.0, blue: 112.0 / 255.0, alpha: 1),
    glowAlpha: 0.28)

let centerSquareRect = CGRect(x: 512 - 44, y: 568 - 44, width: 88, height: 88)
let centerSquare = NSBezierPath(roundedRect: centerSquareRect, xRadius: 24, yRadius: 24)
context.saveGState()
context.setShadow(offset: .zero, blur: 20, color: NSColor(calibratedWhite: 1, alpha: 0.24).cgColor)
NSColor(calibratedWhite: 1.0, alpha: 0.96).setFill()
centerSquare.fill()
context.restoreGState()

guard
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: URL(fileURLWithPath: outputPath).deletingLastPathComponent(),
    withIntermediateDirectories: true)
try pngData.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
print("Generated app icon \(Int(canvasSize.width))x\(Int(canvasSize.height)) at \(outputPath)")
