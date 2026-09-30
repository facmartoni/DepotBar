import AppKit

// MARK: - Glass status-bar icon (theme `glass`: frosted capsule + glyph)

enum StatusIconArt {
    static let size = NSSize(width: 26, height: 22)

    /// Frosted-glass capsule with the current status glyph (or spinner frame)
    /// centered. All colors adapt to the menu bar: translucent white capsule,
    /// glyph in the adaptive label color.
    static func glassImage(for status: MenuPresentation.StatusIcon) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            let capsule = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
            NSColor.white.withAlphaComponent(0.18).setFill()
            capsule.fill()
            NSColor.white.withAlphaComponent(0.35).setStroke()
            capsule.lineWidth = 1
            capsule.stroke()

            switch status {
            case .spinner(let frame):
                let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.labelColor,
                ]
                let text = NSAttributedString(string: frame, attributes: attrs)
                let textSize = text.size()
                text.draw(at: NSPoint(
                    x: rect.midX - textSize.width / 2,
                    y: rect.midY - textSize.height / 2
                ))
            case .symbol(let name):
                if let glyph = NSImage(systemSymbolName: name, accessibilityDescription: "Depot CI") {
                    glyph.isTemplate = true
                    let side: CGFloat = 14
                    NSColor.labelColor.set()
                    glyph.draw(in: NSRect(
                        x: rect.midX - side / 2,
                        y: rect.midY - side / 2,
                        width: side, height: side
                    ))
                }
            }
            return true
        }
    }
}
