// Original application artwork, GPL-3.0. Rebuild with: swift Scripts/generate-icon.swift Assets
import AppKit
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Assets", isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let set = root.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
func drawIcon() {
    let tile = NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 207, yRadius: 207)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.25); shadow.shadowBlurRadius = 22; shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.set()
    rgb(0.055, 0.09, 0.17).setFill(); tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [rgb(0.14, 0.22, 0.36), rgb(0.055, 0.09, 0.17)])!.draw(in: tile, angle: -65)
    let rim = NSBezierPath(ovalIn: NSRect(x: 196, y: 196, width: 632, height: 632))
    rgb(0.62, 0.92, 1, 0.16).setStroke(); rim.lineWidth = 24; rim.stroke()
    let orbit = NSBezierPath(); orbit.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 316, startAngle: 31, endAngle: 302, clockwise: false)
    rgb(0.13, 0.85, 0.96).setStroke(); orbit.lineWidth = 25; orbit.lineCapStyle = .round; orbit.stroke()
    for i in 0..<8 {
        let a = (Double(i) * 45 + 22.5) * Double.pi / 180
        let x = 512 + 370 * cos(a), y = 512 + 370 * sin(a)
        NSGraphicsContext.saveGraphicsState()
        let t = AffineTransform(translationByX: x, byY: y); (t as NSAffineTransform).concat()
        let rot = NSAffineTransform(); rot.rotate(byDegrees: CGFloat(Double(i) * 45 + 22.5)); rot.concat()
        rgb(0.75, 0.87, 0.98, i == 0 || i == 4 ? 0.85 : 0.35).setFill()
        NSBezierPath(roundedRect: NSRect(x: -10, y: -26, width: 20, height: 52), xRadius: 10, yRadius: 10).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    let slide = NSBezierPath(); slide.move(to: NSPoint(x: 301, y: 302))
    slide.curve(to: NSPoint(x: 722, y: 702), controlPoint1: NSPoint(x: 389, y: 290), controlPoint2: NSPoint(x: 512, y: 726))
    rgb(0.19, 0.91, 0.98).setStroke(); slide.lineWidth = 34; slide.lineCapStyle = .round; slide.stroke()
    for (x, y) in [(310.0, 304.0), (470.0, 465.0)] {
        let note = NSBezierPath(ovalIn: NSRect(x: x - 43, y: y - 43, width: 86, height: 86))
        rgb(0.10, 0.16, 0.26).setFill(); note.fill()
        rgb(1, 0.28, 0.63).setStroke(); note.lineWidth = 21; note.stroke()
    }
    let star = NSBezierPath()
    for i in 0..<10 {
        let a = (90 + Double(i) * 36) * Double.pi / 180
        let r = i % 2 == 0 ? 94.0 : 45.0
        let p = NSPoint(x: 716 + r * cos(a), y: 703 + r * sin(a))
        if i == 0 { star.move(to: p) } else { star.line(to: p) }
    }
    star.close(); star.lineJoinStyle = .round; star.lineWidth = 8
    rgb(1, 0.79, 0.22).setFill(); star.fill(); rgb(1, 0.89, 0.49).setStroke(); star.stroke()
}
func render(_ pixels: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(); NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: set.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: set.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(1024).write(to: root.appendingPathComponent("AppIcon.png"))
