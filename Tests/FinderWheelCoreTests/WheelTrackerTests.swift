import Testing
import CoreGraphics
import Foundation
@testable import FinderWheelCore

@Suite struct WheelTrackerTests {
    /// Offset for an angle in degrees clockwise from up, at a radius.
    private func point(_ degrees: Double, _ radius: Double) -> (CGFloat, CGFloat) {
        let r = degrees * .pi / 180
        return (CGFloat(sin(r) * radius), CGFloat(cos(r) * radius))
    }
    private func tracker(_ counts: [Slot: Int]) -> WheelTracker { WheelTracker(optionCounts: counts) }
    private func hit(_ t: inout WheelTracker, _ degrees: Double, _ radius: Double) -> WheelHit {
        let (dx, dy) = point(degrees, radius)
        t.update(dx: dx, dy: dy)
        return t.hit
    }

    @Test func deadZoneIsNoHit() {
        var t = tracker([.up: 1])
        #expect(hit(&t, 0, 20) == .none)
    }

    @Test func eachDirectionMapsToItsSlot() {
        var t = tracker(Dictionary(uniqueKeysWithValues: Slot.allCases.map { ($0, 1) }))
        #expect(hit(&t, 0, 90) == .entry(.up))
        #expect(hit(&t, 60, 90) == .entry(.upperRight))
        #expect(hit(&t, 120, 90) == .entry(.lowerRight))
        #expect(hit(&t, 180, 90) == .entry(.down))
        #expect(hit(&t, 240, 90) == .entry(.lowerLeft))
        #expect(hit(&t, 300, 90) == .entry(.upperLeft))
    }

    @Test func wedgeBoundariesAreAtThirtyDegrees() {
        var t = tracker([.up: 1, .upperRight: 1, .upperLeft: 1])
        #expect(hit(&t, 29, 90) == .entry(.up))
        #expect(hit(&t, 31, 90) == .entry(.upperRight))
        #expect(hit(&t, 331, 90) == .entry(.up))
        #expect(hit(&t, 329, 90) == .entry(.upperLeft))
    }

    @Test func emptySlotIsNoHit() {
        var t = tracker([.up: 1])
        #expect(hit(&t, 180, 90) == .none)
        #expect(hit(&t, 180, 300) == .none)
    }

    @Test func singleOptionEntryStaysEntryBeyondTheRing() {
        var t = tracker([.up: 1])
        #expect(hit(&t, 0, 90) == .entry(.up))
        #expect(hit(&t, 0, 400) == .entry(.up))
    }

    @Test func outerRingPicksOptionByAngle() {
        // 4 options around 60°: centres at 30°, 60°, 90°, 120°.
        var t = tracker([.upperRight: 4])
        #expect(hit(&t, 60, 90) == .entry(.upperRight))
        // Leaving the ring straight through the wedge locks the slot and hits the option straight ahead.
        #expect(hit(&t, 60, 180) == .option(.upperRight, 1))
        #expect(hit(&t, 30, 180) == .option(.upperRight, 0))
        #expect(hit(&t, 90, 180) == .option(.upperRight, 2))
        #expect(hit(&t, 120, 180) == .option(.upperRight, 3))
    }

    @Test func twoOptionsFirstIsStraightAhead() {
        var t = tracker([.upperRight: 2])
        #expect(hit(&t, 60, 180) == .option(.upperRight, 0))
        #expect(hit(&t, 90, 180) == .option(.upperRight, 1))
        #expect(hit(&t, 20, 180) == .option(.upperRight, 0))
    }

    @Test func outerRingClampsAndStaysLocked() {
        var t = tracker([.upperRight: 3, .lowerRight: 3])
        _ = hit(&t, 60, 90)
        _ = hit(&t, 60, 180)
        // Far past the fan, still locked to upperRight and clamped to the last option.
        #expect(hit(&t, 150, 180) == .option(.upperRight, 2))
        #expect(hit(&t, 350, 180) == .option(.upperRight, 0))
    }

    @Test func returningInsideUnlocks() {
        var t = tracker([.upperRight: 3, .lowerRight: 3])
        _ = hit(&t, 60, 180)
        #expect(hit(&t, 120, 90) == .entry(.lowerRight))
        #expect(hit(&t, 120, 180) == .option(.lowerRight, 1))
    }

    @Test func threeOptionsCentreIsStraightAhead() {
        var t = tracker([.lowerRight: 3])
        #expect(hit(&t, 120, 180) == .option(.lowerRight, 1))
        #expect(hit(&t, 90, 180) == .option(.lowerRight, 0))
        #expect(hit(&t, 150, 180) == .option(.lowerRight, 2))
    }
}
