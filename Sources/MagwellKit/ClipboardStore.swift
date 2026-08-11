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

    private init() {}

    var visibleItems: [ClipboardItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return items }
        return items.filter { $0.matches(needle) }
    }

    func add(_ item: ClipboardItem) {
        // Re-copying something already in history promotes it instead of duplicating.
        if let existing = items.firstIndex(where: { $0.fingerprint == item.fingerprint }) {
            let promoted = items.remove(at: existing)
            items.insert(promoted, at: 0)
            return
        }
        items.insert(item, at: 0)
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
    }

    func purge() {
        items.removeAll()
    }
}
