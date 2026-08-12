import AppKit

/// PNG ⇄ TIFF conversion, and the rule for which bitmap flavours history keeps.
///
/// Apps routinely put the same pixels on the pasteboard twice, as PNG *and* as TIFF, and the
/// pasteboard's TIFF is uncompressed — a Retina screenshot is tens of megabytes of it. Since
/// history lives in RAM, holding both is the most expensive thing ClipIt does, for no gain.
/// Capture keeps one compressed copy; `Paster` synthesizes the other flavour back on the way
/// out, so apps that only read TIFF still paste correctly.
enum Bitmap {

    /// Bitmap flavours in the order we'd rather keep them: PNG compresses, TIFF does not.
    static let png = NSPasteboard.PasteboardType.png
    static let tiff = NSPasteboard.PasteboardType.tiff

    static func pngFromTIFF(_ data: Data) -> Data? {
        NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
    }

    static func tiffFromPNG(_ data: Data) -> Data? {
        NSBitmapImageRep(data: data)?.tiffRepresentation
    }

    /// Reduces a captured set of representations to a single bitmap flavour.
    ///
    /// A transcode that fails leaves the original untouched: keeping an expensive TIFF beats
    /// losing the picture.
    static func collapsingDuplicates(
        _ representations: [NSPasteboard.PasteboardType: Data]
    ) -> [NSPasteboard.PasteboardType: Data] {
        var result = representations

        if result[png] != nil {
            result[tiff] = nil
            return result
        }
        if let data = result[tiff], let converted = pngFromTIFF(data) {
            result[tiff] = nil
            result[png] = converted
        }
        return result
    }
}
