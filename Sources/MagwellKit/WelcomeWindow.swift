import AppKit
import SwiftUI

/// Hosts `WelcomeView`. Shown once on first launch, and on demand from the menu.
@MainActor
final class WelcomeWindow: NSObject, NSWindowDelegate {

    static let shared = WelcomeWindow()

    private static let seenKey = "hasSeenWelcome"

    private var window: NSWindow?

    var hasBeenSeen: Bool {
        UserDefaults.standard.bool(forKey: Self.seenKey)
    }

    func showIfFirstRun() {
        guard !hasBeenSeen else { return }
        show()
    }

    func show() {
        PermissionState.shared.startWatching()
        LoginItem.shared.refresh()

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: WelcomeView(onFinish: { [weak self] in
            self?.close()
        }))

        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Magwell"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)

        // An accessory app has no Dock icon, so it must ask for focus explicitly or the
        // window opens behind whatever the user was doing.
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func close() {
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        PermissionState.shared.stopWatching()
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        PermissionState.shared.stopWatching()
        window = nil
    }
}
