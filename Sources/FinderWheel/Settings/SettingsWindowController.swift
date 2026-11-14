import AppKit
import SwiftUI
import FinderWheelCore

/// A standard Mac settings window with toolbar tabs.
@MainActor
final class SettingsWindowController {
    enum Tab: Int { case general, wheel, services }

    /// Every page has this width, so the window only changes height between tabs.
    static let width: CGFloat = 720

    private var window: NSWindow?
    private var tabs: NSTabViewController?

    /// Opens the window, on `tab` if given and otherwise on the tab it was last on.
    func show(settings: AppSettings, lastUsed: LastUsedStore, tab: Tab? = nil) {
        if window == nil {
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            let pages: [(String, String, AnyView)] = [
                ("General", "gearshape", AnyView(GeneralSettingsView(settings: settings))),
                ("Wheel", "chart.pie", AnyView(WheelSettingsView(settings: settings, lastUsed: lastUsed))),
                ("Services", "network", AnyView(ServicesSettingsView(settings: settings))),
            ]
            for (title, symbol, view) in pages {
                let host = NSHostingController(rootView: view)
                host.sizingOptions = .preferredContentSize
                // The tab controller shows the selected page's title as the window title.
                host.title = title
                let item = NSTabViewItem(viewController: host)
                item.label = title
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
                tabs.addTabViewItem(item)
            }
            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
            self.tabs = tabs
        }
        if let tab { tabs?.selectedTabViewItemIndex = tab.rawValue }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
