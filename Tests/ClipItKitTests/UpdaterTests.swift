import XCTest
@testable import ClipItKit

@MainActor
final class UpdaterTests: XCTestCase {

    /// Sparkle finds its delegate methods with `respondsToSelector:`, so a Swift signature that
    /// drifts from the Objective-C one fails *silently* — the app would go back to relaunching
    /// mid-session and wiping the memory-only history, with nothing to notice it by.
    func testInstallOnQuitHookIsVisibleToSparkle() {
        let selector = Selector(("updater:willInstallUpdateOnQuit:immediateInstallationBlock:"))

        XCTAssertTrue(Updater.shared.responds(to: selector),
                      "Sparkle will not park updates until quit if it cannot see this method")
    }
}
