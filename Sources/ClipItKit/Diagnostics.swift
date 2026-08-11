import AppKit
import ApplicationServices

/// `ClipIt --check-trust`. The System Settings switch can read ON while the app is actually
/// denied (see README), so this reports what the API returns rather than what the UI claims.
@MainActor
public enum Diagnostics {

    @discardableResult
    public static func reportTrust() -> Bool {
        let trusted = AXIsProcessTrusted()
        print("AXIsProcessTrusted() = \(trusted)")
        print("bundle = \(Bundle.main.bundlePath)")
        print("bundleIdentifier = \(Bundle.main.bundleIdentifier ?? "nil")")
        return trusted
    }
}
