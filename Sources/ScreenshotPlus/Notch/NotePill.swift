import AppKit

/// The small dark "note" chip that follows the screenshot during a drag,
/// so it's obvious the prompt travels with the image.
enum NotePill {
    static func image(for note: String) -> NSImage {
        let text = note.replacingOccurrences(of: "\n", with: " ")
        let font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
        ]
        let iconWidth: CGFloat = 16
        let maxTextWidth: CGFloat = 220
        let measured = (text as NSString).size(withAttributes: attributes)
        let textWidth = min(ceil(measured.width), maxTextWidth)
        let size = NSSize(width: textWidth + iconWidth + 26, height: 24)

        return NSImage(size: size, flipped: false) { rect in
            let pill = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
            NSColor(white: 0.12, alpha: 0.96).setFill()
            pill.fill()
            NSColor.white.withAlphaComponent(0.14).setStroke()
            pill.stroke()

            if let symbol = NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold)
                    .applying(.init(paletteColors: [NSColor(red: 1, green: 0.78, blue: 0.32, alpha: 1)]))) {
                let s = symbol.size
                symbol.draw(in: NSRect(x: 10, y: (rect.height - s.height) / 2, width: s.width, height: s.height))
            }
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            var attrs = attributes
            attrs[.paragraphStyle] = style
            (text as NSString).draw(
                with: NSRect(x: 10 + iconWidth, y: (rect.height - measured.height) / 2 - 1, width: textWidth, height: measured.height + 2),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs
            )
            return true
        }
    }
}
