import AppKit
import MagwellKit

// Top-level code in a SwiftPM executable is not implicitly main-actor isolated, but it does
// run on the main thread — assert that so the @MainActor types can be built here.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let arguments = CommandLine.arguments

    // Development hooks. See SnapshotRenderer / IconRenderer.
    if let flag = arguments.firstIndex(of: "--snapshot"), arguments.count > flag + 1 {
        application.setActivationPolicy(.accessory)
        SnapshotRenderer.run(outputDirectory: arguments[flag + 1])
    }
    if let flag = arguments.firstIndex(of: "--make-icon"), arguments.count > flag + 1 {
        IconRenderer.run(outputDirectory: arguments[flag + 1])
    }

    // Diagnostic: report what the Accessibility API actually thinks of this binary.
    if arguments.contains("--check-trust") {
        let trusted = Diagnostics.reportTrust()
        exit(trusted ? 0 : 1)
    }

    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    // Kept alive for the process lifetime.
    objc_setAssociatedObject(application, "MagwellDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    application.run()
}
