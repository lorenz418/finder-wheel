import SwiftUI
import FinderWheelCore

struct WheelView: View {
    let model: WheelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The panel is this size; the wheel is centred in it. Follows the outer ring's radius
    /// (460 with the default metrics), so tuning `WheelMetrics` never clips the wheel.
    static let side: CGFloat = WheelMetrics().outerRingOuter * 2 + 48

    var body: some View {
        let m = model.metrics
        let center = CGPoint(x: Self.side / 2, y: Self.side / 2)
        ZStack {
            GlassEffectContainer {
                ZStack {
                    ForEach(Slot.allCases, id: \.self) { slot in
                        wedge(slot, metrics: m)
                    }
                    if let slot = model.expandedSlot, let entry = model.entry(at: slot) {
                        ForEach(Array(entry.options.enumerated()), id: \.offset) { index, _ in
                            optionWedge(slot: slot, index: index, count: entry.options.count, metrics: m)
                        }
                    }
                    Circle()
                        .fill(.clear)
                        .frame(width: (m.deadZone - 6) * 2, height: (m.deadZone - 6) * 2)
                        .glassEffect(.regular, in: Circle())
                }
            }
            ForEach(model.entries, id: \.slot) { entry in
                wedgeLabel(entry)
                    .position(.polar(center: center, degrees: Double(entry.slot.rawValue) * 60, radius: (m.deadZone + m.ringOuter) / 2))
            }
            if let slot = model.expandedSlot, let entry = model.entry(at: slot) {
                ForEach(Array(entry.options.enumerated()), id: \.offset) { index, option in
                    Text(option.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isOptionHit(slot, index) ? Color.white : Color.primary)
                        .position(.polar(center: center,
                                         degrees: m.optionAngle(slot: slot, index: index, count: entry.options.count),
                                         radius: (m.ringOuter + m.outerRingOuter) / 2))
                        .transition(.opacity)
                }
            }
            Text(model.isUnsupported ? "No actions for\nthis selection" : model.summary)
                .font(.system(size: 11, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(width: m.deadZone * 2 - 20)
        }
        .frame(width: Self.side, height: Self.side)
        .scaleEffect(model.isVisible || reduceMotion ? 1 : 0.9)
        .opacity(model.isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: model.isVisible)
        .animation(.easeOut(duration: 0.1), value: model.hit)
        .animation(.spring(duration: 0.18, bounce: 0.15), value: model.expandedSlot)
    }

    private func isEntryHit(_ slot: Slot) -> Bool {
        switch model.hit {
        case .entry(let s): return s == slot
        case .option(let s, _): return s == slot
        case .none: return false
        }
    }

    private func isOptionHit(_ slot: Slot, _ index: Int) -> Bool {
        model.hit == .option(slot, index)
    }

    private func wedge(_ slot: Slot, metrics m: WheelMetrics) -> some View {
        let hasEntry = model.entry(at: slot) != nil
        let active = isEntryHit(slot)
        return Color.clear
            .frame(width: Self.side, height: Self.side)
            .glassEffect(active ? .regular.tint(.accentColor) : .regular,
                         in: WedgeShape(centerDegrees: Double(slot.rawValue) * 60, spanDegrees: 60,
                                        innerRadius: m.deadZone, outerRadius: m.ringOuter))
            .opacity(hasEntry ? 1 : 0.35)
    }

    private func optionWedge(slot: Slot, index: Int, count: Int, metrics m: WheelMetrics) -> some View {
        Color.clear
            .frame(width: Self.side, height: Self.side)
            .glassEffect(isOptionHit(slot, index) ? .regular.tint(.accentColor) : .regular,
                         in: WedgeShape(centerDegrees: m.optionAngle(slot: slot, index: index, count: count),
                                        spanDegrees: m.optionArc, innerRadius: m.ringOuter + 4, outerRadius: m.outerRingOuter))
            .transition(reduceMotion ? .opacity : .scale(scale: 0.86).combined(with: .opacity))
    }

    private func wedgeLabel(_ entry: WheelEntry) -> some View {
        let active = isEntryHit(entry.slot)
        return VStack(spacing: 3) {
            Image(systemName: entry.symbol)
                .font(.system(size: 19, weight: .medium))
            Text(entry.title)
                .font(.system(size: 12, weight: .semibold))
            if let hint = model.releaseOptionTitles[entry.slot] {
                Text(hint)
                    .font(.system(size: 9.5, weight: .medium))
                    .opacity(0.7)
            }
        }
        .foregroundStyle(active ? Color.white : Color.primary)
        .scaleEffect(active && !reduceMotion ? 1.06 : 1)
    }
}
