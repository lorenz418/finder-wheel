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
            // No GlassEffectContainer: it would melt a closing and an opening outer ring into one shape.
            // A ring of segments around a separate hub. The ring's seam lies under a divider.
            GlassSurface(shape: WedgeShape(centerDegrees: 30, spanDegrees: 360, innerRadius: m.deadZone,
                                           outerRadius: m.ringOuter, gap: 0))
            GlassSurface(shape: Circle())
                .frame(width: (m.deadZone - 7) * 2, height: (m.deadZone - 7) * 2)
            optionRing(.glass)
            ForEach(Slot.allCases, id: \.self) { slot in
                WedgeShape(centerDegrees: Double(slot.rawValue) * 60, spanDegrees: 60,
                           innerRadius: m.deadZone + 4, outerRadius: m.ringOuter - 4, gap: 8, cornerRadius: 12)
                    .fill(Color.accentColor.gradient)
                    .opacity(isEntryHit(slot) ? (isPassedThrough(slot) ? 0.25 : 1) : 0)
                // A direction without an action is dimmed.
                if model.entry(at: slot) == nil {
                    WedgeShape(centerDegrees: Double(slot.rawValue) * 60, spanDegrees: 60,
                               innerRadius: m.deadZone, outerRadius: m.ringOuter, gap: 0)
                        .fill(.black.opacity(0.2))
                }
            }
            Dividers(angles: (0..<6).map { Double($0) * 60 + 30 },
                     innerRadius: m.deadZone + 1, outerRadius: m.ringOuter - 1)
            ForEach(model.entries, id: \.slot) { entry in
                wedgeLabel(entry)
                    .position(.polar(center: center, degrees: Double(entry.slot.rawValue) * 60, radius: (m.deadZone + m.ringOuter) / 2))
            }
            Text(model.isUnsupported ? "No actions for\nthis selection" : model.summary)
                .font(.system(size: 10.5, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.85)
                .frame(width: (m.deadZone - 7) * 2 - 8)
            // Above every piece of glass, so a closing ring never covers an opening one's labels.
            optionRing(.content)
        }
        .frame(width: Self.side, height: Self.side)
        // Smoked glass with light labels, whatever the system appearance: it reads over
        // white Finder windows and dark ones alike.
        .environment(\.colorScheme, .dark)
        .scaleEffect(model.isVisible || reduceMotion ? 1 : 0.92)
        .opacity(model.isVisible ? 1 : 0)
        .animation(model.isVisible ? .spring(duration: 0.22, bounce: 0.18) : .easeOut(duration: 0.12), value: model.isVisible)
        .animation(.easeOut(duration: 0.1), value: model.hit)
    }


    /// One outer ring per entry with options, always present and open only for the expanded slot,
    /// so each ring opens out of and closes back into its own wedge.
    private func optionRing(_ layer: OptionRing.Layer) -> some View {
        ForEach(model.entries.filter { $0.options.count > 1 }, id: \.slot) { entry in
            let isOpen = model.expandedSlot == entry.slot
            OptionRing(layer: layer, entry: entry, hitIndex: hitOption(in: entry.slot), metrics: model.metrics, side: Self.side,
                       progress: isOpen ? 1 : 0, reduceMotion: reduceMotion)
                // Closer to the ring than the `hit` animation, so it wins. Closing is quick and
                // without a spring tail, which would leave a sliver of glass visible.
                .animation(isOpen ? .spring(duration: 0.26, bounce: 0.12) : .easeOut(duration: 0.14), value: isOpen)
        }
    }

    private func isEntryHit(_ slot: Slot) -> Bool {
        switch model.hit {
        case .entry(let s): return s == slot
        case .option(let s, _): return s == slot
        case .none: return false
        }
    }

    /// The cursor went through this wedge to one of its outer options.
    private func isPassedThrough(_ slot: Slot) -> Bool {
        hitOption(in: slot) != nil
    }

    private func hitOption(in slot: Slot) -> Int? {
        if case .option(slot, let index) = model.hit { return index }
        return nil
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
        .foregroundStyle(active && !isPassedThrough(entry.slot) ? Color.white : Color.primary)
        .scaleEffect(active && !reduceMotion ? 1.06 : 1)
    }
}

/// The outer ring for one entry. It grows out of the entry's wedge as `progress`
/// goes from 0 to 1 and folds back into it on the way back to 0.
private struct OptionRing: View, Animatable {
    /// Labels and highlight are drawn above all glass, so the ring is drawn in two layers.
    enum Layer { case glass, content }

    let layer: Layer
    let entry: WheelEntry
    let hitIndex: Int?
    let metrics: WheelMetrics
    let side: CGFloat
    var progress: Double
    /// Fades in place instead of growing.
    let reduceMotion: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// Geometry follows `progress` unless motion is reduced, in which case only opacity does.
    private var shape: Double { reduceMotion ? 1 : progress }

    private var count: Int { entry.options.count }
    private var inner: CGFloat { metrics.ringOuter + 6 }
    private var outer: CGFloat { inner + (metrics.outerRingOuter - inner) * CGFloat(shape) }
    /// Starts as wide as the wedge, centred on it, and opens to the options' full arc.
    private var span: Double { 60 + (Double(count) * metrics.optionArc - 60) * shape }
    private var optionSpan: Double { span / Double(count) }
    private var start: Double {
        let slotAngle = Double(entry.slot.rawValue) * 60
        let openCenter = (metrics.optionAngle(slot: entry.slot, index: 0, count: count)
                          + metrics.optionAngle(slot: entry.slot, index: count - 1, count: count)) / 2
        return slotAngle + (openCenter - slotAngle) * shape - span / 2
    }
    private func angle(_ index: Int) -> Double { start + (Double(index) + 0.5) * optionSpan }

    var body: some View {
        ZStack {
            // Glass ignores opacity, so the ring is dropped once it has shrunk to a sliver
            // (or, without motion, once it has mostly faded).
            if reduceMotion ? progress > 0.5 : shape > 0.06 {
                layerContent
            }
        }
        .frame(width: side, height: side)
        .opacity(min(1, progress * 2))
    }

    @ViewBuilder
    private var layerContent: some View {
        switch layer {
        case .glass:
            let band = WedgeShape(centerDegrees: start + span / 2, spanDegrees: span,
                                  innerRadius: inner, outerRadius: outer, gap: 0, cornerRadius: 18)
            GlassSurface(shape: band)
        case .content:
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        let center = CGPoint(x: side / 2, y: side / 2)
        // While the ring is still a sliver the inset highlight would turn inside out.
        if let hitIndex, outer - inner > 12 {
            WedgeShape(centerDegrees: angle(hitIndex), spanDegrees: optionSpan,
                       innerRadius: inner + 5, outerRadius: outer - 5, gap: 10, cornerRadius: 12)
                .fill(Color.accentColor.gradient)
        }
        Dividers(angles: (1..<count).map { start + Double($0) * optionSpan },
                 innerRadius: inner + 1, outerRadius: outer - 1)
        ForEach(Array(entry.options.enumerated()), id: \.offset) { index, option in
            Text(option.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(index == hitIndex ? Color.white : Color.primary)
                .position(.polar(center: center, degrees: angle(index), radius: (inner + outer) / 2))
                .opacity(max(0, min(1, progress * 2 - 0.6)))
        }
    }
}

/// A pane of smoked glass: dark and see-through, with a bright rim and a shadow around it.
private struct GlassSurface<S: Shape>: View {
    let shape: S

    var body: some View {
        ZStack {
            // The shadow is cut out under the pane, where it would show through and dull the glass.
            shape
                .fill(.black)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .mask {
                    Rectangle()
                        .padding(-60)
                        .overlay(shape.blendMode(.destinationOut))
                        .compositingGroup()
                }
            shape
                .fill(.clear)
                .glassEffect(.clear.tint(.black.opacity(0.45)), in: shape)
            shape
                .stroke(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08), .white.opacity(0.3)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
    }
}

/// Hairlines between wedges, at `angles` degrees clockwise from the top.
struct Dividers: View {
    let angles: [Double]
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            Path { path in
                guard outerRadius > innerRadius else { return }
                for angle in angles {
                    path.move(to: .polar(center: center, degrees: angle, radius: innerRadius))
                    path.addLine(to: .polar(center: center, degrees: angle, radius: outerRadius))
                }
            }
            .stroke(.white.opacity(0.16), lineWidth: 1)
        }
    }
}
