import SwiftUI
import FinderWheelCore

@main
struct FinderWheelApp: App {
    private static let reader = FinderSelectionReader()

    private static let trigger: HotkeyTrigger = {
        let t = HotkeyTrigger(combo: .optionSpace)
        t.onPress = {
            do {
                let urls = try reader.read()
                let kinds = urls.map { Classifier.kind(of: $0) }
                NSLog("FinderWheel: press, \(urls.count) items, classification \(Classifier.classify(kinds).rawValue)")
            } catch {
                NSLog("FinderWheel: selection error \(error)")
            }
            t.setEscapeEnabled(true)
        }
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
