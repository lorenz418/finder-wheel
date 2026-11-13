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
    private var escapeModRef: EventHotKeyRef?
    private var polledDown = false
    private var upTicks = 0
    private var pollTimer: Timer?
    private var handlerRef: EventHandlerRef?
    private var activationObserver: NSObjectProtocol?
    private(set) var isHeld = false

    private static let signature: OSType = 0x4657_484C // "FWHL"
    private static let mainID: UInt32 = 1
    private static let escapeID: UInt32 = 2

    init(combo: HotkeyCombo) {
        self.combo = combo
    }

    deinit {
        pollTimer?.invalidate()
        unregister(&mainRef)
        unregister(&escapeRef)
        unregister(&escapeModRef)
        if let handlerRef { RemoveEventHandler(handlerRef) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
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
        if enabled {
            if escapeRef == nil {
                escapeRef = register(keyCode: UInt32(kVK_Escape), modifiers: 0, id: Self.escapeID)
            }
            // Carbon matches the exact modifier set, so Esc is also needed with the hotkey's modifiers held.
            if escapeModRef == nil, combo.modifiers != 0 {
                escapeModRef = register(keyCode: UInt32(kVK_Escape), modifiers: combo.modifiers, id: Self.escapeID)
            }
        } else {
            unregister(&escapeRef)
            unregister(&escapeModRef)
        }
    }

    /// Fires `onRelease` if the hotkey is no longer physically held. Runs on its own timer
    /// while the hotkey is held, as a safety net for a missed key-up event.
    func pollRelease() {
        guard isHeld else { return }
        let keyDown = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(combo.keyCode))
        if keyDown { polledDown = true }
        // The key reading may be unreliable without Input Monitoring, so it only counts once
        // it has been seen down. Modifier state needs no permission.
        let released = !modifiersHeld || (polledDown && !keyDown)
        if released {
            upTicks += 1
            if upTicks >= 3 { handle(id: Self.mainID, pressed: false) }
        } else {
            upTicks = 0
        }
    }

    private var modifiersHeld: Bool {
        var required: NSEvent.ModifierFlags = []
        if combo.modifiers & UInt32(optionKey) != 0 { required.insert(.option) }
        if combo.modifiers & UInt32(controlKey) != 0 { required.insert(.control) }
        if combo.modifiers & UInt32(cmdKey) != 0 { required.insert(.command) }
        if combo.modifiers & UInt32(shiftKey) != 0 { required.insert(.shift) }
        return NSEvent.modifierFlags.isSuperset(of: required)
    }

    private func startPolling() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.pollRelease() }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
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
            polledDown = false
            upTicks = 0
            startPolling()
            onPress?()
        case (Self.mainID, false):
            guard isHeld else { return }
            isHeld = false
            pollTimer?.invalidate()
            pollTimer = nil
            onRelease?()
            updateRegistration()
        case (Self.escapeID, true):
            onEscape?()
        default:
            break
        }
    }
}
