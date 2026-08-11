import AppKit

/// Draws the app icon at every size macOS asks for. Vector-drawn rather than exported from a
/// design tool so the small sizes can be simplified deliberately instead of being a blurry
/// downscale of the big one.
///
/// The mark: a clipboard whose rows show what it holds — text, images and files — with a badge
/// in the corner. A lone clip shape was tried and read as a padlock; sheets ghosted behind the
/// board turned to mush below 64px.
@MainActor
public enum IconRenderer {

    /// macOS iconset contents. `iconutil` turns these into the .icns.
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
    /// proportion. Detail that would turn to mud below ~128px is dropped rather than blurred.
    private static func draw(canvas: CGFloat) {
        let unit = canvas / 1024
        func s(_ value: CGFloat) -> CGFloat { value * unit }
        let showsDetail = canvas >= 128
        let showsRows = canvas >= 48

        // — Plate, on the standard macOS icon grid (824pt inside 1024).
        let plate = NSRect(x: s(100), y: s(100), width: s(824), height: s(824))
        let plateShape = NSBezierPath(roundedRect: plate, xRadius: s(185), yRadius: s(185))
        NSGradient(colors: [
            NSColor(srgbRed: 0.48, green: 0.68, blue: 0.97, alpha: 1),
            NSColor(srgbRed: 0.23, green: 0.44, blue: 0.86, alpha: 1),
        ])?.draw(in: plateShape, angle: -90)

        if showsDetail {
            plateShape.lineWidth = s(6)
            NSColor.white.withAlphaComponent(0.28).setStroke()
            plateShape.stroke()
        }

        drawClipboard(unit: unit, showsDetail: showsDetail, showsRows: showsRows)
        if showsRows { drawBadge(unit: unit, showsDetail: showsDetail) }
    }

    // MARK: - Clipboard

    private static func drawClipboard(unit: CGFloat, showsDetail: Bool, showsRows: Bool) {
        func s(_ value: CGFloat) -> CGFloat { value * unit }

        let ink = NSColor(srgbRed: 0.16, green: 0.38, blue: 0.80, alpha: 1)
        let clipBlue = NSGradient(colors: [
            NSColor(srgbRed: 0.55, green: 0.74, blue: 0.99, alpha: 1),
            NSColor(srgbRed: 0.31, green: 0.55, blue: 0.92, alpha: 1),
        ])

        // Board, sitting large in the frame — a small mark floating in a big plate is the
        // single biggest thing that makes an icon look amateur.
        let board = NSRect(x: s(244), y: s(150), width: s(500), height: s(672))
        let boardShape = NSBezierPath(roundedRect: board, xRadius: s(58), yRadius: s(58))

        if showsDetail {
            NSGraphicsContext.saveGraphicsState()
            let dropShadow = NSShadow()
            dropShadow.shadowColor = NSColor(srgbRed: 0.08, green: 0.20, blue: 0.45, alpha: 0.45)
            dropShadow.shadowBlurRadius = s(40)
            dropShadow.shadowOffset = NSSize(width: 0, height: -s(14))
            dropShadow.set()
            NSColor.black.setFill()
            boardShape.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        NSGradient(colors: [NSColor.white,
                            NSColor(srgbRed: 0.90, green: 0.94, blue: 0.99, alpha: 1)])?
            .draw(in: boardShape, angle: -90)

        // Clip: a bar across the top plus a tab standing proud of the board.
        clipBlue?.draw(in: NSBezierPath(roundedRect: NSRect(x: s(354), y: s(736),
                                                            width: s(280), height: s(116)),
                                        xRadius: s(38), yRadius: s(38)), angle: -90)
        clipBlue?.draw(in: NSBezierPath(roundedRect: NSRect(x: s(424), y: s(812),
                                                            width: s(140), height: s(104)),
                                        xRadius: s(46), yRadius: s(46)), angle: -90)
        if showsDetail {
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: NSRect(x: s(462), y: s(842), width: s(64), height: s(64))).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        }

        guard showsRows else { return }

        // Three rows, one per kind of thing ClipIt holds: text, images, files. Below 128px the
        // glyphs are dropped and the lines widen, which still reads as a filled page.
        let rowYs: [CGFloat] = [s(560), s(408), s(256)]
        for (index, y) in rowYs.enumerated() {
            if showsDetail {
                ink.setFill()
                ink.setStroke()
                drawGlyph(index: index, origin: NSPoint(x: s(300), y: y), unit: unit)
            }

            NSColor(srgbRed: 0.72, green: 0.79, blue: 0.89, alpha: 1).setFill()
            let lineX = showsDetail ? s(432) : s(310)
            let fullWidth = showsDetail ? s(232) : s(354)
            for line in 0..<2 {
                let width = line == 0 ? fullWidth : fullWidth * 0.72
                NSBezierPath(roundedRect: NSRect(x: lineX, y: y + (line == 0 ? s(62) : s(6)),
                                                 width: width, height: s(40)),
                             xRadius: s(20), yRadius: s(20)).fill()
            }
        }
    }

    /// Row markers: T for text, a picture for images, angle brackets for files and code.
    private static func drawGlyph(index: Int, origin: NSPoint, unit: CGFloat) {
        func s(_ value: CGFloat) -> CGFloat { value * unit }
        let box = NSRect(x: origin.x, y: origin.y, width: s(104), height: s(104))

        switch index {
        case 0:
            // T: a crossbar and a stem, drawn as rects so it stays crisp.
            NSBezierPath(rect: NSRect(x: box.minX + s(6), y: box.maxY - s(26),
                                      width: box.width - s(12), height: s(26))).fill()
            NSBezierPath(rect: NSRect(x: box.midX - s(13), y: box.minY,
                                      width: s(26), height: box.height - s(26))).fill()
        case 1:
            // Picture: frame, sun, hill.
            let frame = NSBezierPath(roundedRect: box.insetBy(dx: s(4), dy: s(10)),
                                     xRadius: s(16), yRadius: s(16))
            frame.lineWidth = s(16)
            frame.stroke()
            NSBezierPath(ovalIn: NSRect(x: box.minX + s(26), y: box.maxY - s(46),
                                        width: s(22), height: s(22))).fill()
            let hill = NSBezierPath()
            hill.move(to: NSPoint(x: box.minX + s(18), y: box.minY + s(26)))
            hill.line(to: NSPoint(x: box.midX + s(2), y: box.midY + s(10)))
            hill.line(to: NSPoint(x: box.maxX - s(18), y: box.minY + s(26)))
            hill.close()
            hill.fill()
        default:
            // < / >
            let stroke = NSBezierPath()
            stroke.lineWidth = s(18)
            stroke.lineCapStyle = .round
            stroke.lineJoinStyle = .round
            stroke.move(to: NSPoint(x: box.minX + s(30), y: box.maxY - s(20)))
            stroke.line(to: NSPoint(x: box.minX, y: box.midY))
            stroke.line(to: NSPoint(x: box.minX + s(30), y: box.minY + s(20)))
            stroke.move(to: NSPoint(x: box.maxX - s(30), y: box.maxY - s(20)))
            stroke.line(to: NSPoint(x: box.maxX, y: box.midY))
            stroke.line(to: NSPoint(x: box.maxX - s(30), y: box.minY + s(20)))
            stroke.stroke()
        }
    }

    // MARK: - Badge

    /// Straddles the board's bottom-right corner, which is what makes it read as a badge
    /// rather than a sticker printed on the page.
    private static func drawBadge(unit: CGFloat, showsDetail: Bool) {
        func s(_ value: CGFloat) -> CGFloat { value * unit }

        let centre = NSPoint(x: s(742), y: s(246))
        let radius = s(118)
        let circle = NSRect(x: centre.x - radius, y: centre.y - radius,
                            width: radius * 2, height: radius * 2)

        if showsDetail {
            NSGraphicsContext.saveGraphicsState()
            let dropShadow = NSShadow()
            dropShadow.shadowColor = NSColor(srgbRed: 0.06, green: 0.16, blue: 0.38, alpha: 0.5)
            dropShadow.shadowBlurRadius = s(26)
            dropShadow.shadowOffset = NSSize(width: 0, height: -s(8))
            dropShadow.set()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: circle).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        NSGradient(colors: [NSColor(srgbRed: 0.99, green: 1.00, blue: 1.00, alpha: 1),
                            NSColor(srgbRed: 0.86, green: 0.91, blue: 0.98, alpha: 1)])?
            .draw(in: NSBezierPath(ovalIn: circle), angle: -90)

        // U+F8FF is the Apple logo in Apple's system fonts. It renders nowhere else, which is
        // fine for a Mac-only app. Note: Apple's identity guidelines forbid using their logo in
        // third-party app icons — swap this for "⌘" or the app's initial to be safe.
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: s(132)),
            .foregroundColor: NSColor(srgbRed: 0.13, green: 0.22, blue: 0.38, alpha: 1),
        ]
        let mark = NSAttributedString(string: "\u{F8FF}", attributes: attributes)
        let bounds = mark.size()
        mark.draw(at: NSPoint(x: centre.x - bounds.width / 2, y: centre.y - bounds.height / 2))
    }
}
