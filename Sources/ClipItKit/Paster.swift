import AppKit
import Carbon.HIToolbox

/// Puts an item on the pasteboard, returns focus to whatever app you were in, and synthesizes
/// ⌘V there.
@MainActor
enum Paster {

    private static let vKeyCode = CGKeyCode(kVK_ANSI_V)

    // MARK: - Permission

    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Writing

    /// Writes every captured flavour, so pasting into Pages or Word keeps the original styling.
    static func placeOnPasteboard(_ item: ClipboardItem, plainOnly: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if plainOnly {
            let text = plainTextRepresentation(of: item)
            pasteboard.setString(text, forType: .string)
        } else if item.kind == .files, !item.fileURLs.isEmpty {
            pasteboard.writeObjects(item.fileURLs as [NSURL])
        } else {
            let pbItem = NSPasteboardItem()
            for (type, data) in item.representations {
                pbItem.setData(data, forType: type)
            }
            pasteboard.writeObjects([pbItem])
        }

        ClipboardMonitor.shared.suppressCurrentChange()
    }

    /// What ⌘⇧V should produce for a given item.
    static func plainTextRepresentation(of item: ClipboardItem) -> String {
        if !item.plainText.isEmpty { return item.plainText }

        // Fall back to flattening rich text when no plain flavour was captured.
        if let rtf = item.representations[.rtf],
           let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            return attributed.string
        }
        if let html = item.representations[.html],
           let attributed = try? NSAttributedString(
                data: html,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil) {
            return attributed.string
        }
        if item.kind == .files {
            return item.fileURLs.map(\.path).joined(separator: "\n")
        }
        return ""
    }

    // MARK: - Pasting

    /// Restores `target` to the front, then sends ⌘V.
    static func paste(_ item: ClipboardItem, plainOnly: Bool, into target: NSRunningApplication?) {
        guard ensureTrusted() else { return }

        placeOnPasteboard(item, plainOnly: plainOnly)
        activateAndPaste(target)
    }

    /// ⌘⇧V with no history involved: strip whatever is on the pasteboard right now, paste it,
    /// then put the original flavours back so the user's clipboard is unchanged afterwards.
    static func pasteCurrentAsPlainText(into target: NSRunningApplication?) {
        guard ensureTrusted() else { return }

        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            NSSound.beep()
            return
        }

        // Snapshot so we can restore formatting after the paste lands.
        let backup = snapshotPasteboard()

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        ClipboardMonitor.shared.suppressCurrentChange()

        activateAndPaste(target) {
            restorePasteboard(backup)
        }
    }

    // MARK: - Internals

    private static func ensureTrusted() -> Bool {
        guard isTrusted else {
            PermissionPrompt.show()
            return false
        }
        return true
    }

    private static func snapshotPasteboard() -> [NSPasteboard.PasteboardType: Data] {
        let pasteboard = NSPasteboard.general
        var snapshot: [NSPasteboard.PasteboardType: Data] = [:]
        for type in pasteboard.types ?? [] {
            if let data = pasteboard.data(forType: type) { snapshot[type] = data }
        }
        return snapshot
    }

    private static func restorePasteboard(_ snapshot: [NSPasteboard.PasteboardType: Data]) {
        guard !snapshot.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        for (type, data) in snapshot { item.setData(data, forType: type) }
        pasteboard.writeObjects([item])
        ClipboardMonitor.shared.suppressCurrentChange()
    }

    private static func activateAndPaste(_ target: NSRunningApplication?,
                                         completion: (() -> Void)? = nil) {
        if let target, !target.isActive {
            target.activate()
        }

        // The hotkey fires while ⌘⇧ (or ⌘⌥) are still physically held. Posting ⌘V now would
        // arrive as ⌘⇧V and re-trigger us, so wait for the user to let go first.
        waitForModifiersToClear {
            // Give the reactivated app a beat to install its first responder. Nothing to wait
            // for when it was already frontmost.
            let settle = (target == nil || target?.isActive == true) ? 0.0 : 0.045
            DispatchQueue.main.asyncAfter(deadline: .now() + settle) {
                sendCommandV()
                if let completion {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: completion)
                }
            }
        }
    }

    private static func waitForModifiersToClear(attempt: Int = 0, then body: @escaping () -> Void) {
        let held: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        let current = CGEventSource.flagsState(.combinedSessionState)

        // Bail out after ~600ms in case something is holding a modifier down for real.
        if current.intersection(held).isEmpty || attempt > 75 {
            body()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.008) {
            waitForModifiersToClear(attempt: attempt + 1, then: body)
        }
    }

    private static func sendCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents],
            state: .eventSuppressionStateSuppressionInterval)

        let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

@MainActor
enum PermissionPrompt {

    private static var isShowing = false

    static func show() {
        guard !isShowing else { return }
        isShowing = true
        defer { isShowing = false }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "ClipIt needs Accessibility access"
        alert.informativeText = """
            To paste into other apps, ClipIt has to send a ⌘V keystroke on your behalf. \
            macOS gates that behind Accessibility.

            Open System Settings › Privacy & Security › Accessibility and switch ClipIt on. \
            Your clipboard history keeps recording either way — only pasting is blocked.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            Paster.requestTrust()
            if let url = URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
