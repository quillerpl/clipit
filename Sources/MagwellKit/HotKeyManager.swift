import AppKit
import Carbon.HIToolbox

/// Carbon `RegisterEventHotKey` rather than a `CGEventTap`, on purpose: hotkey registration
/// needs no Accessibility permission, so the menu bar and switcher work the moment you launch.
/// Only the synthesized paste itself requires the permission.
@MainActor
final class HotKeyManager {

    static let shared = HotKeyManager()

    struct Modifiers {
        static let command = UInt32(cmdKey)
        static let shift   = UInt32(shiftKey)
        static let option  = UInt32(optionKey)
        static let control = UInt32(controlKey)
    }

    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var installed = false

    private init() {}

    func start() {
        guard !installed else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), clipStackHotKeyHandler, 1, &spec, nil, nil)
        installed = true
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> Bool {
        start()
        let id = nextID
        nextID += 1

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_5053), id: id) // 'CLPS'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("Magwell: failed to register hotkey \(keyCode)/\(modifiers) — OSStatus \(status)")
            return false
        }
        actions[id] = action
        refs[id] = ref
        return true
    }

    func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        actions.removeAll()
    }

    fileprivate func fire(id: UInt32) {
        actions[id]?()
    }
}

/// Carbon needs a plain C function pointer, so this lives at file scope.
private func clipStackHotKeyHandler(_ callRef: EventHandlerCallRef?,
                                    _ event: EventRef?,
                                    _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)
    guard status == noErr else { return status }

    let id = hotKeyID.id
    DispatchQueue.main.async {
        MainActor.assumeIsolated { HotKeyManager.shared.fire(id: id) }
    }
    return noErr
}
