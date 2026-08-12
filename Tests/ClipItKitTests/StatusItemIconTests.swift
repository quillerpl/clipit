import XCTest
import AppKit
@testable import ClipItKit

@MainActor
final class StatusItemIconTests: XCTestCase {

    func testPlainGlyphIsATemplate() throws {
        let image = try XCTUnwrap(StatusItemIcon.image(badged: false))

        XCTAssertTrue(image.isTemplate, "a non-template glyph would not tint with the menu bar")
    }

    func testBadgedGlyphIsAlsoATemplateAndDiffers() throws {
        let plain = try XCTUnwrap(StatusItemIcon.image(badged: false))
        let badged = try XCTUnwrap(StatusItemIcon.image(badged: true))

        XCTAssertTrue(badged.isTemplate)
        XCTAssertNotEqual(badged.tiffRepresentation, plain.tiffRepresentation)
        // The dot lives beside the glyph, so the canvas has to grow to hold it — cropped to the
        // plain width, the mark would simply not be there.
        XCTAssertGreaterThan(badged.size.width, plain.size.width)
        XCTAssertEqual(badged.size.height, plain.size.height,
                       "a taller glyph would shrink to fit the menu bar and shift everything")
    }

    /// Not an assertion — writes both glyphs, scaled up on a menu-bar-ish backdrop, so the
    /// badge can actually be looked at. Off unless CLIPIT_ICON_DUMP points somewhere.
    func testDumpGlyphsForInspection() throws {
        guard let directory = ProcessInfo.processInfo.environment["CLIPIT_ICON_DUMP"] else { return }

        for (name, badged) in [("plain", false), ("badged", true)] {
            let source = try XCTUnwrap(StatusItemIcon.image(badged: badged))
            let scale: CGFloat = 16
            let target = NSSize(width: source.size.width * scale, height: source.size.height * scale)

            let canvas = NSImage(size: target)
            canvas.lockFocus()
            NSColor(white: 0.82, alpha: 1).setFill()          // stand-in for the menu bar
            NSBezierPath(rect: NSRect(origin: .zero, size: target)).fill()
            NSGraphicsContext.current?.imageInterpolation = .none
            source.draw(in: NSRect(origin: .zero, size: target))
            canvas.unlockFocus()

            let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(canvas.tiffRepresentation))?
                .representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
    }
}
