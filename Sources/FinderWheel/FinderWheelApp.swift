import SwiftUI

@main
struct FinderWheelApp: App {
    var body: some Scene {
        MenuBarExtra("Finder Wheel", systemImage: "circle.dashed") {
            Button("Quit Finder Wheel") { NSApplication.shared.terminate(nil) }
        }
    }
}
