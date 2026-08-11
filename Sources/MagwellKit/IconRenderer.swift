import AppKit

/// Draws the app icon at every size macOS asks for. Vector-drawn rather than exported from a
/// design tool so the small sizes can be simplified deliberately instead of being a blurry
/// downscale of the big one.
///
/// The mark: three cartridges stacked like a clip, the top one already sliding out. Cartridges
/// read at any size, the stack doubles as a list of history rows, and it puts the
/// clip/clipboard pun on screen instead of leaving it in the name.
@MainActor
public enum IconRenderer {

    /// macOS iconset contents. `iconutil` turns these into Magwell.icns.
    private static let sizes: [(name: String, points: Int, scale: Int)] = [
        ("icon_16x16",      16, 1), ("icon_16x16@2x",   16, 2),
        ("icon_32x32",      32, 1), ("icon_32x32@2x",   32, 2),
        ("icon_128x128",   128, 1), ("icon_128x128@2x", 128, 2),
        ("icon_256x256",   256, 1), ("icon_256x256@2x", 256, 2),
        ("icon_512x512",   512, 1), ("icon_512x512@2x", 512, 2),
    ]

    public static func run(outputDirectory: String) {
        let dir = URL(fileURLWithPath: outputDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for (name, points, scale) in sizes {
            guard let data = png(pixels: points * scale) else { continue }
            try? data.write(to: dir.appendingPathComponent("\(name).png"))
        }
        print("Wrote \(sizes.count) icon sizes to \(dir.path)")
        exit(0)
    }

    // MARK: - Drawing

    private static func png(pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(canvas: CGFloat(pixels))
        NSGraphicsContext.current?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    /// All geometry is expressed against a 1024 grid and scaled, so every size is identical in
    /// proportion. Detail that would turn to mud below ~64px is dropped rather than blurred.
    private static func draw(canvas: CGFloat) {
        let unit = canvas / 1024
        func s(_ value: CGFloat) -> CGFloat { value * unit }
        let showsDetail = canvas >= 64

        // — Rounded-square plate, on the standard macOS icon grid (824pt inside 1024).
        let plate = NSRect(x: s(100), y: s(100), width: s(824), height: s(824))
        let plateShape = NSBezierPath(roundedRect: plate, xRadius: s(185), yRadius: s(185))

        NSGradient(colors: [
            NSColor(srgbRed: 0.24, green: 0.27, blue: 0.32, alpha: 1),
            NSColor(srgbRed: 0.09, green: 0.10, blue: 0.13, alpha: 1),
        ])?.draw(in: plateShape, angle: -90)

        if showsDetail {
            // Faint top-edge sheen, the way a machined surface catches light.
            NSGraphicsContext.saveGraphicsState()
            plateShape.setClip()
            NSGradient(colors: [NSColor.white.withAlphaComponent(0.16),
                                NSColor.white.withAlphaComponent(0.0)])?
                .draw(in: NSRect(x: plate.minX, y: plate.midY,
                                 width: plate.width, height: plate.height / 2), angle: -90)
            NSGraphicsContext.restoreGraphicsState()

            plateShape.lineWidth = s(3)
            NSColor.white.withAlphaComponent(0.14).setStroke()
            plateShape.stroke()
        }

        drawCartridges(unit: unit, showsDetail: showsDetail)
    }

    private static func drawCartridges(unit: CGFloat, showsDetail: Bool) {
        func s(_ value: CGFloat) -> CGFloat { value * unit }

        let brass = NSGradient(colors: [
            NSColor(srgbRed: 1.00, green: 0.85, blue: 0.47, alpha: 1),
            NSColor(srgbRed: 0.79, green: 0.50, blue: 0.11, alpha: 1),
        ])
        let copper = NSGradient(colors: [
            NSColor(srgbRed: 0.98, green: 0.72, blue: 0.45, alpha: 1),
            NSColor(srgbRed: 0.68, green: 0.35, blue: 0.12, alpha: 1),
        ])

        let height = s(116)
        let width = s(496)
        let nose = s(150)
        let baseX = s(250)

        // The top round sits proud of the stack: it's the one queued up to paste.
        let rows: [(y: CGFloat, offset: CGFloat)] = [
            (s(596), s(58)),
            (s(448), 0),
            (s(300), 0),
        ]

        for row in rows {
            let x = baseX + row.offset

            let caseRect = NSRect(x: x, y: row.y, width: width - nose, height: height)
            brass?.draw(in: NSBezierPath(roundedRect: caseRect, xRadius: s(18), yRadius: s(18)),
                        angle: -90)

            // Extractor rim — the detail that stops a cartridge reading as a lozenge.
            if showsDetail {
                let rim = NSBezierPath(roundedRect: NSRect(x: x - s(14), y: row.y - s(9),
                                                           width: s(40), height: height + s(18)),
                                       xRadius: s(14), yRadius: s(14))
                brass?.draw(in: rim, angle: -90)
                rim.lineWidth = s(4)
                NSColor.black.withAlphaComponent(0.22).setStroke()
                rim.stroke()
            }

            // Bullet: an ogive nose, not a triangle.
            let noseStart = caseRect.maxX - s(6)
            let tip = NSPoint(x: x + width, y: row.y + height / 2)
            let bullet = NSBezierPath()
            bullet.move(to: NSPoint(x: noseStart, y: row.y))
            bullet.curve(to: tip,
                         controlPoint1: NSPoint(x: noseStart + nose * 0.72, y: row.y + height * 0.02),
                         controlPoint2: NSPoint(x: tip.x, y: row.y + height * 0.22))
            bullet.curve(to: NSPoint(x: noseStart, y: row.y + height),
                         controlPoint1: NSPoint(x: tip.x, y: row.y + height * 0.78),
                         controlPoint2: NSPoint(x: noseStart + nose * 0.72, y: row.y + height * 0.98))
            bullet.close()
            copper?.draw(in: bullet, angle: -90)
        }
    }
}
