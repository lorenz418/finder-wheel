import AppKit
import SwiftUI

/// Floating strip for ordering files before Combine. Key-capable, non-activating.
@MainActor
final class ReorderPanelController {
    private var panel: KeyPanel?
    private var completion: (([URL]?) -> Void)?
    private var model: ReorderModel?

    var isShowing: Bool { panel != nil }

    /// Shows the strip near `point`. `completion` receives the ordered URLs, or nil if cancelled.
    func show(urls: [URL], near point: NSPoint, completion: @escaping ([URL]?) -> Void) {
        close(result: nil)
        let model = ReorderModel(urls: urls)
        self.model = model
        self.completion = completion

        let size = NSSize(width: ReorderView.width(for: urls.count), height: ReorderView.height)
        let panel = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.contentView = NSHostingView(rootView: ReorderView(
            model: model,
            confirm: { [weak self] in self?.close(result: model.items.map(\.url)) },
            cancel: { [weak self] in self?.close(result: nil) }))

        var origin = NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        if let visible = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame ?? NSScreen.main?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    private func close(result: [URL]?) {
        guard let panel else { return }
        panel.orderOut(nil)
        self.panel = nil
        self.model = nil
        let completion = self.completion
        self.completion = nil
        completion?(result)
    }
}

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
