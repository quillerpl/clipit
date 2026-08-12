import XCTest
import AppKit
@testable import ClipItKit

/// Layout and formatting rules that have no UI of their own but decide what the user sees.
@MainActor
final class PresentationTests: XCTestCase {

    // MARK: - Switcher window

    func testWindowShowsSelectionAndTheNextCard() {
        XCTAssertEqual(CardWindow.range(selection: 0, count: 7, visible: 2), 0..<2)
        XCTAssertEqual(CardWindow.range(selection: 3, count: 7, visible: 2), 3..<5)
    }

    func testWindowShiftsBackAtTheEndOfTheList() {
        // Selection is the last item: the window must still show two cards.
        XCTAssertEqual(CardWindow.range(selection: 6, count: 7, visible: 2), 5..<7)
    }

    func testWindowShrinksWhenHistoryIsSmallerThanTheWindow() {
        XCTAssertEqual(CardWindow.range(selection: 0, count: 1, visible: 2), 0..<1)
    }

    func testWindowIsEmptyForEmptyHistory() {
        XCTAssertEqual(CardWindow.range(selection: 0, count: 0, visible: 2), 0..<0)
    }

    func testWindowClampsOutOfBoundsSelection() {
        // Defensive: selection can lag behind a purge for one render pass.
        XCTAssertEqual(CardWindow.range(selection: 99, count: 3, visible: 2), 1..<3)
        XCTAssertEqual(CardWindow.range(selection: -5, count: 3, visible: 2), 0..<2)
    }

    func testWindowNeverExceedsTheList() {
        for count in 0...12 {
            for selection in -2...14 {
                let range = CardWindow.range(selection: selection, count: count, visible: 2)
                XCTAssertGreaterThanOrEqual(range.lowerBound, 0)
                XCTAssertLessThanOrEqual(range.upperBound, count)
            }
        }
    }

    // MARK: - Switcher default selection

    /// Index 0 is what a plain ⌘V already pastes, so opening there makes ⌘⌥V ⏎ a slower ⌘V.
    func testSwitcherOpensOnThePreviousItem() {
        XCTAssertEqual(QuickSwitcherView.initialSelection(itemCount: 5), 1)
        XCTAssertEqual(QuickSwitcherView.initialSelection(itemCount: 2), 1)
    }

    func testSwitcherStaysOnTheOnlyItemItHas() {
        XCTAssertEqual(QuickSwitcherView.initialSelection(itemCount: 1), 0)
        XCTAssertEqual(QuickSwitcherView.initialSelection(itemCount: 0), 0)
    }

    // MARK: - Popover sizing

    func testPopoverGrowsWithItemCount() {
        let small = HistoryView.preferredHeight(itemCount: 2, hasSearch: false)
        let larger = HistoryView.preferredHeight(itemCount: 5, hasSearch: false)

        XCTAssertGreaterThan(larger, small, "the panel should grow as history fills up")
    }

    func testPopoverStopsGrowingAndScrolls() {
        let many = HistoryView.preferredHeight(itemCount: 20, hasSearch: false)
        let absurd = HistoryView.preferredHeight(itemCount: 500, hasSearch: false)

        XCTAssertEqual(many, absurd, "past the cap the list scrolls instead of growing")
    }

    func testSearchRowAddsHeight() {
        let without = HistoryView.preferredHeight(itemCount: 3, hasSearch: false)
        let with = HistoryView.preferredHeight(itemCount: 3, hasSearch: true)

        XCTAssertEqual(with - without, HistoryView.searchRowHeight, accuracy: 0.5)
    }

    // MARK: - Relative time

    func testRelativeTimeWording() {
        func string(secondsAgo: TimeInterval) -> String {
            RelativeTime.string(for: Date().addingTimeInterval(-secondsAgo))
        }

        XCTAssertEqual(string(secondsAgo: 1), "just now")
        XCTAssertEqual(string(secondsAgo: 30), "30s ago")
        XCTAssertEqual(string(secondsAgo: 120), "2m ago")
        XCTAssertEqual(string(secondsAgo: 7200), "2h ago")
        XCTAssertEqual(string(secondsAgo: 172_800), "2d ago")
    }

    // MARK: - Plain-text flattening (⌘⇧V)

    func testPlainTextPrefersTheCapturedString() {
        let item = ClipboardItem(kind: .text, plainText: "hello",
                                 representations: [.string: Data("hello".utf8)],
                                 image: nil, fileURLs: [],
                                 sourceAppName: nil, sourceAppIcon: nil)

        XCTAssertEqual(Paster.plainTextRepresentation(of: item), "hello")
    }

    func testPlainTextFlattensRTFWhenNoStringWasCaptured() {
        let attributed = NSAttributedString(
            string: "styled text",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 24)])
        let rtf = attributed.rtf(from: NSRange(location: 0, length: attributed.length),
                                 documentAttributes: [:])!

        let item = ClipboardItem(kind: .text, plainText: "",
                                 representations: [.rtf: rtf],
                                 image: nil, fileURLs: [],
                                 sourceAppName: nil, sourceAppIcon: nil)

        XCTAssertEqual(Paster.plainTextRepresentation(of: item), "styled text")
    }

    func testPlainTextForFilesIsTheirPaths() {
        let urls = [URL(fileURLWithPath: "/a.txt"), URL(fileURLWithPath: "/b.txt")]
        let item = ClipboardItem(kind: .files, plainText: "",
                                 representations: [:], image: nil, fileURLs: urls,
                                 sourceAppName: nil, sourceAppIcon: nil)

        XCTAssertEqual(Paster.plainTextRepresentation(of: item), "/a.txt\n/b.txt")
    }

    // MARK: - Bitmap round-trip

    /// History keeps only the compressed flavour to stay small, so the paste has to put the
    /// uncompressed one back — otherwise apps that read nothing but TIFF paste nothing.
    func testPastingAPNGOnlyItemStillOffersTIFF() {
        let source = NSImage(size: NSSize(width: 8, height: 8))
        source.lockFocus()
        NSColor.systemPink.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 8, height: 8)).fill()
        source.unlockFocus()
        let png = NSBitmapImageRep(data: source.tiffRepresentation!)!
            .representation(using: .png, properties: [:])!

        let item = ClipboardItem(kind: .image, plainText: "",
                                 representations: [.png: png],
                                 image: nil, fileURLs: [],
                                 sourceAppName: nil, sourceAppIcon: nil)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.quillerpl.clipit.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        Paster.placeOnPasteboard(item, plainOnly: false, on: pasteboard)

        XCTAssertNotNil(pasteboard.data(forType: .png))
        XCTAssertNotNil(pasteboard.data(forType: .tiff),
                        "an app that only reads TIFF must still get the picture")
    }

    func testCollapsingDuplicatesKeepsOneFlavour() {
        let source = NSImage(size: NSSize(width: 4, height: 4))
        source.lockFocus()
        NSColor.systemTeal.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 4, height: 4)).fill()
        source.unlockFocus()

        let tiff = source.tiffRepresentation!
        let png = Bitmap.pngFromTIFF(tiff)!

        let both = Bitmap.collapsingDuplicates([.png: png, .tiff: tiff, .string: Data("x".utf8)])
        XCTAssertNil(both[.tiff])
        XCTAssertEqual(both[.png], png)
        XCTAssertNotNil(both[.string], "collapsing bitmaps must not touch anything else")

        let tiffOnly = Bitmap.collapsingDuplicates([.tiff: tiff])
        XCTAssertNil(tiffOnly[.tiff])
        XCTAssertNotNil(tiffOnly[.png])
    }
}
