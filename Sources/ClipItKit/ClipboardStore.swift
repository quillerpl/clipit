import AppKit
import Combine

/// In-memory history. Deliberately never persisted: quitting the app or rebooting clears it,
/// matching Windows' clipboard-history behaviour.
@MainActor
final class ClipboardStore: ObservableObject {

    static let shared = ClipboardStore()

    @Published private(set) var items: [ClipboardItem] = []

    /// Live filter text. Panels read `visibleItems`, never `items`, so the keyboard shortcuts
    /// and the rendered rows can never disagree about what index 3 means.
    @Published var query: String = ""

    let maxItems = 50

    /// Ceiling on the pasteboard bytes history holds. The item cap alone is no protection: one
    /// screenshot runs to megabytes, and fifty of them would turn "memory-only" — the app's
    /// whole privacy claim — into a reason to quit the app.
    let maxBytes = 150 * 1024 * 1024

    private init() {}

    var visibleItems: [ClipboardItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return items }
        return items.filter { $0.matches(needle) }
    }

    /// Recomputed rather than cached: fifty additions is nothing to sum, and a stale running
    /// total would be a silent leak.
    var totalBytes: Int {
        items.reduce(0) { $0 + $1.byteCount }
    }

    func add(_ item: ClipboardItem) {
        // Re-copying something already in history moves it to the top. The *new* capture wins:
        // the old one would still claim it came from wherever it was first copied, an hour ago.
        if let existing = items.firstIndex(where: { $0.fingerprint == item.fingerprint }) {
            items.remove(at: existing)
        }
        items.insert(item, at: 0)
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
        enforceByteBudget()
    }

    private func enforceByteBudget() {
        let dropped = Self.evictionCount(sizes: items.map(\.byteCount), budget: maxBytes)
        if dropped > 0 { items.removeLast(dropped) }
    }

    /// How many entries to drop from the oldest end so the rest fit `budget`, given their sizes
    /// newest-first.
    ///
    /// The newest is never dropped, even when it busts the budget on its own: silently failing
    /// to record what someone just copied would be a far stranger bug than briefly going over.
    /// Pulled out as a pure function because an off-by-one here quietly eats history.
    static func evictionCount(sizes: [Int], budget: Int) -> Int {
        guard sizes.count > 1 else { return 0 }

        var total = sizes.reduce(0, +)
        var dropped = 0
        while dropped < sizes.count - 1, total > budget {
            total -= sizes[sizes.count - 1 - dropped]
            dropped += 1
        }
        return dropped
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
    }

    func purge() {
        items.removeAll()
    }
}
