import XCTest
import AppKit
@testable import MagwellKit

/// Exercises `ClipboardMonitor.capture()` against a real, private pasteboard.
///
/// This is where every classification bug so far has lived: a copied image filed as text
/// because the browser also put its URL on the pasteboard, a password manager entry that
/// should never have been recorded at all.
@MainActor
final class ClipboardCaptureTests: XCTestCase {

    private var pasteboard: NSPasteboard!
    private var monitor: ClipboardMonitor!

    override func setUp() {
        super.setUp()
        // A uniquely named pasteboard, so tests never touch the developer's real clipboard.
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.jacks.magwell.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        monitor = ClipboardMonitor(pasteboard: pasteboard)
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        pasteboard = nil
        monitor = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func write(_ build: (NSPasteboardItem) -> Void) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        build(item)
        pasteboard.writeObjects([item])
    }

    private func samplePNG(width: Int = 8, height: Int = 8) -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemPink.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        image.unlockFocus()
        let tiff = image.tiffRepresentation!
        return NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
    }

    // MARK: - Classification

    func testPlainTextIsCapturedAsText() {
        write { $0.setString("hello world", forType: .string) }

        let item = monitor.capture()

        XCTAssertEqual(item?.kind, .text)
        XCTAssertEqual(item?.plainText, "hello world")
    }

    func testBitmapWithNoTextIsAnImage() {
        write { $0.setData(samplePNG(), forType: .png) }

        let item = monitor.capture()

        XCTAssertEqual(item?.kind, .image)
        XCTAssertNotNil(item?.image)
    }

    /// The regression that started this: "Copy Image" in a browser puts the bitmap *and* the
    /// image's URL on the pasteboard. Filing it as text gave the user a link glyph instead of
    /// their picture.
    func testBitmapAlongsideBareURLIsAnImage() {
        write {
            $0.setData(samplePNG(), forType: .png)
            $0.setString("https://example.com/cat.png", forType: .string)
        }

        let item = monitor.capture()

        XCTAssertEqual(item?.kind, .image, "a copied image must not be demoted to a link")
        XCTAssertNotNil(item?.image)
    }

    /// ...but real prose alongside a bitmap is a rich-text copy, and the text is the point.
    func testBitmapAlongsideProseIsText() {
        write {
            $0.setData(samplePNG(), forType: .png)
            $0.setString("The quarterly figures are attached.", forType: .string)
        }

        let item = monitor.capture()

        XCTAssertEqual(item?.kind, .text)
        // The bitmap is still kept so the row can show a preview rather than a glyph.
        XCTAssertNotNil(item?.image)
    }

    func testFileURLIsCapturedAsFiles() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("magwell-test-\(UUID().uuidString).txt")
        try "x".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])

        let item = monitor.capture()

        XCTAssertEqual(item?.kind, .files)
        XCTAssertEqual(item?.fileURLs.first?.lastPathComponent, url.lastPathComponent)
    }

    // MARK: - Privacy

    func testConcealedContentIsNeverRecorded() {
        write {
            $0.setString("hunter2", forType: .string)
            $0.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        }

        XCTAssertNil(monitor.capture(), "password manager copies must never enter history")
    }

    func testTransientContentIsNeverRecorded() {
        write {
            $0.setString("ephemeral", forType: .string)
            $0.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        }

        XCTAssertNil(monitor.capture())
    }

    func testWhitespaceOnlyTextIsIgnored() {
        write { $0.setString("   \n\t ", forType: .string) }

        XCTAssertNil(monitor.capture())
    }

    func testEmptyPasteboardYieldsNothing() {
        pasteboard.clearContents()

        XCTAssertNil(monitor.capture())
    }

    // MARK: - URL heuristic

    func testBareURLDetection() {
        XCTAssertTrue(monitor.isBareURL("https://example.com/a.png"))
        XCTAssertTrue(monitor.isBareURL("file:///Users/x/y.txt"))

        XCTAssertFalse(monitor.isBareURL("see https://example.com for details"),
                       "a sentence containing a URL is prose")
        XCTAssertFalse(monitor.isBareURL("example.com"), "no scheme, so not unambiguous")
        XCTAssertFalse(monitor.isBareURL("https://example.com\nhttps://other.com"),
                       "multiple lines are content, not a single link")
    }
}
