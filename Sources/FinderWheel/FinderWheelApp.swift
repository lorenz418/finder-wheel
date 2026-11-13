import SwiftUI
import FinderWheelCore

@main
struct FinderWheelApp: App {
    private static let trigger: HotkeyTrigger = {
        let t = HotkeyTrigger(combo: .optionSpace)
        t.onPress = { NSLog("FinderWheel: press"); t.setEscapeEnabled(true) }
        t.onRelease = { NSLog("FinderWheel: release"); t.setEscapeEnabled(false) }
        t.onEscape = { NSLog("FinderWheel: escape") }
        return t
    }()

    init() { Self.trigger.start() }

    var body: some Scene {
        MenuBarExtra("Finder Wheel", systemImage: "circle.dashed") {
            Button("Quit Finder Wheel") { NSApplication.shared.terminate(nil) }
        }
    }
}
