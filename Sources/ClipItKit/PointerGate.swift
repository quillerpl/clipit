import AppKit

/// Decides when a hover is the user choosing something, rather than the UI moving underneath a
/// resting cursor.
///
/// Arrow keys animate the list to the new selection, which slides a *different* row under a
/// stationary pointer. SwiftUI reports that as a hover, hover sets the selection, and the
/// keyboard's choice is immediately overwritten by wherever the mouse happens to be sitting —
/// so holding ↓ appears to stick. Requiring the pointer to have actually moved lets each input
/// win while it is the one being used, with no modes and nothing to time out.
@MainActor
final class PointerGate {

    static let shared = PointerGate()

    private var lastLocation: NSPoint?

    private init() {}

    /// Call when a panel opens. Whatever the pointer already rests on was not a choice — the
    /// panel arrived under it.
    func reset() {
        lastLocation = NSEvent.mouseLocation
    }

    /// True when the pointer has moved since the last hover we honoured.
    func acceptsHover() -> Bool {
        let current = NSEvent.mouseLocation
        guard current != lastLocation else { return false }
        lastLocation = current
        return true
    }
}
