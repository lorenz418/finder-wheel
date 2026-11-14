import SwiftUI
import UniformTypeIdentifiers
import FinderWheelCore

private extension UTType {
    /// Private drag types, so nothing else dragged over the editor can rearrange the wheel.
    static let wheelSlot = UTType(exportedAs: "com.lorenz.finderwheel.slot")
    static let wheelOption = UTType(exportedAs: "com.lorenz.finderwheel.option")
}

private func dragItem(_ type: UTType, _ value: String) -> NSItemProvider {
    let provider = NSItemProvider()
    provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { completion in
        completion(Data(value.utf8), nil)
        return nil
    }
    return provider
}

/// Lets the user arrange the wheel for each file type: pick a direction on the preview,
/// then choose its action and outer-ring options in the inspector.
struct WheelSettingsView: View {
    @Bindable var settings: AppSettings
    let lastUsed: LastUsedStore
    @State private var type: WheelFileType = .pdf
    @State private var selected: Slot = .up

    var body: some View {
        let config = settings.wheel[type]
        VStack(spacing: 0) {
            Picker("File type", selection: $type) {
                ForEach(WheelFileType.allCases, id: \.self) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)
            .padding(.top, 18)
            .padding(.bottom, 16)

            HStack(alignment: .top, spacing: 0) {
                ZStack(alignment: .bottom) {
                    WheelDiagram(type: type, config: config, selected: $selected) { from, to in
                        edit { $0.swap(from, to) }
                        selected = to
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text("Click a direction to edit it. Drag one onto another to swap them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 14)
                }
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
                .padding(.leading, 20)

                SlotInspector(settings: settings, type: type, slot: selected, edit: edit)
                    .frame(width: 348)
            }
            .frame(height: 436)

            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "info.circle")
                Text(mixedNote)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 16)
                Button("Reset \(type.title) Wheel") { edit { $0 = .standard(for: type) } }
                    .disabled(config == .standard(for: type))
                    .foregroundStyle(.primary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: SettingsWindowController.width)
    }

    /// The one way the wheel is changed, so a remembered choice never outlives its setting.
    private func edit(_ change: (inout WheelConfiguration) -> Void) {
        let old = settings.wheel[type]
        var new = old
        change(&new)
        guard new != old else { return }
        settings.wheel[type] = new
        lastUsed.forgetChanges(from: old, to: new, type: type)
    }

    private var mixedNote: String {
        switch type {
        case .pdf, .image: return "Selections that mix PDFs and images show what both wheels share, placed as on the PDF wheel."
        case .video, .audio: return "Selections that mix video and audio show what both wheels share, placed as on the Video wheel."
        }
    }
}

// MARK: - Diagram

/// A scaled-down copy of the real wheel that can be clicked and rearranged.
/// The selected direction's outer ring is shown around it.
private struct WheelDiagram: View {
    let type: WheelFileType
    let config: WheelConfiguration
    @Binding var selected: Slot
    let onSwap: (_ from: Slot, _ to: Slot) -> Void

    @State private var dragged: Slot?
    @State private var dropTarget: Slot?
    @State private var hovered: Slot?

    private static let scale: CGFloat = 0.8
    private let metrics = WheelMetrics()
    private var hub: CGFloat { metrics.deadZone * Self.scale }
    private var ring: CGFloat { metrics.ringOuter * Self.scale }
    private var optionsInner: CGFloat { ring + 5 }
    private var optionsOuter: CGFloat { metrics.outerRingOuter * Self.scale }
    private var side: CGFloat { optionsOuter * 2 + 24 }

    var body: some View {
        ZStack {
            pane(Circle())
                .frame(width: ring * 2, height: ring * 2)
            Circle()
                .stroke(.white.opacity(0.16), lineWidth: 1)
                .frame(width: hub * 2, height: hub * 2)
            outerRing
            ForEach(Slot.allCases, id: \.self) { slot in
                wedge(slot)
            }
            Dividers(angles: (0..<6).map { Double($0) * 60 + 30 }, innerRadius: hub + 1, outerRadius: ring - 1)
                .allowsHitTesting(false)
            VStack(spacing: 2) {
                Image(systemName: type.symbol)
                    .font(.system(size: 13))
                Text(type.title)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.6))
            .allowsHitTesting(false)
        }
        .frame(width: side, height: side)
        .onContinuousHover { phase in
            if case .active(let point) = phase { hovered = slot(at: point) } else { hovered = nil }
        }
        .onDrop(of: [.wheelSlot], delegate: SlotDropDelegate(slotAt: slot(at:), dragged: $dragged, target: $dropTarget) { from, to in
            onSwap(from, to)
        })
        .animation(.easeOut(duration: 0.12), value: selected)
        .animation(.easeOut(duration: 0.1), value: hovered)
    }

    /// The real wheel's smoked glass, drawn opaque enough to read on the settings window.
    private func pane(_ shape: some Shape) -> some View {
        shape
            .fill(Color(white: 0.14).opacity(0.9))
            .shadow(color: .black.opacity(0.22), radius: 9, y: 4)
            .overlay {
                shape.stroke(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08), .white.opacity(0.25)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
    }

    private func wedge(_ slot: Slot) -> some View {
        let entry = config[slot]
        let isSelected = slot == selected
        let highlight = WedgeShape(centerDegrees: Double(slot.rawValue) * 60, spanDegrees: 60,
                                   innerRadius: hub + 3, outerRadius: ring - 3, gap: 6, cornerRadius: 10)
        let center = CGPoint(x: side / 2, y: side / 2)
        return ZStack {
            if isSelected {
                highlight.fill(Color.accentColor.gradient)
            } else if hovered == slot {
                highlight.fill(.white.opacity(0.1))
            }
            if dropTarget == slot, let dragged, dragged != slot {
                highlight.stroke(.white, lineWidth: 2)
            }
            label(entry)
                .foregroundStyle(.white.opacity(entry == nil && !isSelected ? 0.35 : 1))
                .position(.polar(center: center, degrees: Double(slot.rawValue) * 60, radius: (hub + ring) / 2 + 1))
        }
        .frame(width: side, height: side)
        .contentShape(WedgeShape(centerDegrees: Double(slot.rawValue) * 60, spanDegrees: 60,
                                 innerRadius: hub, outerRadius: ring, gap: 0))
        .onTapGesture { selected = slot }
        .onDrag {
            dragged = slot
            return dragItem(.wheelSlot, String(slot.rawValue))
        } preview: {
            label(entry)
                .foregroundStyle(.white)
                .padding(10)
                .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(slot.name): \(entry?.verb.title ?? "Empty")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selected = slot }
    }

    @ViewBuilder
    private func label(_ entry: SlotConfiguration?) -> some View {
        if let entry {
            VStack(spacing: 3) {
                Image(systemName: entry.verb.symbol)
                    .font(.system(size: 15, weight: .medium))
                Text(entry.verb.title)
                    .font(.system(size: 10, weight: .semibold))
            }
        } else {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
        }
    }

    /// The selected direction's outer ring, laid out as on the real wheel. The default option is marked.
    @ViewBuilder
    private var outerRing: some View {
        if let entry = config[selected], entry.optionIDs.count > 1 {
            let count = entry.optionIDs.count
            let titles = WheelCatalog.options(for: entry.verb, classification: type.classification)
            let center = CGPoint(x: side / 2, y: side / 2)
            let first = metrics.optionAngle(slot: selected, index: 0, count: count)
            let last = metrics.optionAngle(slot: selected, index: count - 1, count: count)
            ZStack {
                pane(WedgeShape(centerDegrees: (first + last) / 2, spanDegrees: Double(count) * metrics.optionArc,
                                innerRadius: optionsInner, outerRadius: optionsOuter, gap: 0, cornerRadius: 14))
                Dividers(angles: (1..<count).map { first + (Double($0) - 0.5) * metrics.optionArc },
                         innerRadius: optionsInner + 1, outerRadius: optionsOuter - 1)
                ForEach(Array(entry.optionIDs.enumerated()), id: \.element) { index, id in
                    let angle = metrics.optionAngle(slot: selected, index: index, count: count)
                    let isDefault = id == entry.defaultOptionID
                    if isDefault {
                        WedgeShape(centerDegrees: angle, spanDegrees: metrics.optionArc,
                                   innerRadius: optionsInner + 4, outerRadius: optionsOuter - 4, gap: 8, cornerRadius: 9)
                            .fill(Color.accentColor.opacity(0.55))
                    }
                    Text(titles.first { $0.id == id }?.title ?? id)
                        .font(.system(size: 9, weight: isDefault ? .bold : .medium))
                        .foregroundStyle(.white.opacity(isDefault ? 1 : 0.85))
                        .position(.polar(center: center, degrees: angle, radius: (optionsInner + optionsOuter) / 2))
                }
            }
            .frame(width: side, height: side)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    private func slot(at point: CGPoint) -> Slot? {
        let dx = point.x - side / 2
        let dy = side / 2 - point.y
        let radius = hypot(dx, dy)
        guard radius >= hub, radius <= ring else { return nil }
        return WheelMetrics.slot(atDegrees: Double(atan2(dx, dy)) * 180 / .pi)
    }
}

/// Moves the dragged option into the place of the row it is dragged over.
private struct OptionDropDelegate: DropDelegate {
    let target: String
    @Binding var dragged: String?
    let move: (_ from: String, _ to: String) -> Void

    func validateDrop(info: DropInfo) -> Bool { dragged != nil }

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target else { return }
        move(dragged, target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}

private struct SlotDropDelegate: DropDelegate {
    let slotAt: (CGPoint) -> Slot?
    @Binding var dragged: Slot?
    @Binding var target: Slot?
    let perform: (_ from: Slot, _ to: Slot) -> Void

    func validateDrop(info: DropInfo) -> Bool { dragged != nil }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        target = slotAt(info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { target = nil }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            target = nil
            dragged = nil
        }
        guard let from = dragged, let to = slotAt(info.location), from != to else { return false }
        perform(from, to)
        return true
    }
}

// MARK: - Inspector

private struct SlotInspector: View {
    let settings: AppSettings
    let type: WheelFileType
    let slot: Slot
    let edit: ((inout WheelConfiguration) -> Void) -> Void
    /// The outer-ring option being dragged to a new position.
    @State private var draggedOption: String?

    private var config: WheelConfiguration { settings.wheel[type] }
    private var entry: SlotConfiguration? { config[slot] }
    private var allOptions: [WheelOption] {
        entry.map { WheelCatalog.options(for: $0.verb, classification: type.classification) } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 12)
            if let entry {
                SettingsCard {
                    SettingsRow {
                        Text("Action")
                        Spacer()
                        Picker("Action", selection: Binding(
                            get: { Verb?.some(entry.verb) },
                            set: { verb in edit { $0.assign(verb, to: slot, type: type) } })) {
                            ForEach(WheelCatalog.verbs(for: type.classification), id: \.self) { verb in
                                Label(menuTitle(verb), systemImage: verb.symbol).tag(Verb?.some(verb))
                            }
                            Divider()
                            Text("No Action").tag(Verb?.none)
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                }
                SettingsFootnote(description(of: entry.verb))
                if allOptions.count > 1 {
                    optionSections(entry)
                }
            } else {
                SettingsCard {
                    let verbs = WheelCatalog.verbs(for: type.classification)
                    ForEach(verbs, id: \.self) { verb in
                        addRow(verb)
                        if verb != verbs.last { SettingsSeparator() }
                    }
                }
                SettingsFootnote("Nothing happens in this direction yet. Pick an action for it.")
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
        .padding(.trailing, 20)
    }

    /// The direction being edited, with an arrow pointing the way.
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up")
                .font(.system(size: 11, weight: .bold))
                .rotationEffect(.degrees(Double(slot.rawValue) * 60))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 6))
            Text(slot.name)
                .font(.headline)
        }
    }

    /// A row that puts `verb` in this, so far empty, direction.
    private func addRow(_ verb: Verb) -> some View {
        Button {
            edit { $0.assign(verb, to: slot, type: type) }
        } label: {
            SettingsRow {
                Image(systemName: verb.symbol)
                    .frame(width: 20)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verb.title)
                    if let other = config.slot(of: verb) {
                        Text("Moves here from \(other.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(description(of: verb))
    }

    @ViewBuilder
    private func optionSections(_ entry: SlotConfiguration) -> some View {
        let hidden = allOptions.map(\.id).filter { !entry.optionIDs.contains($0) }
        SettingsSectionTitle("Outer Ring")
            .padding(.top, 18)
        SettingsCard {
            // Rows reorder themselves while one is dragged over them.
            ForEach(entry.optionIDs, id: \.self) { id in
                optionRow(id, shown: true, entry: entry)
                    .onDrag {
                        draggedOption = id
                        return dragItem(.wheelOption, id)
                    }
                    .onDrop(of: [.wheelOption], delegate: OptionDropDelegate(target: id, dragged: $draggedOption) { from, to in
                        withAnimation(.snappy(duration: 0.2)) {
                            edit { $0.moveOption(from, onto: to, at: slot) }
                        }
                    })
                if id != entry.optionIDs.last || !hidden.isEmpty { SettingsSeparator() }
            }
            ForEach(hidden, id: \.self) { id in
                optionRow(id, shown: false, entry: entry)
                if id != hidden.last { SettingsSeparator() }
            }
        }
        SettingsFootnote("Slide past \(entry.verb.title) to pick one of these. Drag to reorder.")

        SettingsCard {
            SettingsRow {
                Text("On release, run")
                Spacer()
                Picker("On release, run", selection: Binding(
                    get: { entry.defaultOptionID },
                    set: { id in edit { $0.setDefault(id, at: slot) } })) {
                    ForEach(entry.optionIDs, id: \.self) { id in
                        Text(title(of: id)).tag(id)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(entry.optionIDs.count < 2)
            }
            SettingsSeparator()
            SettingsToggleRow(title: "Remember last choice",
                              detail: "Releasing on \(entry.verb.title) repeats your last pick from the outer ring.",
                              isOn: Binding(get: { entry.remembersLastUsed },
                                            set: { on in edit { $0.setRemembersLastUsed(on, at: slot) } }))
                .disabled(entry.optionIDs.count < 2)
        }
        .padding(.top, 14)
    }

    private func optionRow(_ id: String, shown: Bool, entry: SlotConfiguration) -> some View {
        let isLast = shown && entry.optionIDs.count == 1
        let index = entry.optionIDs.firstIndex(of: id)
        return SettingsRow {
            Toggle(title(of: id), isOn: Binding(
                get: { shown },
                set: { on in edit { $0.setOption(id, shown: on, at: slot) } }))
                .toggleStyle(.checkbox)
                .disabled(isLast)
            Spacer()
            if shown && id == entry.defaultOptionID && entry.optionIDs.count > 1 {
                Text("Default")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            if shown {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .help("Drag to reorder")
            }
        }
        .frame(minHeight: 34)
        .foregroundStyle(shown ? .primary : .secondary)
        .contentShape(Rectangle())
        .contextMenu {
            if let index {
                Button("Move Up") { edit { $0.moveOption(id, onto: entry.optionIDs[index - 1], at: slot) } }
                    .disabled(index == 0)
                Button("Move Down") { edit { $0.moveOption(id, onto: entry.optionIDs[index + 1], at: slot) } }
                    .disabled(index == entry.optionIDs.count - 1)
                Button("Make Default") { edit { $0.setDefault(id, at: slot) } }
                    .disabled(id == entry.defaultOptionID)
            }
        }
    }

    private func title(of id: String) -> String {
        allOptions.first { $0.id == id }?.title ?? id
    }

    private func menuTitle(_ verb: Verb) -> String {
        if let other = config.slot(of: verb), other != slot {
            return "\(verb.title) (swap with \(other.name))"
        }
        return verb.title
    }

    private func description(of verb: Verb) -> String {
        switch (verb, type) {
        case (.markdown, .pdf), (.markdown, .image):
            let base = "Extracts the text as Markdown using Mistral OCR. The files are sent to Mistral."
            return settings.mistralKey.isEmpty ? base + " Add an API key under Services first." : base
        case (.markdown, _):
            return "Transcribes speech into a Markdown file, on this Mac."
        case (.convert, .pdf):
            return "Saves every page as an image."
        case (.convert, _):
            return "Saves a copy in another format."
        case (.compress, _):
            return "Saves a smaller copy."
        case (.split, _):
            return "Saves each page as its own PDF."
        case (.cutOut, _):
            return "Saves the subject without its background."
        case (.combine, .pdf):
            return "Merges the selected PDFs into one. Shown when two or more PDFs are selected."
        case (.combine, _):
            return "Puts the selected images into one PDF."
        }
    }
}

extension Slot {
    var name: String {
        switch self {
        case .up: return "Up"
        case .upperRight: return "Upper Right"
        case .lowerRight: return "Lower Right"
        case .down: return "Down"
        case .lowerLeft: return "Lower Left"
        case .upperLeft: return "Upper Left"
        }
    }
}
