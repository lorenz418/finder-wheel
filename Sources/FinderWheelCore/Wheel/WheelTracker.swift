import CoreGraphics
import Foundation

public struct WheelMetrics: Sendable {
    /// Radius below which nothing is selected.
    public var deadZone: CGFloat = 44
    /// Outer edge of the main ring; beyond it the outer ring begins.
    public var ringOuter: CGFloat = 140
    /// Outer edge of the outer ring, for drawing only. Hit-testing has no outer limit.
    public var outerRingOuter: CGFloat = 206
    /// Angular size of one outer-ring option, in degrees.
    public var optionArc: Double = 30

    public init() {}

    /// Centre angle in degrees (clockwise from up) of option `index` out of `count` for a slot.
    public func optionAngle(slot: Slot, index: Int, count: Int) -> Double {
        Double(slot.rawValue) * 60 + Double(index - (count - 1) / 2) * optionArc
    }
}

public enum WheelHit: Equatable, Sendable {
    case none
    case entry(Slot)
    case option(Slot, Int)
}

/// Pure geometry: cursor offset in, hit out. Holds the one piece of state the wheel
/// needs, which slot the cursor left the ring through.
public struct WheelTracker: Sendable {
    public let metrics: WheelMetrics
    private let optionCounts: [Slot: Int]
    private var lockedSlot: Slot?
    public private(set) var hit: WheelHit = .none

    /// `optionCounts` has one key per slot that has an entry; the value is its number of options.
    public init(optionCounts: [Slot: Int], metrics: WheelMetrics = WheelMetrics()) {
        self.optionCounts = optionCounts
        self.metrics = metrics
    }

    /// `dx` positive is right, `dy` positive is up.
    public mutating func update(dx: CGFloat, dy: CGFloat) {
        let radius = hypot(dx, dy)
        guard radius >= metrics.deadZone else {
            lockedSlot = nil
            hit = .none
            return
        }
        var degrees = Double(atan2(dx, dy)) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        let angleSlot = Slot(rawValue: Int((degrees + 30) / 60) % 6)!

        if radius < metrics.ringOuter {
            lockedSlot = nil
            hit = optionCounts[angleSlot] == nil ? .none : .entry(angleSlot)
            return
        }

        let slot = lockedSlot ?? angleSlot
        lockedSlot = slot
        guard let count = optionCounts[slot] else {
            hit = .none
            return
        }
        guard count > 1 else {
            hit = .entry(slot)
            return
        }
        var delta = degrees - Double(slot.rawValue) * 60
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        let raw = Int((delta / metrics.optionArc + 0.5).rounded(.down)) + (count - 1) / 2
        hit = .option(slot, min(max(raw, 0), count - 1))
    }
}
