// Renders assets/AppIcon.icns. Run from the repository root:
//
//   swift assets/make-icon.swift
//
// Three desktops, the middle one active, on a dark tile. Drawn on Apple's 1024pt icon grid.

import AppKit

func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

func roundedBold(_ size: CGFloat) -> NSFont {
    let font = NSFont.systemFont(ofSize: size, weight: .bold)
    guard let descriptor = font.fontDescriptor.withDesign(.rounded) else { return font }
    return NSFont(descriptor: descriptor, size: size) ?? font
}

func drawNumber(_ text: String, in rect: NSRect, size: CGFloat, color: NSColor) {
    let font = roundedBold(size)
    let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    let width = string.size().width
    let baseline = rect.midY - font.capHeight / 2
    string.draw(at: NSPoint(x: rect.midX - width / 2, y: baseline + font.descender))
}

// Shadows are not scaled by the context transform, so they take the pixel scale explicitly
func withShadow(scale: CGFloat, blur: CGFloat, offset: CGFloat, alpha: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
    shadow.shadowOffset = NSSize(width: 0, height: -offset * scale)
    shadow.shadowBlurRadius = blur * scale
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

func drawIcon(scale: CGFloat) {
    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    withShadow(scale: scale, blur: 28, offset: 12, alpha: 0.35) {
        rgb(0x15161F).setFill()
        body.fill()
    }
    NSGradient(starting: rgb(0x33364D), ending: rgb(0x14151E))!.draw(in: body, angle: -90)

    for (number, x) in [(1, 246.0), (3, 778.0)] {
        let rect = NSRect(x: x - 80, y: 432, width: 160, height: 160)
        rgb(0xFFFFFF, 0.13).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 38, yRadius: 38).fill()
        drawNumber("\(number)", in: rect, size: 92, color: rgb(0xFFFFFF, 0.45))
    }

    let active = NSRect(x: 362, y: 362, width: 300, height: 300)
    let activePath = NSBezierPath(roundedRect: active, xRadius: 68, yRadius: 68)
    withShadow(scale: scale, blur: 40, offset: 14, alpha: 0.45) {
        rgb(0xB04DDB).setFill()
        activePath.fill()
    }
    NSGradient(starting: rgb(0xFF4D8D), ending: rgb(0x7C4DFF))!.draw(in: activePath, angle: -45)
    drawNumber("2", in: active, size: 196, color: .white)
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let scale = CGFloat(pixels) / 1024
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)
    drawIcon(scale: scale)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try! png(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try! png(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "assets/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
