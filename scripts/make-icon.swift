// Малює іконку DiskHealth і збирає Resources/AppIcon.icns.
// Запуск: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        .applying(.init(paletteColors: [.white]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Сітка іконок macOS: тіло 824/1024 з відступом 100.
    let inset = s * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.set()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.05, green: 0.62, blue: 0.55, alpha: 1),
        NSColor(calibratedRed: 0.04, green: 0.33, blue: 0.52, alpha: 1),
    ])!.draw(in: path, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    // Диск.
    let drive = symbol("internaldrive.fill", pointSize: body.width * 0.36, weight: .regular)
    let dw = body.width * 0.62
    let dh = dw * drive.size.height / drive.size.width
    drive.draw(in: NSRect(x: body.midX - dw / 2, y: body.minY + body.height * 0.45, width: dw, height: dh))

    // Пульс під диском.
    let pulse = NSBezierPath()
    let y = body.minY + body.height * 0.25
    let x0 = body.minX + body.width * 0.18
    let w = body.width * 0.64
    let points: [(CGFloat, CGFloat)] = [(0, 0), (0.30, 0), (0.38, 0.09), (0.46, -0.11), (0.54, 0.13), (0.62, 0), (1, 0)]
    for (i, p) in points.enumerated() {
        let pt = NSPoint(x: x0 + p.0 * w, y: y + p.1 * body.height)
        i == 0 ? pulse.move(to: pt) : pulse.line(to: pt)
    }
    pulse.lineWidth = body.width * 0.045
    pulse.lineCapStyle = .round
    pulse.lineJoinStyle = .round
    NSColor(calibratedRed: 0.55, green: 1.0, blue: 0.6, alpha: 1).setStroke()
    pulse.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try render(1024).write(to: root.appendingPathComponent("Resources/AppIcon-preview.png"))

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "Resources/AppIcon.icns готово" : "iconutil помилка \(p.terminationStatus)")
