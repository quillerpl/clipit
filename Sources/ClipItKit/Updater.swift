import AppKit
import Sparkle

/// Auto-update via Sparkle.
///
/// ClipIt is a menu bar app with no main window, so it can't rely on a standard app menu to
/// carry "Check for Updates" — the item lives in the panel's ••• menu and drives this.
@MainActor
final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate {

    static let shared = Updater()

    /// Published so the menu item can disable itself while an check is impossible.
    @Published private(set) var canCheckForUpdates = false

    /// Version of an update that is downloaded and waiting for ClipIt to quit, if any.
    ///
    /// Updates install silently here, which is the right trade for a memory-only history but
    /// leaves the user with no idea anything happened. This is the quiet signal: a dot on the
    /// menu bar icon and a line in the ••• menu, rather than a dialog that interrupts.
    @Published private(set) var pendingUpdateVersion: String?

    private var controller: SPUStandardUpdaterController?
    private var observation: NSKeyValueObservation?

    private override init() {
        super.init()
    }

    /// Sparkle refuses to start without a feed URL, which is exactly right for a local
    /// development build — so a missing `SUFeedURL` disables updating rather than crashing.
    func start() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            NSLog("ClipIt: no SUFeedURL in Info.plist — auto-update disabled for this build")
            return
        }

        let controller = SPUStandardUpdaterController(startingUpdater: true,
                                                     updaterDelegate: self,
                                                     userDriverDelegate: nil)
        self.controller = controller

        // Read the value out of the KVO change rather than off the updater, and hop to the
        // singleton instead of capturing self: the closure is nonisolated, and capturing a
        // main-actor `self` across it is rejected by some toolchains.
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) {
            _, change in
            guard let value = change.newValue else { return }
            Task { @MainActor in Updater.shared.canCheckForUpdates = value }
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    // MARK: - SPUUpdaterDelegate

    /// Park a downloaded update until ClipIt quits, instead of letting Sparkle escalate to an
    /// "Install and Relaunch" alert.
    ///
    /// A relaunch destroys the history — it lives in memory and nowhere else — so an update
    /// arriving mid-afternoon would silently eat the morning's clipboard. Returning `true`
    /// stalls Sparkle's update cycle so it stops asking; deliberately *not* calling
    /// `immediateInstallHandler` is what keeps the running session intact. Sparkle's on-quit
    /// installer does not relaunch the app, so the update lands invisibly on next launch.
    func updater(_ updater: SPUUpdater,
                 willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        pendingUpdateVersion = item.displayVersionString
        return true
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }
}
