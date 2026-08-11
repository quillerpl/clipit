import AppKit
import CryptoKit
import QuickLookThumbnailing

enum ClipKind {
    case text
    case image
    case files
}

/// One captured pasteboard snapshot. Held in memory only — nothing is ever written to disk.
@MainActor
final class ClipboardItem: Identifiable, Equatable, ObservableObject {

    let id = UUID()
    let kind: ClipKind
    let date: Date

    /// Plain-text rendering. Used for the CMD+SHIFT+V unformatted paste and for previews.
    let plainText: String

    /// Every pasteboard representation we captured, so a normal paste round-trips formatting.
    let representations: [NSPasteboard.PasteboardType: Data]

    let image: NSImage?
    let fileURLs: [URL]

    let sourceAppName: String?
    let sourceAppIcon: NSImage?

    /// Content fingerprint, used to collapse duplicates.
    let fingerprint: String

    /// Starts as whatever can be produced instantly, then upgrades in place when Quick Look
    /// returns a real preview for a copied file.
    @Published private(set) var thumbnail: NSImage?

    /// True when the thumbnail shows actual content rather than a document icon, so views can
    /// inset it less and fill card previews with it.
    @Published private(set) var thumbnailIsContent: Bool = false

    init(kind: ClipKind,
         plainText: String,
         representations: [NSPasteboard.PasteboardType: Data],
         image: NSImage?,
         fileURLs: [URL],
         sourceAppName: String?,
         sourceAppIcon: NSImage?) {
        self.kind = kind
        self.date = Date()
        self.plainText = plainText
        self.representations = representations
        self.image = image
        self.fileURLs = fileURLs
        self.sourceAppName = sourceAppName
        self.sourceAppIcon = sourceAppIcon
        self.fingerprint = Self.fingerprint(kind: kind,
                                            plainText: plainText,
                                            representations: representations,
                                            fileURLs: fileURLs)
        makeInitialThumbnail()
        requestQuickLookThumbnail()
    }

    nonisolated static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Display

    /// First meaningful line, collapsed — what shows as the row headline.
    var title: String {
        switch kind {
        case .files:
            if fileURLs.count == 1 { return fileURLs[0].lastPathComponent }
            return "\(fileURLs.count) files"
        case .image:
            if let image { return "Image · \(Int(image.size.width))×\(Int(image.size.height))" }
            return "Image"
        case .text:
            let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            let firstLine = trimmed.split(separator: "\n", maxSplits: 1,
                                          omittingEmptySubsequences: false).first.map(String.init) ?? ""
            return firstLine.isEmpty ? "(whitespace)" : firstLine
        }
    }

    /// Second line of the row — a continuation for text, a path for files.
    var subtitle: String? {
        switch kind {
        case .files:
            if fileURLs.count == 1 {
                return fileURLs[0].deletingLastPathComponent().path
                    .replacingOccurrences(of: NSHomeDirectory(), with: "~")
            }
            return fileURLs.prefix(3).map(\.lastPathComponent).joined(separator: ", ")
        case .image:
            return nil
        case .text:
            let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count > 1 else { return nil }
            let rest = parts[1].replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return rest.isEmpty ? nil : rest
        }
    }

    /// True when a plain-text paste would visibly differ from a normal paste.
    var hasFormatting: Bool {
        representations.keys.contains(.rtf) || representations.keys.contains(.rtfd)
            || representations.keys.contains(.html)
    }

    var lineCount: Int {
        guard kind == .text else { return 1 }
        return plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: false).count
    }

    /// Matches content, filename and source app, so "outlook" or "xlsx" both find things a
    /// plain content search would miss.
    func matches(_ needle: String) -> Bool {
        let haystacks = [plainText, sourceAppName ?? ""] + fileURLs.map(\.lastPathComponent)
        return haystacks.contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    var symbolName: String {
        switch kind {
        case .text:  return plainText.hasPrefix("http://") || plainText.hasPrefix("https://")
            ? "link" : "text.alignleft"
        case .image: return "photo"
        case .files: return "doc"
        }
    }

    // MARK: - Helpers

    private static func fingerprint(kind: ClipKind,
                                    plainText: String,
                                    representations: [NSPasteboard.PasteboardType: Data],
                                    fileURLs: [URL]) -> String {
        var hasher = SHA256()
        switch kind {
        case .text:
            hasher.update(data: Data(plainText.utf8))
        case .files:
            hasher.update(data: Data(fileURLs.map(\.path).joined(separator: "\n").utf8))
        case .image:
            // Hash the pixel payload, preferring the smaller/canonical representation.
            let data = representations[.png] ?? representations[.tiff] ?? Data()
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func makeInitialThumbnail() {
        // Any entry carrying a bitmap gets a real preview, whatever its kind — a styled copy
        // from a browser is still worth showing as a picture in the badge.
        if let image, image.size.width > 0, image.size.height > 0 {
            thumbnail = image.scaledToFit(boundingBox: NSSize(width: 256, height: 256))
            thumbnailIsContent = true
            return
        }
        // Generic document icon as a placeholder; Quick Look replaces it below if it can.
        if kind == .files, let first = fileURLs.first {
            let icon = NSWorkspace.shared.icon(forFile: first.path)
            icon.size = NSSize(width: 32, height: 32)
            thumbnail = icon
            thumbnailIsContent = false
        }
    }

    /// Copying an image *file* out of Finder puts a file URL on the pasteboard, not a bitmap —
    /// so without this a copied photo shows a blank document icon. Quick Look renders a real
    /// preview for anything it knows how to open (images, PDFs, video, Office documents),
    /// off the main thread.
    private func requestQuickLookThumbnail() {
        guard kind == .files, let url = fileURLs.first, url.isFileURL else { return }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 256, height: 256),
            scale: scale,
            representationTypes: .thumbnail)

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let cgImage = representation?.cgImage else { return }
            let size = NSSize(width: CGFloat(cgImage.width) / scale,
                              height: CGFloat(cgImage.height) / scale)
            let image = NSImage(cgImage: cgImage, size: size)
            Task { @MainActor [weak self] in
                self?.thumbnail = image
                self?.thumbnailIsContent = true
            }
        }
    }
}

extension NSImage {
    /// Aspect-fit rescale. Never upscales — a 12×12 favicon stays 12×12 rather than going blurry.
    func scaledToFit(boundingBox: NSSize) -> NSImage {
        guard size.width > 0, size.height > 0 else { return self }
        let scale = min(boundingBox.width / size.width, boundingBox.height / size.height, 1.0)
        let target = NSSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        guard target.width >= 1, target.height >= 1 else { return self }

        let output = NSImage(size: target)
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: target),
             from: NSRect(origin: .zero, size: size),
             operation: .copy,
             fraction: 1.0)
        output.unlockFocus()
        return output
    }
}
