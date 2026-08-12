import AppKit

/// The menu bar glyph, optionally carrying an "update waiting" dot.
///
/// Drawn as a *template* image so the menu bar tints it itself — that is what keeps it correct
/// in light mode, dark mode, and while the item is highlighted. A coloured dot would look
/// deliberate in one of those and wrong in the other two.
///
/// The dot sits *beside* the glyph rather than on it. `doc.on.clipboard` is a solid filled
/// shape whose top-right corner is exactly where a badge wants to go: a black dot there is
/// invisible against black, and the transparent moat needed to separate them reads as a bite
/// taken out of the icon. Widening the canvas costs a few points of menu bar and leaves the
/// glyph untouched.
@MainActor
enum StatusItemIcon {

    private static let symbolName = "doc.on.clipboard"

    /// Diameter of the dot and the gap between it and the glyph. Small on purpose: a status
    /// hint, not a notification badge demanding a click.
    private static let dotDiameter: CGFloat = 3
    private static let gap: CGFloat = 1.5

    static func image(badged: Bool) -> NSImage? {
        guard let base = NSImage(systemSymbolName: symbolName,
                                 accessibilityDescription: "ClipIt") else { return nil }
        base.isTemplate = true
        guard badged else { return base }

        let glyph = base.size
        let canvas = NSImage(size: NSSize(width: glyph.width + gap + dotDiameter,
                                          height: glyph.height))
        canvas.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: glyph))

        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: glyph.width + gap,
                                    y: glyph.height - dotDiameter,
                                    width: dotDiameter,
                                    height: dotDiameter)).fill()

        canvas.unlockFocus()
        canvas.isTemplate = true
        return canvas
    }
}
