import SwiftUI

/// The narrow panel behind the menu bar icon. Its height is driven by the item count
/// (see `HistoryView.preferredHeight`) so it grows as the history fills up.
struct HistoryView: View {

    @ObservedObject var store = ClipboardStore.shared
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var loginItem = LoginItem.shared
    @ObservedObject var updater = Updater.shared
    @Binding var selection: Int

    /// Paste the item; the Bool is `plainOnly`.
    var onPaste: (ClipboardItem, Bool) -> Void
    var onPurge: () -> Void
    var onQuit: () -> Void

    static let rowHeight: CGFloat = 46
    static let width: CGFloat = 340
    static let searchRowHeight: CGFloat = 30
    private static let chromeHeight: CGFloat = 34 + 26   // header + footer
    private static let maxListHeight: CGFloat = rowHeight * 8.5

    /// Grows with the list, then caps and lets the list scroll. `hasSearch` accounts for the
    /// filter row, which only appears once there is enough history to be worth filtering.
    static func preferredHeight(itemCount: Int, hasSearch: Bool) -> CGFloat {
        let search = hasSearch ? searchRowHeight : 0
        guard itemCount > 0 else { return chromeHeight + search + 96 }
        let list = min(CGFloat(itemCount) * rowHeight + 8, maxListHeight)
        return chromeHeight + search + list
    }

    /// Below this the list fits on screen anyway and a filter box is just clutter.
    static let searchThreshold = 5

    private var showsSearch: Bool {
        store.items.count >= Self.searchThreshold || !store.query.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)

            if showsSearch {
                SearchField()
                    .padding(.horizontal, 10)
                    .frame(height: Self.searchRowHeight)
            }

            if store.items.isEmpty {
                emptyState
            } else if store.visibleItems.isEmpty {
                noMatches
            } else {
                list
            }

            Divider().opacity(0.5)
            footer
        }
        .frame(width: Self.width)
        .background(VisualEffectBackground())
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 6) {
            ViewModeToggle(mode: $settings.viewMode)
            Text("Clipboard")
                .font(.system(size: 12, weight: .semibold))
            if !store.items.isEmpty {
                Text(store.query.isEmpty
                     ? "\(store.items.count)"
                     : "\(store.visibleItems.count)/\(store.items.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            Spacer()
            Button(action: onPurge) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(store.items.isEmpty)
            .help("Purge clipboard history")

            Menu {
                Toggle("Open at Login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }))
                Button("Welcome & Shortcuts…") { WelcomeWindow.shared.show() }
                if let pending = updater.pendingUpdateVersion {
                    // A plain label, not a button: there is nothing to do about it, and the
                    // point is that it *doesn't* interrupt.
                    Text("Update \(pending) ready — installs when you quit")
                } else {
                    Button("Check for Updates…") { Updater.shared.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
                Divider()
                // Naming the consequence is the whole reason the badge exists.
                Button(updater.pendingUpdateVersion == nil ? "Quit ClipIt" : "Quit and Update ClipIt",
                       action: onQuit)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 16)
            .foregroundStyle(.secondary)
            .help("More")
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(store.visibleItems.enumerated()), id: \.element.id) { index, item in
                        HistoryRow(item: item,
                                   index: index,
                                   isSelected: index == selection,
                                   onPaste: { plainOnly in onPaste(item, plainOnly) },
                                   onDelete: { store.remove(item) })
                            .id(item.id)
                            .onHover { inside in
                                // Only when the pointer actually moved — see PointerGate.
                                if inside, PointerGate.shared.acceptsHover() { selection = index }
                            }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: selection) { _, new in
                guard store.visibleItems.indices.contains(new) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(store.visibleItems[new].id, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Nothing copied yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Copy something and it shows up here.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
    }

    private var noMatches: some View {
        VStack(spacing: 4) {
            Text("No matches")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("for “\(store.query)”")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            KeyHint(keys: "⌘⇧V", label: "paste plain")
            KeyHint(keys: "⌘⌥V", label: "switcher")
            Spacer()
            Text("⏎ paste")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
    }
}

struct KeyHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Text(keys)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.95))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.18)))
            // Explicit white opacity rather than .tertiary: the semantic tiers are tuned for
            // an opaque window and disappear against a translucent one.
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.70))
        }
    }
}

// MARK: - Row

struct HistoryRow: View {

    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let onPaste: (Bool) -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 9) {
            ClipBadge(item: item)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    ClipMetaLine(item: item)
                }
            }

            Spacer(minLength: 0)

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Remove from history")
            } else if index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: HistoryView.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.30) : .clear)
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { onPaste(false) }
        .contextMenu {
            Button("Paste") { onPaste(false) }
            Button("Paste as Plain Text") { onPaste(true) }
            Divider()
            Button("Remove", role: .destructive, action: onDelete)
        }
        .help(item.plainText.isEmpty ? item.title : String(item.plainText.prefix(600)))
    }
}
