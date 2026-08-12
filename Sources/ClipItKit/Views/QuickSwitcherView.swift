import SwiftUI

/// The ⌘⌥V heads-up switcher: shows two entries at a time next to wherever you're typing.
/// Driveable by mouse (arrows or a click on a card) or keyboard (←/→, ⏎, esc).
///
/// Deliberately has no ⌘N shortcuts: the panel doesn't own the whole keyboard the way the
/// drawer does, so ⌘2 here would reach the app underneath and switch its tab instead.
struct QuickSwitcherView: View {

    @ObservedObject var store = ClipboardStore.shared
    @Binding var selection: Int

    var onPaste: (ClipboardItem) -> Void
    var onCancel: () -> Void

    // Same card metrics as the drawer, so the two panels read as one design.
    static let cardWidth: CGFloat = CardDrawerView.cardWidth
    static let cardHeight: CGFloat = CardDrawerView.cardHeight

    /// Exactly two cards fit without scrolling; arrows page through the rest.
    static let visibleCards = 2
    private static let arrowWidth: CGFloat = 26

    /// Which entry the switcher opens on.
    ///
    /// Index 0 is the head of history — exactly what a plain ⌘V already pastes — so landing
    /// there spends the whole gesture to achieve nothing. Start one back, for the same reason
    /// ⌘Tab starts on the previous app rather than the one you're already in: ⌘⌥V ⏎ then means
    /// "the thing before this", which is what people reach for the switcher to get.
    static func initialSelection(itemCount: Int) -> Int {
        itemCount >= 2 ? 1 : 0
    }

    static let width: CGFloat = CGFloat(visibleCards) * cardWidth + 10   // cards + gap
        + arrowWidth * 2 + 24                                           // arrows + padding
    static let height: CGFloat = cardHeight + 52

    private var items: [ClipboardItem] { store.visibleItems }
    private var needsPaging: Bool { items.count > Self.visibleCards }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                arrow(systemName: "chevron.left", enabled: selection > 0) { move(by: -1) }
                cards
                arrow(systemName: "chevron.right",
                      enabled: selection < items.count - 1) { move(by: 1) }
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)

            Spacer(minLength: 0)
            captionBar
        }
        .frame(width: Self.width, height: Self.height)
        .background(
            ZStack {
                PanelBackground()
                // Anywhere that isn't a card or a button drags the panel out of the way.
                WindowDragHandle()
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Pieces

    /// A window of two cards centred on the selection, rather than a scroller — with only two
    /// slots, scrolling reads as jitter.
    private var window: [(offset: Int, element: ClipboardItem)] {
        CardWindow.range(selection: selection, count: items.count, visible: Self.visibleCards)
            .map { ($0, items[$0]) }
    }

    private var cards: some View {
        HStack(spacing: 10) {
            ForEach(window, id: \.element.id) { index, item in
                ClipCard(item: item,
                         isSelected: index == selection,
                         width: Self.cardWidth,
                         height: Self.cardHeight)
                    .onTapGesture {
                        // First click focuses, second commits — matches how the keyboard path
                        // feels, and avoids mis-pastes on a stray click.
                        if index == selection { onPaste(item) } else { selection = index }
                    }
            }
        }
        .frame(width: CGFloat(Self.visibleCards) * Self.cardWidth + 10, alignment: .leading)
        .animation(.easeOut(duration: 0.14), value: selection)
    }

    @ViewBuilder
    private func arrow(systemName: String, enabled: Bool,
                       action: @escaping () -> Void) -> some View {
        if needsPaging {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: Self.arrowWidth, height: Self.cardHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(enabled ? Color.white.opacity(0.75) : Color.white.opacity(0.20))
            .disabled(!enabled)
        } else {
            // Keep the slot so the cards stay put whether or not paging is available.
            Color.clear.frame(width: Self.arrowWidth, height: Self.cardHeight)
        }
    }

    private var captionBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.40))
                .help("Drag to move this panel")
            if let item = current { ClipMetaLine(item: item) }
            if needsPaging {
                Text("\(selection + 1) of \(items.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            Spacer()
            KeyHint(keys: "← →", label: "select")
            KeyHint(keys: "⏎", label: "paste")
            KeyHint(keys: "esc", label: "close")
        }
        .padding(.horizontal, 16)
        .frame(height: 30)
    }

    private var current: ClipboardItem? {
        items.indices.contains(selection) ? items[selection] : nil
    }

    private func move(by delta: Int) {
        let next = selection + delta
        guard items.indices.contains(next) else { return }
        selection = next
    }
}
