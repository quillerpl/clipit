import SwiftUI

/// Understated inline filter. Present but quiet — no heavy chrome, no dedicated toolbar row of
/// its own in the drawer, and never hidden behind a disclosure icon.
struct SearchField: View {

    @ObservedObject var store = ClipboardStore.shared
    @ObservedObject var focus = SearchFocus.shared
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isFocused ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))

            TextField("Search", text: $store.query)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .focused($isFocused)
                .onSubmit { isFocused = false }

            if !store.query.isEmpty {
                Button {
                    store.query = ""
                    isFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(isFocused ? 0.12 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isFocused ? 0.8 : 0), lineWidth: 1)
        )
        // ⌘F from the panel's key handler bumps a counter rather than reaching in directly —
        // @FocusState can only be driven from inside the view that owns it.
        .onChange(of: focus.requests) { _, _ in isFocused = true }
        .onChange(of: focus.dismissals) { _, _ in isFocused = false }
    }
}

/// Lets AppKit ask SwiftUI to focus or blur the search field.
@MainActor
final class SearchFocus: ObservableObject {
    static let shared = SearchFocus()
    @Published private(set) var requests = 0
    @Published private(set) var dismissals = 0

    private init() {}

    func request() { requests += 1 }
    func dismiss() { dismissals += 1 }
}
