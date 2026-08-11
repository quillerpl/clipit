import AppKit
import SwiftUI

/// Borderless floating panel that hosts `QuickSwitcherView`. A `.nonactivatingPanel` that can
/// still become key, so it takes arrow keys without a Dock-icon-style app switch.
final class QuickSwitcherPanel: NSPanel {

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Drag it out of the way by grabbing anywhere that isn't a card or a button.
        isMovableByWindowBackground = true
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    static var activeScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }

    /// Places the panel just below `anchor` — the caret, or whatever we could find — so it
    /// reads as belonging to the spot you're pasting into. Flips above when there's no room
    /// underneath, and is always clamped onto the screen.
    func position(near anchor: CGRect?) {
        guard let anchor else { return positionCentred() }

        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) }
            ?? Self.activeScreen
        guard let visible = screen?.visibleFrame else { return positionCentred() }

        let size = frame.size
        let gap: CGFloat = 12

        var y = anchor.minY - gap - size.height          // below the caret
        if y < visible.minY {
            let above = anchor.maxY + gap               // not enough room: go above
            y = (above + size.height <= visible.maxY) ? above : visible.minY + gap
        }

        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + gap), visible.maxX - size.width - gap)

        setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func positionCentred() {
        guard let visible = Self.activeScreen?.visibleFrame else { return }
        let size = frame.size
        setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                               y: visible.midY - size.height / 2 + visible.height * 0.12))
    }

    /// Drops the drawer just below the menu bar, centred — it reads as pulled down from the
    /// status item rather than floating loose in the middle of the screen.
    func positionUnderMenuBar() {
        guard let screen = Self.activeScreen else { return }
        let visible = screen.visibleFrame
        let size = frame.size
        setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                               y: visible.maxY - size.height - 8))
    }
}
