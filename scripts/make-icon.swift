// Draws the app icon (a black notch dropping a screenshot) into an .iconset.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(colors: [NSColor(white: 0.20, alpha: 1), NSColor(white: 0.07, alpha: 1)])!.draw(in: tilePath, angle: -90)

    // Notch
    let notchW = tile.width * 0.46, notchH = tile.height * 0.15
    let notch = NSRect(x: tile.midX - notchW / 2, y: tile.maxY - notchH, width: notchW, height: notchH)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: notch.insetBy(dx: 0, dy: -notchH * 0.5).offsetBy(dx: 0, dy: notchH * 0.5),
                 xRadius: notchH * 0.6, yRadius: notchH * 0.6).fill()
    NSBezierPath(rect: NSRect(x: notch.minX, y: tile.maxY - notchH * 0.4, width: notchW, height: notchH * 0.4)).fill()

    // Screenshot card
    let cardW = tile.width * 0.52, cardH = cardW * 0.68
    let card = NSRect(x: tile.midX - cardW / 2, y: tile.minY + tile.height * 0.2, width: cardW, height: cardH)
    let shadow = NSShadow()
    shadow.shadowBlurRadius = s * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(white: 0.96, alpha: 1).setFill()
    NSBezierPath(roundedRect: card, xRadius: cardW * 0.07, yRadius: cardW * 0.07).fill()
    NSGraphicsContext.restoreGraphicsState()
    let inner = card.insetBy(dx: cardW * 0.07, dy: cardW * 0.07)
    NSColor(red: 0.38, green: 0.62, blue: 1, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.midY, width: inner.width, height: inner.height / 2),
                 xRadius: cardW * 0.03, yRadius: cardW * 0.03).fill()
    NSColor(white: 0.78, alpha: 1).setFill()
    for i in 0..<2 {
        let w = inner.width * (i == 0 ? 0.8 : 0.55)
        NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY + CGFloat(i) * inner.height * 0.2 + inner.height * 0.04,
                                         width: w, height: inner.height * 0.1), xRadius: 2, yRadius: 2).fill()
    }
    // Note badge
    let badgeR = cardW * 0.16
    let badge = NSRect(x: card.maxX - badgeR * 1.2, y: card.maxY - badgeR * 1.2, width: badgeR * 2, height: badgeR * 2)
    NSColor(red: 1, green: 0.78, blue: 0.32, alpha: 1).setFill()
    NSBezierPath(ovalIn: badge).fill()
    NSColor.black.setStroke()
    let plus = NSBezierPath()
    plus.lineWidth = badgeR * 0.28
    plus.lineCapStyle = .round
    plus.move(to: NSPoint(x: badge.midX - badgeR * 0.45, y: badge.midY)); plus.line(to: NSPoint(x: badge.midX + badgeR * 0.45, y: badge.midY))
    plus.move(to: NSPoint(x: badge.midX, y: badge.midY - badgeR * 0.45)); plus.line(to: NSPoint(x: badge.midX, y: badge.midY + badgeR * 0.45))
    plus.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try draw(size).write(to: output.appendingPathComponent("icon_\(size)x\(size).png"))
    try draw(size * 2).write(to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
