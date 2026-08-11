import AppKit
import ApplicationServices

/// Finds where the user is actually typing, so the switcher can appear next to the insertion
/// point rather than parked in the middle of the screen.
///
/// Uses the same Accessibility permission the paste already needs, so this costs nothing extra.
@MainActor
enum CaretLocator {

    /// Best guess at the paste target, in Cocoa screen coordinates (origin bottom-left).
    /// Falls back to the focused control, then the pointer. Nil means "no idea".
    static func anchorRect() -> CGRect? {
        if let caret = caretRectInAXSpace() ?? focusedElementRectInAXSpace() {
            return convertFromAXSpace(caret)
        }
        // The pointer is a decent proxy: you generally clicked where you want to paste.
        let mouse = NSEvent.mouseLocation
        return CGRect(x: mouse.x, y: mouse.y, width: 1, height: 1)
    }

    // MARK: - Accessibility queries

    private static func caretRectInAXSpace() -> CGRect? {
        guard AXIsProcessTrusted(), let element = focusedElement() else { return nil }

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,
                                            kAXSelectedTextRangeAttribute as CFString,
                                            &rangeRef) == .success,
              let range = rangeRef, CFGetTypeID(range) == AXValueGetTypeID() else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                range,
                &boundsRef) == .success,
              let bounds = boundsRef, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.height > 0 else { return nil }
        return rect
    }

    private static func focusedElementRectInAXSpace() -> CGRect? {
        guard AXIsProcessTrusted(), let element = focusedElement() else { return nil }

        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString,
                                            &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString,
                                            &sizeRef) == .success,
              let positionValue = positionRef, CFGetTypeID(positionValue) == AXValueGetTypeID(),
              let sizeValue = sizeRef, CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }

        return CGRect(origin: origin, size: size)
    }

    private static func focusedElement() -> AXUIElement? {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(),
                                            kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID()
        else { return nil }
        return (element as! AXUIElement)
    }

    /// Accessibility reports rects with the origin at the top-left of the primary display;
    /// AppKit windows use bottom-left. Flip through the primary screen's height.
    private static func convertFromAXSpace(_ rect: CGRect) -> CGRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        return CGRect(x: rect.origin.x,
                      y: primary.frame.height - rect.origin.y - rect.height,
                      width: rect.width,
                      height: rect.height)
    }
}
