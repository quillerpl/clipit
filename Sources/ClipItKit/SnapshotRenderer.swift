import AppKit
import SwiftUI

/// `ClipIt --snapshot <dir>` seeds illustrative history, renders each panel offscreen over a
/// backdrop, and writes PNGs for the README.
///
/// These are the real SwiftUI views with sample data, not mock-ups — but they are composited
/// over a synthetic wallpaper rather than captured from a live desktop, because the app is
/// `LSUIElement` and its panels can't be screen-captured conventionally.
@MainActor
public enum SnapshotRenderer {

    public static func run(outputDirectory: String) {
        let dir = URL(fileURLWithPath: outputDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Snapshots composite inside one window, so the material must blend within it.
        VisualEffectBackground.blendsWithinWindow = true

        seedStore()
        AppSettings.shared.viewMode = .list

        write(PanelPreview(panel: NSSize(width: HistoryView.width, height: HistoryView.preferredHeight(itemCount: 7, hasSearch: true))) { HistoryPreview() },
              panel: NSSize(width: HistoryView.width,
                            height: HistoryView.preferredHeight(itemCount: 7, hasSearch: true)),
              margin: NSSize(width: 170, height: 90),
              to: dir.appendingPathComponent("list.png"))

        write(PanelPreview(panel: NSSize(width: 940, height: CardDrawerView.height)) { DrawerPreview() },
              panel: NSSize(width: 940, height: CardDrawerView.height),
              margin: NSSize(width: 90, height: 90),
              to: dir.appendingPathComponent("cards.png"))

        write(PanelPreview(panel: NSSize(width: QuickSwitcherView.width, height: QuickSwitcherView.height)) { SwitcherPreview() },
              panel: NSSize(width: QuickSwitcherView.width, height: QuickSwitcherView.height),
              margin: NSSize(width: 150, height: 110),
              to: dir.appendingPathComponent("switcher.png"))

        write(PanelPreview(panel: NSSize(width: 460, height: 520), cornerRadius: 12, light: true) { WelcomePreview() },
              panel: NSSize(width: 460, height: 520),
              margin: NSSize(width: 130, height: 80),
              to: dir.appendingPathComponent("welcome.png"))

        print("Wrote snapshots to \(dir.path)")
        exit(0)
    }

    // MARK: - Fixtures

    /// Deliberately generic sample content — these end up in a public README.
    private static func seedStore() {
        ClipboardStore.shared.purge()
        ClipboardStore.shared.query = ""

        let samples: [ClipboardItem] = [
            makeText("https://github.com/quillerpl/clipit", app: "Safari"),
            makeImage(app: "Preview"),
            makeText("""
                Hi Anna,

                Here are the notes from this morning's review. Nothing blocking —
                I'll pick up the rest tomorrow.

                Thanks!
                """, app: "Mail", styled: true),
            makeFiles([URL(fileURLWithPath: "/Users/you/Documents/Quarterly-report.pdf")],
                      app: "Finder"),
            makeText("SELECT * FROM orders WHERE status = 'pending';", app: "Terminal"),
            makeText("npm run dev -- --port 3000", app: "Terminal"),
            makeText("The quick brown fox jumps over the lazy dog.", app: "Notes"),
        ]
        for item in samples.reversed() { ClipboardStore.shared.add(item) }
    }

    private static func makeText(_ string: String, app: String, styled: Bool = false) -> ClipboardItem {
        var reps: [NSPasteboard.PasteboardType: Data] = [.string: Data(string.utf8)]
        if styled {
            let attributed = NSAttributedString(string: string)
            if let rtf = attributed.rtf(from: NSRange(location: 0, length: attributed.length),
                                        documentAttributes: [:]) {
                reps[.rtf] = rtf
            }
        }
        return ClipboardItem(kind: .text, plainText: string, representations: reps,
                             image: nil, fileURLs: [],
                             sourceAppName: app, sourceAppIcon: nil)
    }

    private static func makeFiles(_ urls: [URL], app: String) -> ClipboardItem {
        ClipboardItem(kind: .files, plainText: urls.map(\.path).joined(separator: "\n"),
                      representations: [.fileURL: Data(urls[0].absoluteString.utf8)],
                      image: nil, fileURLs: urls,
                      sourceAppName: app, sourceAppIcon: nil)
    }

    private static func makeImage(app: String) -> ClipboardItem {
        let size = NSSize(width: 480, height: 300)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(colors: [NSColor.systemTeal, NSColor.systemIndigo])?
            .draw(in: NSRect(origin: .zero, size: size), angle: 35)
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: NSRect(x: 40, y: 110, width: 400, height: 80),
                     xRadius: 12, yRadius: 12).fill()
        image.unlockFocus()

        return ClipboardItem(kind: .image, plainText: "",
                             representations: [.tiff: image.tiffRepresentation ?? Data()],
                             image: image, fileURLs: [],
                             sourceAppName: app, sourceAppIcon: nil)
    }

    // MARK: - Offscreen rendering

    /// Rendered at 2× so the images stay sharp on the retina displays most people read a
    /// README on. An offscreen window is always 1× backing, so the scale is applied to the
    /// view tree instead.
    private static let scale: CGFloat = 2

    private static func write(_ view: some View, panel: NSSize, margin: NSSize, to url: URL) {
        let logical = NSSize(width: panel.width + margin.width * 2,
                             height: panel.height + margin.height * 2)
        let total = NSSize(width: logical.width * scale, height: logical.height * scale)

        let view = view
            .frame(width: logical.width, height: logical.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: total.width, height: total.height, alignment: .topLeading)

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: total),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = true
        window.appearance = NSAppearance(named: .darkAqua)

        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(origin: .zero, size: total)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()

        // Let SwiftUI lay out, and the material sample its backdrop, before grabbing the bits.
        RunLoop.main.run(until: Date().addingTimeInterval(0.7))

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
            print("  \(url.lastPathComponent) — \(Int(total.width))×\(Int(total.height))")
        }
        window.orderOut(nil)
    }
}

// MARK: - Preview wrappers

/// A synthetic wallpaper behind the panel, so the translucency reads the way it does on screen.
private struct PanelPreview<Content: View>: View {
    var panel: NSSize
    var cornerRadius: CGFloat = 14
    var light = false
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            LinearGradient(colors: light
                           ? [Color(red: 0.42, green: 0.52, blue: 0.72),
                              Color(red: 0.24, green: 0.28, blue: 0.44)]
                           : [Color(red: 0.16, green: 0.22, blue: 0.42),
                              Color(red: 0.34, green: 0.20, blue: 0.44),
                              Color(red: 0.10, green: 0.12, blue: 0.22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            // Soft highlights, so the blur has something with structure to sample.
            Circle().fill(Color.white.opacity(0.10)).frame(width: 340).blur(radius: 70)
                .offset(x: -140, y: -90)
            Circle().fill(Color(red: 1.0, green: 0.7, blue: 0.4).opacity(0.16))
                .frame(width: 260).blur(radius: 60).offset(x: 190, y: 110)

            content
                // Constrain to the panel's real size: the history list otherwise expands to
                // fill whatever it is given, and the screenshot grows a tail of empty rows.
                .frame(width: panel.width, height: panel.height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 26, y: 12)
        }
    }
}

private struct HistoryPreview: View {
    @State private var selection = 1
    var body: some View {
        HistoryView(selection: $selection, onPaste: { _, _ in }, onPurge: {}, onQuit: {})
    }
}

private struct DrawerPreview: View {
    @State private var selection = 1
    var body: some View {
        CardDrawerView(selection: $selection, onPaste: { _, _ in }, onPurge: {}, onClose: {})
    }
}

private struct SwitcherPreview: View {
    @State private var selection = 1
    var body: some View {
        QuickSwitcherView(selection: $selection, onPaste: { _ in }, onCancel: {})
    }
}

private struct WelcomePreview: View {
    var body: some View {
        WelcomeView(onFinish: {})
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light)
    }
}
