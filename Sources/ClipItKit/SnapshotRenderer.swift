import AppKit
import SwiftUI

/// Development-only: `ClipIt --snapshot <dir>` seeds fake history, renders the two panels
/// offscreen to PNGs, and exits. Lets the UI be inspected without a running menu bar.
@MainActor
public enum SnapshotRenderer {

    public static func run(outputDirectory: String) {
        let dir = URL(fileURLWithPath: outputDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        seedStore()
        let count = ClipboardStore.shared.items.count

        let history = HistoryContainerPreview()
        write(view: history,
              size: NSSize(width: HistoryView.width,
                           height: HistoryView.preferredHeight(itemCount: count, hasSearch: true)),
              to: dir.appendingPathComponent("history.png"))

        let empty = HistoryContainerPreview(emptyState: true)
        write(view: empty,
              size: NSSize(width: HistoryView.width,
                           height: HistoryView.preferredHeight(itemCount: 0, hasSearch: false)),
              to: dir.appendingPathComponent("history-empty.png"))

        seedStore()
        let switcher = SwitcherContainerPreview()
        write(view: switcher,
              size: NSSize(width: QuickSwitcherView.width, height: QuickSwitcherView.height),
              to: dir.appendingPathComponent("switcher.png"))

        let drawer = DrawerContainerPreview()
        write(view: drawer,
              size: NSSize(width: 940, height: CardDrawerView.height),
              to: dir.appendingPathComponent("drawer.png"))

        print("Wrote snapshots to \(dir.path)")
        exit(0)
    }

    // MARK: - Fixtures

    private static func seedStore() {
        ClipboardStore.shared.purge()

        let samples: [ClipboardItem] = [
            makeText("https://github.com/anthropics/claude-code", app: "Arc"),
            makeImage(app: "Preview"),
            makeText("""
                Dear Jack,

                The quarterly figures are attached. Let me know if the FX column looks right.

                Best,
                Maria
                """, app: "Microsoft Outlook", styled: true),
            makeFiles([URL(fileURLWithPath: "/Users/you/Documents/Q3-invoices.xlsx")], app: "Finder"),
            makeText("SELECT * FROM invoices WHERE status = 'pending';", app: "Sublime Text"),
            makeText("PL61 1090 1014 0000 0712 1981 2874", app: "Safari"),
            makeText("npm run dev -- --port 3000", app: "Terminal"),
        ]
        // Insert oldest-first so the array ends up newest-first.
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
        // A simple gradient stands in for a real screenshot.
        let size = NSSize(width: 480, height: 300)
        let image = NSImage(size: size)
        image.lockFocus()
        let gradient = NSGradient(colors: [NSColor.systemTeal, NSColor.systemIndigo])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 35)
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: NSRect(x: 40, y: 110, width: 400, height: 80),
                     xRadius: 12, yRadius: 12).fill()
        image.unlockFocus()

        let tiff = image.tiffRepresentation ?? Data()
        return ClipboardItem(kind: .image, plainText: "", representations: [.tiff: tiff],
                             image: image, fileURLs: [],
                             sourceAppName: app, sourceAppIcon: nil)
    }

    // MARK: - Offscreen rendering

    private static func write(view: some View, size: NSSize, to url: URL) {
        // Real window backing, otherwise SwiftUI materials render as holes.
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.isOpaque = true
        // The panels are translucent dark; give the material something plausible to blend
        // against so the snapshot resembles what sits over a real desktop.
        window.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)

        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()

        // Let SwiftUI lay out and draw before we grab the bits.
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
            print("  \(url.lastPathComponent) — \(Int(size.width))×\(Int(size.height))")
        }
        window.orderOut(nil)
    }
}

// MARK: - Preview wrappers

private struct HistoryContainerPreview: View {
    var emptyState = false
    @State private var selection = 1

    var body: some View {
        HistoryView(selection: $selection,
                    onPaste: { _, _ in },
                    onPurge: { if emptyState { } },
                    onQuit: {})
            .onAppear { if emptyState { ClipboardStore.shared.purge() } }
    }
}

private struct SwitcherContainerPreview: View {
    @State private var selection = 1

    var body: some View {
        QuickSwitcherView(selection: $selection, onPaste: { _ in }, onCancel: {})
    }
}

private struct DrawerContainerPreview: View {
    @State private var selection = 1

    var body: some View {
        CardDrawerView(selection: $selection,
                       onPaste: { _, _ in },
                       onPurge: {},
                       onClose: {})
    }
}
