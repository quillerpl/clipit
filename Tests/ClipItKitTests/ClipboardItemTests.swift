import XCTest
import AppKit
@testable import ClipItKit

@MainActor
final class ClipboardItemTests: XCTestCase {

    private func text(_ string: String,
                      representations: [NSPasteboard.PasteboardType: Data]? = nil) -> ClipboardItem {
        ClipboardItem(kind: .text,
                      plainText: string,
                      representations: representations ?? [.string: Data(string.utf8)],
                      image: nil,
                      fileURLs: [],
                      sourceAppName: nil,
                      sourceAppIcon: nil)
    }

    // MARK: - Display strings

    func testTitleIsFirstLineAndSubtitleIsTheRest() {
        let item = text("Dear Jack,\n\nThe figures are attached.\nBest, Maria")

        XCTAssertEqual(item.title, "Dear Jack,")
        XCTAssertEqual(item.subtitle, "The figures are attached. Best, Maria")
    }

    func testSingleLineTextHasNoSubtitle() {
        XCTAssertNil(text("just one line").subtitle)
    }

    func testWhitespaceOnlyTitleIsLabelled() {
        XCTAssertEqual(text("   ").title, "(whitespace)")
    }

    func testLineCount() {
        XCTAssertEqual(text("one").lineCount, 1)
        XCTAssertEqual(text("one\ntwo\nthree").lineCount, 3)
    }

    func testFileItemTitleAndSubtitle() {
        let url = URL(fileURLWithPath: "/Users/x/Documents/Q3-invoices.xlsx")
        let item = ClipboardItem(kind: .files, plainText: url.path, representations: [:],
                                 image: nil, fileURLs: [url],
                                 sourceAppName: nil, sourceAppIcon: nil)

        XCTAssertEqual(item.title, "Q3-invoices.xlsx")
        XCTAssertEqual(item.subtitle, "/Users/x/Documents")
    }

    func testMultipleFilesAreCounted() {
        let urls = [URL(fileURLWithPath: "/a.txt"), URL(fileURLWithPath: "/b.txt")]
        let item = ClipboardItem(kind: .files, plainText: "", representations: [:],
                                 image: nil, fileURLs: urls,
                                 sourceAppName: nil, sourceAppIcon: nil)

        XCTAssertEqual(item.title, "2 files")
    }

    // MARK: - Formatting

    func testHasFormattingOnlyWhenRichFlavoursExist() {
        XCTAssertFalse(text("plain").hasFormatting)

        let styled = text("styled", representations: [.string: Data("styled".utf8),
                                                      .rtf: Data([0x7b])])
        XCTAssertTrue(styled.hasFormatting)
    }

    // MARK: - Fingerprints

    func testIdenticalTextSharesAFingerprint() {
        XCTAssertEqual(text("same").fingerprint, text("same").fingerprint)
    }

    func testDifferentTextDiffersInFingerprint() {
        XCTAssertNotEqual(text("one").fingerprint, text("two").fingerprint)
    }

    func testFileItemsFingerprintOnPaths() {
        func files(_ paths: [String]) -> ClipboardItem {
            ClipboardItem(kind: .files, plainText: "", representations: [:], image: nil,
                          fileURLs: paths.map { URL(fileURLWithPath: $0) },
                          sourceAppName: nil, sourceAppIcon: nil)
        }
        XCTAssertEqual(files(["/a"]).fingerprint, files(["/a"]).fingerprint)
        XCTAssertNotEqual(files(["/a"]).fingerprint, files(["/b"]).fingerprint)
    }

    // MARK: - Search

    func testMatchesLooksAtContentAppAndFilename() {
        let item = ClipboardItem(kind: .files,
                                 plainText: "/Users/x/Report.pdf",
                                 representations: [:],
                                 image: nil,
                                 fileURLs: [URL(fileURLWithPath: "/Users/x/Report.pdf")],
                                 sourceAppName: "Finder",
                                 sourceAppIcon: nil)

        XCTAssertTrue(item.matches("report"))
        XCTAssertTrue(item.matches("FINDER"))
        XCTAssertTrue(item.matches("pdf"))
        XCTAssertFalse(item.matches("spreadsheet"))
    }

    // MARK: - Thumbnails

    func testImageItemGetsAContentThumbnailImmediately() {
        let image = NSImage(size: NSSize(width: 40, height: 20))
        image.lockFocus(); NSColor.blue.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 40, height: 20)).fill(); image.unlockFocus()

        let item = ClipboardItem(kind: .image, plainText: "", representations: [:],
                                 image: image, fileURLs: [],
                                 sourceAppName: nil, sourceAppIcon: nil)

        XCTAssertNotNil(item.thumbnail)
        XCTAssertTrue(item.thumbnailIsContent)
    }

    func testTextItemHasNoThumbnail() {
        let item = text("nothing to preview")

        XCTAssertNil(item.thumbnail)
        XCTAssertFalse(item.thumbnailIsContent)
    }

    func testScaledToFitPreservesAspectAndNeverUpscales() {
        let wide = NSImage(size: NSSize(width: 400, height: 100))
        let scaled = wide.scaledToFit(boundingBox: NSSize(width: 96, height: 96))
        XCTAssertEqual(scaled.size.width, 96, accuracy: 1)
        XCTAssertEqual(scaled.size.height, 24, accuracy: 1)

        let tiny = NSImage(size: NSSize(width: 12, height: 12))
        XCTAssertEqual(tiny.scaledToFit(boundingBox: NSSize(width: 96, height: 96)).size.width, 12,
                       accuracy: 0.5, "small images must not be blown up and blurred")
    }
}
