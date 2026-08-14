import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    public override init() { super.init() }

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let historySelection = SelectionModel()

    private var switcherPanel: QuickSwitcherPanel?
    private let switcherSelection = SelectionModel()

    private var drawerPanel: QuickSwitcherPanel?
    private let drawerSelection = SelectionModel()
    private var drawerResignObserver: Any?

    private var keyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    /// Whatever app was frontmost before we stole focus — the paste target.
    private var lastActiveApp: NSRunningApplication?

    // MARK: - Lifecycle

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setUpStatusItem()
        setUpPopover()
        trackFrontmostApp()
        registerHotKeys()

        ClipboardMonitor.shared.start()
        Updater.shared.start()

        // Resize the popover as history grows or the filter narrows it, so the panel "grows
        // the more items is inside".
        ClipboardStore.shared.$items.map { _ in () }
            .merge(with: ClipboardStore.shared.$query.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updatePopoverSize() }
            .store(in: &cancellables)

        // An update parked for the next quit is the only thing that changes the menu bar glyph.
        Updater.shared.$pendingUpdateVersion
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusItemImage() }
            .store(in: &cancellables)

        // First run gets the welcome window, which explains the shortcuts and walks the user
        // through Accessibility. After that, only nag if the permission is actually missing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if !WelcomeWindow.shared.hasBeenSeen {
                WelcomeWindow.shared.show()
            } else if !Paster.isTrusted {
                PermissionPrompt.show()
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        ClipboardMonitor.shared.stop()
        HotKeyManager.shared.unregisterAll()
        ClipboardStore.shared.purge()
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        // Variable rather than square: the update dot makes the glyph a few points wider, and a
        // square item would crop it off.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(toggleHistory)
            button.target = self
        }
        refreshStatusItemImage()
    }

    /// Redraws the menu bar glyph, with a dot when an update is parked waiting for a quit.
    private func refreshStatusItemImage() {
        guard let button = statusItem?.button else { return }
        let pending = Updater.shared.pendingUpdateVersion
        button.image = StatusItemIcon.image(badged: pending != nil)
        button.setAccessibilityLabel(pending.map { "ClipIt — update to \($0) installs when you quit" }
                                     ?? "ClipIt")
    }

    private func setUpPopover() {
        let root = HistoryContainer(
            selection: historySelection,
            onPaste: { [weak self] item, plainOnly in self?.pasteFromPopover(item, plainOnly: plainOnly) },
            onPurge: { [weak self] in self?.purge() },
            onQuit: { NSApp.terminate(nil) }
        )
        popover.contentViewController = NSHostingController(rootView: root)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        // Dark chrome for the popover frame itself, so the arrow and edges match the
        // translucent content rather than sitting in a light system container.
        popover.appearance = NSAppearance(named: .vibrantDark)
        updatePopoverSize()

        // Flipping the toggle in either panel swaps which one is on screen.
        AppSettings.shared.$viewMode
            .receive(on: RunLoop.main)
            .dropFirst()
            .sink { [weak self] mode in self?.applyViewMode(mode) }
            .store(in: &cancellables)
    }

    private func updatePopoverSize() {
        let store = ClipboardStore.shared
        let hasSearch = store.items.count >= HistoryView.searchThreshold || !store.query.isEmpty
        popover.contentSize = NSSize(
            width: HistoryView.width,
            height: HistoryView.preferredHeight(itemCount: store.visibleItems.count,
                                                hasSearch: hasSearch))
    }

    /// The filter is a transient lens, not a setting — every panel opens showing everything.
    private func resetSearch() {
        ClipboardStore.shared.query = ""
        SearchFocus.shared.dismiss()
    }

    @objc private func toggleHistory() {
        switch AppSettings.shared.viewMode {
        case .list:
            popover.isShown ? popover.performClose(nil) : showHistory()
        case .cards:
            drawerPanel != nil ? dismissDrawer() : showDrawer()
        }
    }

    /// Called when the list/cards toggle flips. Whichever panel is open hands over to the other.
    private func applyViewMode(_ mode: ViewMode) {
        let wasOpen = popover.isShown || drawerPanel != nil
        popover.performClose(nil)
        dismissDrawer()
        guard wasOpen else { return }
        // Let the outgoing panel finish closing before the replacement appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            switch mode {
            case .list:  self.showHistory()
            case .cards: self.showDrawer()
            }
        }
    }

    private func showHistory() {
        guard let button = statusItem.button else { return }
        lastActiveApp = NSWorkspace.shared.frontmostApplication
        historySelection.index = 0
        PointerGate.shared.reset()
        resetSearch()
        updatePopoverSize()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Showing a popover does not give it the keyboard, and a local event monitor only sees
        // keys that were delivered to us — so without this, ↑/↓ never reach `handle()` and
        // macOS beeps instead. The card drawer never had the bug because a panel takes focus
        // for itself with `makeKeyAndOrderFront`.
        popover.contentViewController?.view.window?.makeKey()
        installKeyMonitor(for: .history)
    }

    public func popoverDidClose(_ notification: Notification) {
        removeKeyMonitor()
        resetSearch()
    }

    // MARK: - Card drawer

    private func showDrawer() {
        guard drawerPanel == nil, let screen = QuickSwitcherPanel.activeScreen else { return }
        lastActiveApp = NSWorkspace.shared.frontmostApplication
        drawerSelection.index = 0
        PointerGate.shared.reset()
        resetSearch()

        let rect = NSRect(x: 0, y: 0,
                          width: CardDrawerView.preferredWidth(for: screen),
                          height: CardDrawerView.height)
        let panel = QuickSwitcherPanel(contentRect: rect)

        let root = DrawerContainer(
            selection: drawerSelection,
            onPaste: { [weak self] item, plainOnly in
                self?.pasteFromDrawer(item, plainOnly: plainOnly)
            },
            onPurge: { [weak self] in self?.purge() },
            onClose: { [weak self] in self?.dismissDrawer() }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = rect
        panel.contentView = hosting
        panel.positionUnderMenuBar()
        panel.makeKeyAndOrderFront(nil)

        drawerPanel = panel
        installKeyMonitor(for: .drawer)

        // Click-away dismissal, matching the popover's transient behaviour.
        drawerResignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissDrawer() }
        }
    }

    private func dismissDrawer() {
        guard drawerPanel != nil else { return }
        if let drawerResignObserver { NotificationCenter.default.removeObserver(drawerResignObserver) }
        drawerResignObserver = nil
        removeKeyMonitor()
        drawerPanel?.orderOut(nil)
        drawerPanel = nil
        resetSearch()
    }

    private func pasteFromDrawer(_ item: ClipboardItem, plainOnly: Bool) {
        let target = lastActiveApp
        dismissDrawer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            Paster.paste(item, plainOnly: plainOnly, into: target)
        }
    }

    // MARK: - Quick switcher

    private func toggleSwitcher() {
        if switcherPanel != nil {
            dismissSwitcher()
            return
        }
        guard !ClipboardStore.shared.items.isEmpty else {
            NSSound.beep()
            return
        }
        resetSearch()
        showSwitcher()
    }

    private func showSwitcher() {
        lastActiveApp = NSWorkspace.shared.frontmostApplication
        switcherSelection.index = QuickSwitcherView.initialSelection(
            itemCount: ClipboardStore.shared.visibleItems.count)

        let rect = NSRect(x: 0, y: 0,
                          width: QuickSwitcherView.width,
                          height: QuickSwitcherView.height)
        let panel = QuickSwitcherPanel(contentRect: rect)

        let root = SwitcherContainer(
            selection: switcherSelection,
            onPaste: { [weak self] item in self?.pasteFromSwitcher(item) },
            onCancel: { [weak self] in self?.dismissSwitcher() }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = rect
        panel.contentView = hosting
        // Sit next to the insertion point rather than the middle of the screen — you're about
        // to paste *there*, so that is where the choice belongs.
        panel.position(near: CaretLocator.anchorRect())
        panel.makeKeyAndOrderFront(nil)

        switcherPanel = panel
        installKeyMonitor(for: .switcher)
    }

    private func dismissSwitcher() {
        removeKeyMonitor()
        switcherPanel?.orderOut(nil)
        switcherPanel = nil
    }

    // MARK: - Actions

    private func pasteFromPopover(_ item: ClipboardItem, plainOnly: Bool) {
        popover.performClose(nil)
        let target = lastActiveApp
        // Let the popover finish closing before we hand focus back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Paster.paste(item, plainOnly: plainOnly, into: target)
        }
    }

    private func pasteFromSwitcher(_ item: ClipboardItem) {
        let target = lastActiveApp
        dismissSwitcher()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Paster.paste(item, plainOnly: false, into: target)
        }
    }

    private func purge() {
        ClipboardStore.shared.purge()
        NSPasteboard.general.clearContents()
        ClipboardMonitor.shared.suppressCurrentChange()
    }

    // MARK: - Hotkeys

    private func registerHotKeys() {
        let v = UInt32(kVK_ANSI_V)

        // ⌘⇧V — paste whatever is on the clipboard, stripped of formatting.
        HotKeyManager.shared.register(
            keyCode: v,
            modifiers: HotKeyManager.Modifiers.command | HotKeyManager.Modifiers.shift
        ) { [weak self] in
            guard let self else { return }
            self.lastActiveApp = NSWorkspace.shared.frontmostApplication
            Paster.pasteCurrentAsPlainText(into: self.lastActiveApp)
        }

        // ⌘⌥V — heads-up switcher.
        HotKeyManager.shared.register(
            keyCode: v,
            modifiers: HotKeyManager.Modifiers.command | HotKeyManager.Modifiers.option
        ) { [weak self] in
            self?.toggleSwitcher()
        }
    }

    // MARK: - Keyboard

    private enum KeyContext { case history, switcher, drawer }

    /// True when a text field owns the keyboard — SwiftUI's TextField is backed by the
    /// window's shared field editor, an NSTextView.
    private var isEditingSearch: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView
    }

    private func closePanel(for context: KeyContext) {
        switch context {
        case .history:  popover.performClose(nil)
        case .switcher: dismissSwitcher()
        case .drawer:   dismissDrawer()
        }
    }

    private func installKeyMonitor(for context: KeyContext) {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // The monitor always fires on the main thread; NSEvent just isn't Sendable, so it
            // has to be smuggled across the isolation check.
            let boxed = UncheckedBox(event)
            let consumed = MainActor.assumeIsolated { self.handle(boxed.value, in: context) }
            return consumed ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true when the key was consumed and should not reach the rest of the app.
    private func handle(_ event: NSEvent, in context: KeyContext) -> Bool {
        // Always the filtered list: the rows on screen and the shortcut indices must agree.
        let items = ClipboardStore.shared.visibleItems
        let model: SelectionModel
        switch context {
        case .history:  model = historySelection
        case .switcher: model = switcherSelection
        case .drawer:   model = drawerSelection
        }
        let forwardKey = context == .history ? kVK_DownArrow : kVK_RightArrow
        let backKey = context == .history ? kVK_UpArrow : kVK_LeftArrow

        func commit(plainOnly: Bool) {
            guard items.indices.contains(model.index) else { return }
            let item = items[model.index]
            switch context {
            case .history:  pasteFromPopover(item, plainOnly: plainOnly)
            case .switcher: pasteFromSwitcher(item)
            case .drawer:   pasteFromDrawer(item, plainOnly: plainOnly)
            }
        }

        // ⌘F focuses the filter box from any panel.
        if event.keyCode == kVK_ANSI_F, event.modifierFlags.contains(.command) {
            SearchFocus.shared.request()
            return true
        }

        // While the search field has the keyboard, plain typing belongs to it — otherwise "1"
        // would paste instead of filtering. Navigation and dismissal still work.
        if isEditingSearch {
            switch Int(event.keyCode) {
            case kVK_Escape:
                if ClipboardStore.shared.query.isEmpty {
                    SearchFocus.shared.dismiss()
                    closePanel(for: context)
                } else {
                    ClipboardStore.shared.query = ""
                }
                return true
            case kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow,
                 kVK_Return, kVK_ANSI_KeypadEnter:
                SearchFocus.shared.dismiss()
                model.index = 0
                return true
            default:
                return false
            }
        }

        switch Int(event.keyCode) {
        case kVK_Escape:
            switch context {
            case .history:  popover.performClose(nil)
            case .switcher: dismissSwitcher()
            case .drawer:   dismissDrawer()
            }
            return true

        case forwardKey:
            if !items.isEmpty { model.index = min(model.index + 1, items.count - 1) }
            return true

        case backKey:
            if !items.isEmpty { model.index = max(model.index - 1, 0) }
            return true

        case kVK_Return, kVK_ANSI_KeypadEnter:
            commit(plainOnly: event.modifierFlags.contains(.shift))
            return true

        case kVK_Tab:
            // ⌘⌥V then Tab / ⇧Tab reads naturally as "next / previous", like ⌘Tab.
            guard context == .switcher, !items.isEmpty else { return false }
            let delta = event.modifierFlags.contains(.shift) ? -1 : 1
            model.index = (model.index + delta + items.count) % items.count
            return true

        default:
            // Number keys jump straight to an entry: bare 1–9 in the list, ⌘1–9 in the drawer
            // (matching the ⌘N badges on the cards).
            guard context == .history || context == .drawer,
                  let chars = event.charactersIgnoringModifiers,
                  let digit = Int(chars), (1...9).contains(digit),
                  items.indices.contains(digit - 1) else { return false }

            let needsCommand = context == .drawer
            guard event.modifierFlags.contains(.command) == needsCommand else { return false }

            model.index = digit - 1
            commit(plainOnly: event.modifierFlags.contains(.shift))
            return true
        }
    }

    // MARK: - Focus tracking

    private func trackFrontmostApp() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.lastActiveApp = app }
        }
    }
}

// MARK: - SwiftUI containers

/// Bridges the AppKit-owned `SelectionModel` into the SwiftUI views' `@Binding`.
private struct HistoryContainer: View {
    @ObservedObject var selection: SelectionModel
    let onPaste: (ClipboardItem, Bool) -> Void
    let onPurge: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HistoryView(selection: $selection.index,
                    onPaste: onPaste,
                    onPurge: onPurge,
                    onQuit: onQuit)
    }
}

private struct DrawerContainer: View {
    @ObservedObject var selection: SelectionModel
    let onPaste: (ClipboardItem, Bool) -> Void
    let onPurge: () -> Void
    let onClose: () -> Void

    var body: some View {
        CardDrawerView(selection: $selection.index,
                       onPaste: onPaste,
                       onPurge: onPurge,
                       onClose: onClose)
    }
}

private struct SwitcherContainer: View {
    @ObservedObject var selection: SelectionModel
    let onPaste: (ClipboardItem) -> Void
    let onCancel: () -> Void

    var body: some View {
        QuickSwitcherView(selection: $selection.index,
                          onPaste: onPaste,
                          onCancel: onCancel)
    }
}
