import AppKit
import Carbon.HIToolbox
import FinderWheelCore

/// Global hold-to-show hotkey, active only while Finder is frontmost.
final class HotkeyTrigger {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onEscape: (() -> Void)?

    private var combo: HotkeyCombo
    private var mainRef: EventHotKeyRef?
    private var escapeRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var activationObserver: NSObjectProtocol?
    private(set) var isHeld = false

    private static let signature: OSType = 0x4657_484C // "FWHL"
    private static let mainID: UInt32 = 1
    private static let escapeID: UInt32 = 2

    init(combo: HotkeyCombo) {
        self.combo = combo
    }

    func start() {
        installHandler()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateRegistration() }
        updateRegistration()
    }

    func setCombo(_ newCombo: HotkeyCombo) {
        guard newCombo != combo else { return }
        unregister(&mainRef)
        combo = newCombo
        updateRegistration()
    }

    func setEscapeEnabled(_ enabled: Bool) {
        if enabled, escapeRef == nil {
            escapeRef = register(keyCode: UInt32(kVK_Escape), modifiers: 0, id: Self.escapeID)
        } else if !enabled {
            unregister(&escapeRef)
        }
    }

    /// Fires `onRelease` if the hotkey's key is no longer physically down.
    func pollRelease() {
        guard isHeld else { return }
        if !CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(combo.keyCode)) {
            handle(id: Self.mainID, pressed: false)
        }
    }

    private var finderIsFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
    }

    private func updateRegistration() {
        if isHeld { return }
        if finderIsFrontmost {
            if mainRef == nil { mainRef = register(keyCode: combo.keyCode, modifiers: combo.modifiers, id: Self.mainID) }
        } else {
            unregister(&mainRef)
        }
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        if status != noErr { NSLog("FinderWheel: RegisterEventHotKey failed with status \(status)") }
        return ref
    }

    private func unregister(_ ref: inout EventHotKeyRef?) {
        if let existing = ref { UnregisterEventHotKey(existing) }
        ref = nil
    }

    private func installHandler() {
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let trigger = Unmanaged<HotkeyTrigger>.fromOpaque(userData).takeUnretainedValue()
            trigger.handle(id: hotKeyID.id, pressed: GetEventKind(event) == UInt32(kEventHotKeyPressed))
            return noErr
        }
        InstallEventHandler(GetEventDispatcherTarget(), callback, specs.count, &specs,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    private func handle(id: UInt32, pressed: Bool) {
        switch (id, pressed) {
        case (Self.mainID, true):
            guard !isHeld else { return }
            isHeld = true
            onPress?()
        case (Self.mainID, false):
            guard isHeld else { return }
            isHeld = false
            onRelease?()
            updateRegistration()
        case (Self.escapeID, true):
            onEscape?()
        default:
            break
        }
    }
}
