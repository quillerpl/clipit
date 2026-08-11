import AppKit
import Sparkle

/// Auto-update via Sparkle.
///
/// Magwell is a menu bar app with no main window, so it can't rely on a standard app menu to
/// carry "Check for Updates" — the item lives in the panel's ••• menu and drives this.
@MainActor
final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate {

    static let shared = Updater()

    /// Published so the menu item can disable itself while an check is impossible.
    @Published private(set) var canCheckForUpdates = false

    private var controller: SPUStandardUpdaterController?
    private var observation: NSKeyValueObservation?

    private override init() {
        super.init()
    }

    /// Sparkle refuses to start without a feed URL, which is exactly right for a local
    /// development build — so a missing `SUFeedURL` disables updating rather than crashing.
    func start() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            NSLog("Magwell: no SUFeedURL in Info.plist — auto-update disabled for this build")
            return
        }

        let controller = SPUStandardUpdaterController(startingUpdater: true,
                                                     updaterDelegate: self,
                                                     userDriverDelegate: nil)
        self.controller = controller

        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) {
            [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheckForUpdates = value }
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }
}
