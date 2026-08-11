import Foundation

/// Which slice of the history the ⌘⌥V switcher shows.
///
/// The switcher displays a fixed number of cards with no scrolling, so the visible range has
/// to be derived from the selection alone. Pulled out of the view because the clamping is
/// exactly the kind of off-by-one that silently shows the wrong card.
enum CardWindow {

    /// Range of indices to display: the selection plus the following card where possible,
    /// shifting back at the end of the list. Always in bounds; empty when there is nothing.
    static func range(selection: Int, count: Int, visible: Int) -> Range<Int> {
        guard count > 0, visible > 0 else { return 0..<0 }

        let size = min(visible, count)
        let clampedSelection = min(max(selection, 0), count - 1)

        // Prefer the selection at the leading edge — reading order is "this one, then next".
        var start = clampedSelection
        if start + size > count { start = count - size }   // ran off the end: shift back
        start = max(0, start)

        return start..<(start + size)
    }
}
