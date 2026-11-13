import SwiftUI
import FinderWheelCore

/// Everything the wheel view draws. Written by `WheelController`.
@MainActor
@Observable
final class WheelModel {
    var entries: [WheelEntry] = []
    /// Option a plain release would run, per slot. Only shown for entries with several options.
    var releaseOptionTitles: [Slot: String] = [:]
    var summary = ""
    var isUnsupported = false
    var hit: WheelHit = .none
    var metrics = WheelMetrics()
    /// Flipped to true right after the panel is shown, to drive the appear animation.
    var isVisible = false

    func entry(at slot: Slot) -> WheelEntry? { entries.first { $0.slot == slot } }

    /// The slot whose outer ring should be visible, if any.
    var expandedSlot: Slot? {
        let slot: Slot?
        switch hit {
        case .none: slot = nil
        case .entry(let s): slot = s
        case .option(let s, _): slot = s
        }
        guard let slot, let entry = entry(at: slot), entry.options.count > 1 else { return nil }
        return slot
    }
}
