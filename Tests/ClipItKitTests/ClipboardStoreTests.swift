import XCTest
import AppKit
@testable import ClipItKit

@MainActor
final class ClipboardStoreTests: XCTestCase {

    private var store: ClipboardStore { ClipboardStore.shared }

    override func setUp() {
        super.setUp()
        store.purge()
        store.query = ""
    }

    override func tearDown() {
        store.purge()
        store.query = ""
        super.tearDown()
    }

    private func text(_ string: String, app: String? = nil) -> ClipboardItem {
        ClipboardItem(kind: .text,
                      plainText: string,
                      representations: [.string: Data(string.utf8)],
                      image: nil,
                      fileURLs: [],
                      sourceAppName: app,
                      sourceAppIcon: nil)
    }

    // MARK: - Ordering

    func testNewestItemIsFirst() {
        store.add(text("one"))
        store.add(text("two"))

        XCTAssertEqual(store.items.map(\.plainText), ["two", "one"])
    }

    func testRecopyingPromotesInsteadOfDuplicating() {
        store.add(text("one"))
        store.add(text("two"))
        store.add(text("three"))

        store.add(text("one"))   // same content copied again

        XCTAssertEqual(store.items.map(\.plainText), ["one", "three", "two"])
        XCTAssertEqual(store.items.count, 3, "re-copying must not create a duplicate row")
    }

    func testHistoryIsCappedAndDropsOldest() {
        for index in 0..<(store.maxItems + 10) {
            store.add(text("item \(index)"))
        }

        XCTAssertEqual(store.items.count, store.maxItems)
        XCTAssertEqual(store.items.first?.plainText, "item \(store.maxItems + 9)")
        XCTAssertEqual(store.items.last?.plainText, "item 10")
    }

    func testRemoveDropsOnlyThatItem() {
        store.add(text("one"))
        store.add(text("two"))
        let victim = store.items[0]

        store.remove(victim)

        XCTAssertEqual(store.items.map(\.plainText), ["one"])
    }

    func testPurgeEmptiesEverything() {
        store.add(text("one"))
        store.add(text("two"))

        store.purge()

        XCTAssertTrue(store.items.isEmpty)
    }

    // MARK: - Filtering

    func testEmptyQueryShowsEverything() {
        store.add(text("alpha"))
        store.add(text("beta"))

        store.query = "   "

        XCTAssertEqual(store.visibleItems.count, 2, "whitespace is not a filter")
    }

    func testQueryMatchesContentCaseInsensitively() {
        store.add(text("Quarterly Figures"))
        store.add(text("npm run dev"))

        store.query = "QUARTERLY"

        XCTAssertEqual(store.visibleItems.map(\.plainText), ["Quarterly Figures"])
    }

    func testQueryMatchesSourceApp() {
        store.add(text("some note", app: "Microsoft Outlook"))
        store.add(text("other note", app: "Terminal"))

        store.query = "outlook"

        XCTAssertEqual(store.visibleItems.map(\.plainText), ["some note"])
    }

    func testQueryMatchesFilename() {
        let url = URL(fileURLWithPath: "/Users/x/Q3-invoices.xlsx")
        store.add(ClipboardItem(kind: .files,
                                plainText: url.path,
                                representations: [:],
                                image: nil,
                                fileURLs: [url],
                                sourceAppName: "Finder",
                                sourceAppIcon: nil))
        store.add(text("unrelated"))

        store.query = "xlsx"

        XCTAssertEqual(store.visibleItems.count, 1)
    }

    func testNoMatchesYieldsEmptyRatherThanEverything() {
        store.add(text("alpha"))

        store.query = "zzzz"

        XCTAssertTrue(store.visibleItems.isEmpty)
    }
}
