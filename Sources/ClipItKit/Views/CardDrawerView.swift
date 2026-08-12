import SwiftUI

/// The wide translucent drawer that drops under the menu bar when you switch the panel to
/// card view. Same data as the list, laid out horizontally so each entry shows its content.
struct CardDrawerView: View {

    @ObservedObject var store = ClipboardStore.shared
    @ObservedObject var settings = AppSettings.shared
    @Binding var selection: Int

    var onPaste: (ClipboardItem, Bool) -> Void
    var onPurge: () -> Void
    var onClose: () -> Void

    static let cardWidth: CGFloat = 208
    static let cardHeight: CGFloat = 152
    static let height: CGFloat = cardHeight + 54

    static func preferredWidth(for screen: NSScreen) -> CGFloat {
        let content = CGFloat(max(1, min(ClipboardStore.shared.items.count, 8)))
        let ideal = content * (cardWidth + 10) + 40
        return min(max(ideal, 620), screen.visibleFrame.width - 32)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            cards
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background(PanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            ViewModeToggle(mode: $settings.viewMode)

            Text("Clipboard")
                .font(.system(size: 12, weight: .semibold))
            Text(store.query.isEmpty
                 ? "\(store.items.count)"
                 : "\(store.visibleItems.count)/\(store.items.count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.white.opacity(0.12)))

            SearchField()
                .frame(width: 190)
                .padding(.leading, 6)

            Spacer()

            KeyHint(keys: "⌘1–9", label: "paste")
            KeyHint(keys: "esc", label: "close")

            Button(action: onPurge) {
                Image(systemName: "trash").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(store.items.isEmpty)
            .help("Purge clipboard history")

            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close")
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
    }

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(store.visibleItems.enumerated()), id: \.element.id) { index, item in
                        ClipCard(item: item,
                                 isSelected: index == selection,
                                 width: Self.cardWidth,
                                 height: Self.cardHeight,
                                 shortcut: index + 1)
                            .id(item.id)
                            .onTapGesture { onPaste(item, false) }
                            // Only when the pointer actually moved — see PointerGate.
                            .onHover { if $0, PointerGate.shared.acceptsHover() { selection = index } }
                            .contextMenu {
                                Button("Paste") { onPaste(item, false) }
                                Button("Paste as Plain Text") { onPaste(item, true) }
                                Divider()
                                Button("Remove", role: .destructive) { store.remove(item) }
                            }
                    }
                    if store.visibleItems.isEmpty {
                        Text(store.items.isEmpty ? "Nothing copied yet"
                                                 : "No matches for “\(store.query)”")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(height: Self.cardHeight)
                            .padding(.horizontal, 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .padding(.top, 2)
            }
            .onChange(of: selection) { _, new in
                guard store.visibleItems.indices.contains(new) else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(store.visibleItems[new].id, anchor: .center)
                }
            }
        }
    }
}

/// The list ↔ cards segmented switch, shared by both panels.
struct ViewModeToggle: View {
    @Binding var mode: ViewMode

    var body: some View {
        HStack(spacing: 0) {
            button(.list, symbol: "list.bullet", help: "List view")
            button(.cards, symbol: "rectangle.grid.2x2", help: "Card view")
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.10)))
    }

    private func button(_ target: ViewMode, symbol: String, help: String) -> some View {
        Button { mode = target } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 22, height: 16)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(mode == target ? Color.white.opacity(0.18) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(mode == target ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .help(help)
    }
}
