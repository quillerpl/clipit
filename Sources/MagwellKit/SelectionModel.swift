import Foundation
import Combine

/// Selection index shared between an AppKit controller and its SwiftUI content.
@MainActor
final class SelectionModel: ObservableObject {
    @Published var index: Int = 0
}

/// How the menu bar panel presents history.
enum ViewMode: String {
    case list
    case cards
}

/// UI preferences. Note this is *presentation* state only — clipboard contents are still
/// memory-only and never written to disk.
@MainActor
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    @Published var viewMode: ViewMode {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode") }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: "viewMode") ?? ViewMode.list.rawValue
        viewMode = ViewMode(rawValue: stored) ?? .list
    }
}

/// Escape hatch for main-thread-only AppKit types that aren't `Sendable`.
struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
