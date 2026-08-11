import SwiftUI
import AppKit

/// First-run window. Without it a new user installs a menu bar app, sees nothing happen, and
/// has no idea the shortcuts exist or that macOS is silently blocking every paste.
struct WelcomeView: View {

    @ObservedObject var permission = PermissionState.shared
    @ObservedObject var loginItem = LoginItem.shared

    var onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            VStack(alignment: .leading, spacing: 14) {
                shortcut("⌘⇧V", "Paste without formatting",
                         "Strips fonts, colours and sizes. Your clipboard keeps the styled version.")
                shortcut("⌘⌥V", "Pick from recent copies",
                         "A small panel opens next to your cursor. Arrow keys to choose, Return to paste.")
                shortcut("􀣺", "Everything you've copied",
                         "Click the menu bar icon for the full history, with search.",
                         isMenuBarIcon: true)
            }
            .padding(20)

            Divider()
            permissionSection
            Divider()
            footer
        }
        .frame(width: 460)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text("Magwell")
                    .font(.system(size: 20, weight: .semibold))
                Text("Everything you copy, one keystroke away.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private func shortcut(_ keys: String, _ title: String, _ detail: String,
                          isMenuBarIcon: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if isMenuBarIcon {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 13))
                } else {
                    Text(keys)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
            }
            .frame(width: 52, height: 24)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var permissionSection: some View {
        HStack(spacing: 12) {
            Image(systemName: permission.isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(permission.isTrusted ? Color.green : Color.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(permission.isTrusted ? "Accessibility granted" : "One permission needed")
                    .font(.system(size: 12, weight: .medium))
                Text(permission.isTrusted
                     ? "Magwell can paste into other apps."
                     : "macOS requires this before any app can paste for you. Magwell asks for nothing else.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)

            if !permission.isTrusted {
                Button("Open Settings") { permission.promptAndOpenSettings() }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            Toggle("Open at login", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }))
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

            Spacer()
            Button("Start using Magwell", action: onFinish)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

/// Polls the Accessibility grant so the welcome window updates the moment the user flips the
/// switch in System Settings — there is no notification for it.
@MainActor
final class PermissionState: ObservableObject {

    static let shared = PermissionState()

    @Published private(set) var isTrusted: Bool = Paster.isTrusted

    private var timer: Timer?

    private init() {}

    func startWatching() {
        isTrusted = Paster.isTrusted
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let current = Paster.isTrusted
                if current != self.isTrusted { self.isTrusted = current }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    func promptAndOpenSettings() {
        Paster.requestTrust()
        if let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
