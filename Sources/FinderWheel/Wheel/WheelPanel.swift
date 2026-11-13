import AppKit
import SwiftUI

/// Transparent, click-through, never-key panel that hosts the wheel.
final class WheelPanel: NSPanel {
    init(model: WheelModel) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: WheelView.side, height: WheelView.side),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: WheelView(model: model))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows the panel with its centre at `point` (screen coordinates).
    func show(centeredAt point: NSPoint) {
        setFrameOrigin(NSPoint(x: point.x - WheelView.side / 2, y: point.y - WheelView.side / 2))
        orderFrontRegardless()
    }
}
