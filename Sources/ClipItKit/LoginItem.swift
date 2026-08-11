import Foundation
import ServiceManagement

/// "Open at Login", via the modern `SMAppService` API rather than the deprecated
/// login-items list.
///
/// This matters more here than for most apps: history is memory-only, so an instance that
/// isn't running after a reboot isn't just idle, it's absent — the user copies things all
/// morning and finds nothing recorded.
@MainActor
final class LoginItem: ObservableObject {

    static let shared = LoginItem()

    @Published private(set) var isEnabled: Bool = false

    private init() {
        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Returns an error message on failure, nil on success. Registration legitimately fails
    /// when the app is running from a DMG or the Downloads folder, so the caller needs to be
    /// able to say why rather than silently flipping the switch back.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                // Re-registering an already-registered app throws, so clear first.
                if SMAppService.mainApp.status == .enabled {
                    try? SMAppService.mainApp.unregister()
                }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
            return nil
        } catch {
            refresh()
            if !Bundle.main.bundlePath.hasPrefix("/Applications") {
                return "Move ClipIt to your Applications folder first, then try again."
            }
            return error.localizedDescription
        }
    }
}
