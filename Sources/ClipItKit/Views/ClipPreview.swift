import SwiftUI

/// Translucent window backing. `.hudWindow` is the dark vibrant material the system uses for
/// heads-up panels, which is what gives the panels their see-through look.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    /// `.behindWindow` samples the desktop, which is right in the app but renders as nothing
    /// offscreen. Snapshots put a backdrop view inside the same window instead, so they need
    /// `.withinWindow` to show the translucency the user actually sees.
    @MainActor static var blendsWithinWindow = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = Self.blendsWithinWindow ? .withinWindow : .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Makes an area drag its window. `isMovableByWindowBackground` alone is unreliable under
/// SwiftUI — the hosting view swallows the mouseDown before AppKit sees it — so this forwards
/// the event to `performDrag` explicitly.
struct WindowDragHandle: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
        override func hitTest(_ point: NSPoint) -> NSView? {
            // Only claim clicks that no control above us wanted.
            super.hitTest(point)
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Panel backing: the vibrant material plus a dark scrim. The material alone picks up too much
/// of whatever is behind it, which makes small dimmed text hard to read over a bright window.
struct PanelBackground: View {
    var scrim: Double = 0.55

    var body: some View {
        ZStack {
            VisualEffectBackground()
            Color.black.opacity(scrim)
        }
    }
}

/// Shared visual language for a clipboard entry: the small leading badge (thumbnail for images
/// and files, a glyph for text) used by the history list.
struct ClipBadge: View {
    @ObservedObject var item: ClipboardItem
    var side: CGFloat = 34

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.08))

            if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(item.thumbnailIsContent ? 2 : 5)
            } else {
                Image(systemName: item.symbolName)
                    .font(.system(size: side * 0.4, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

/// "Chrome · 2m ago · styled" — the dimmed metadata line.
struct ClipMetaLine: View {
    @ObservedObject var item: ClipboardItem

    var body: some View {
        HStack(spacing: 4) {
            if let icon = item.sourceAppIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 11, height: 11)
                    .opacity(0.85)
            }
            Text(components.joined(separator: " · "))
                .lineLimit(1)
        }
        .font(.system(size: 10))
        .foregroundStyle(Color.white.opacity(0.72))
    }

    private var components: [String] {
        var parts: [String] = []
        if let name = item.sourceAppName { parts.append(name) }
        parts.append(RelativeTime.string(for: item.date))
        if item.kind == .text {
            let lines = item.lineCount
            if lines > 1 { parts.append("\(lines) lines") }
            if item.hasFormatting { parts.append("styled") }
        }
        return parts
    }
}

enum RelativeTime {
    /// Deliberately terse — this sits in a 10pt line inside a 340pt-wide popover.
    static func string(for date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        switch seconds {
        case ..<5:      return "just now"
        case ..<60:     return "\(seconds)s ago"
        case ..<3600:   return "\(seconds / 60)m ago"
        case ..<86_400: return "\(seconds / 3600)h ago"
        default:        return "\(seconds / 86_400)d ago"
        }
    }
}

// MARK: - Card

/// Full-content preview card, shared by the ⌘⌥V switcher and the card drawer.
/// Body shows the content itself; the footer carries provenance and the ⌘N shortcut.
struct ClipCard: View {

    @ObservedObject var item: ClipboardItem
    let isSelected: Bool
    var width: CGFloat = 132
    var height: CGFloat = 104
    /// 1-based position; renders a ⌘N badge for the first nine.
    var shortcut: Int? = nil

    private var isCompact: Bool { width < 170 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()

            footer
        }
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.white.opacity(0.14),
                              lineWidth: isSelected ? 2.5 : 1)
        )
        .shadow(color: .black.opacity(isSelected ? 0.35 : 0), radius: 8, y: 3)
        .scaleEffect(isSelected ? 1.0 : 0.97)
        .animation(.easeOut(duration: 0.14), value: isSelected)
        // Focus survives a high-contrast or colour-blind setting: border weight + scale +
        // shadow all change, not just the hue.
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .help(item.plainText.isEmpty ? item.title : String(item.plainText.prefix(600)))
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if let icon = item.sourceAppIcon {
                Image(nsImage: icon).resizable().frame(width: 11, height: 11)
            }
            Text(caption)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            if !isCompact {
                Spacer(minLength: 4)
                Text(RelativeTime.string(for: item.date))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            if let shortcut, shortcut <= 9 {
                Text("⌘\(shortcut)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.10)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.22))
    }

    /// The body already shows the text, so text cards caption themselves with their origin
    /// instead of repeating the first line.
    private var caption: String {
        switch item.kind {
        case .text: return item.sourceAppName ?? "Text"
        default:    return isCompact ? item.title : (item.sourceAppName ?? item.title)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let image = item.image, item.kind == .image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if item.kind == .files {
            // A Quick Look preview of a copied photo or PDF fills the card; a plain document
            // icon does not, so it keeps its filename caption underneath.
            if item.thumbnailIsContent, let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 4) {
                    ClipBadge(item: item, side: 30)
                    Text(item.title)
                        .font(.system(size: 9))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            Text(item.plainText.prefix(400))
                .font(.system(size: isCompact ? 9 : 10))
                .foregroundStyle(.primary.opacity(0.9))
                .lineLimit(isCompact ? 6 : 8)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(isCompact ? 7 : 9)
        }
    }
}

