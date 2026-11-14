import Foundation

/// File types whose wheel the user arranges. Mixed selections are derived from these.
public enum WheelFileType: String, CaseIterable, Codable, Sendable {
    case pdf, image, video, audio

    public var classification: Classification {
        switch self {
        case .pdf: return .pdf
        case .image: return .image
        case .video: return .video
        case .audio: return .audio
        }
    }

    public var title: String {
        switch self {
        case .pdf: return "PDF"
        case .image: return "Images"
        case .video: return "Video"
        case .audio: return "Audio"
        }
    }

    /// SF Symbol name.
    public var symbol: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        }
    }
}

/// What every action can offer, per classification. Matches what `ActionRouter` implements.
public enum WheelCatalog {
    public static func verbs(for classification: Classification) -> [Verb] {
        Verb.allCases.filter { !options(for: $0, classification: classification).isEmpty }
    }

    /// Every option of `verb` for `classification`, in their natural order; empty if unsupported.
    public static func options(for verb: Verb, classification: Classification) -> [WheelOption] {
        switch verb {
        case .markdown:
            return classification == .unsupported ? [] : [single(verb, .markdown)]
        case .convert:
            let targets: [ConvertTarget]
            switch classification {
            case .pdf: targets = [.png, .jpg]
            case .image: targets = [.jpg, .png, .heic, .tiff]
            case .video: targets = [.mp4, .gif, .m4a]
            case .audio, .videoAudio: targets = [.m4a]
            case .pdfImage, .unsupported: targets = []
            }
            return targets.map { WheelOption(id: $0.rawValue, title: $0.rawValue.uppercased(), action: .convert($0)) }
        case .compress:
            guard classification != .unsupported else { return [] }
            var presets: [CompressPreset] = [.light, .medium, .strong]
            if classification == .image { presets.append(.resize) }
            return presets.map { WheelOption(id: $0.rawValue, title: $0 == .resize ? "2000 px" : $0.rawValue.capitalized, action: .compress($0)) }
        case .split:
            return classification == .pdf ? [single(verb, .splitPDF)] : []
        case .cutOut:
            return classification == .image ? [single(verb, .cutOut)] : []
        case .combine:
            return [.pdf, .image, .pdfImage].contains(classification) ? [single(verb, .combine)] : []
        }
    }

    /// The option a plain release runs unless the user picked another.
    public static func defaultOptionID(for verb: Verb, classification: Classification) -> String? {
        let all = options(for: verb, classification: classification)
        if verb == .compress, all.contains(where: { $0.id == CompressPreset.medium.rawValue }) { return CompressPreset.medium.rawValue }
        return all.first?.id
    }

    private static func single(_ verb: Verb, _ action: ActionKind) -> WheelOption {
        WheelOption(id: verb.rawValue, title: verb.title, action: action)
    }
}

/// How one direction of the wheel is set up.
public struct SlotConfiguration: Codable, Equatable, Sendable {
    public var verb: Verb
    /// Options shown in the outer ring, in order. Never empty once sanitized.
    public var optionIDs: [String]
    /// What a plain release runs, unless `remembersLastUsed` and a choice was made before.
    public var defaultOptionID: String
    public var remembersLastUsed: Bool

    public init(verb: Verb, optionIDs: [String], defaultOptionID: String, remembersLastUsed: Bool) {
        self.verb = verb
        self.optionIDs = optionIDs
        self.defaultOptionID = defaultOptionID
        self.remembersLastUsed = remembersLastUsed
    }

    /// The verb with all its options, as the app ships it.
    public static func standard(_ verb: Verb, for type: WheelFileType) -> SlotConfiguration {
        let c = type.classification
        return SlotConfiguration(verb: verb,
                                 optionIDs: WheelCatalog.options(for: verb, classification: c).map(\.id),
                                 defaultOptionID: WheelCatalog.defaultOptionID(for: verb, classification: c) ?? verb.rawValue,
                                 remembersLastUsed: verb == .convert || verb == .compress)
    }
}

/// The wheel for one file type: an action, or nothing, in each of the six directions.
public struct WheelConfiguration: Codable, Equatable, Sendable {
    /// Indexed by `Slot.rawValue`; nil is an empty direction.
    private var slots: [SlotConfiguration?]

    public init(_ slots: [Slot: SlotConfiguration] = [:]) {
        self.slots = Slot.allCases.map { slots[$0] }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Always six directions, whatever was stored. A direction that cannot be read, for
        // example one with an action this version does not know, becomes empty; the rest is kept.
        let stored = try container.decode([Lenient].self, forKey: .slots)
        slots = Slot.allCases.map { stored.indices.contains($0.rawValue) ? stored[$0.rawValue].value : nil }
    }

    private struct Lenient: Decodable {
        let value: SlotConfiguration?
        init(from decoder: Decoder) { value = try? SlotConfiguration(from: decoder) }
    }

    public subscript(slot: Slot) -> SlotConfiguration? {
        get { slots.indices.contains(slot.rawValue) ? slots[slot.rawValue] : nil }
        set { slots[slot.rawValue] = newValue }
    }

    public func slot(of verb: Verb) -> Slot? {
        Slot.allCases.first { self[$0]?.verb == verb }
    }

    public static func standard(for type: WheelFileType) -> WheelConfiguration {
        let placement: [(Slot, Verb)] = [(.up, .markdown), (.upperRight, .convert), (.lowerRight, .compress),
                                         (.lowerLeft, .split), (.lowerLeft, .cutOut), (.upperLeft, .combine)]
        let verbs = WheelCatalog.verbs(for: type.classification)
        var config = WheelConfiguration()
        for (slot, verb) in placement where verbs.contains(verb) {
            config[slot] = .standard(verb, for: type)
        }
        return config
    }

    /// Repairs a stored configuration: drops actions the type does not support and repeated
    /// actions, unknown options, and fixes an empty outer ring or a default that is not shown.
    public func sanitized(for type: WheelFileType) -> WheelConfiguration {
        let c = type.classification
        var result = WheelConfiguration()
        var seen: Set<Verb> = []
        for slot in Slot.allCases {
            guard var entry = self[slot], !seen.contains(entry.verb) else { continue }
            let available = WheelCatalog.options(for: entry.verb, classification: c).map(\.id)
            guard !available.isEmpty else { continue }
            seen.insert(entry.verb)
            var ids: [String] = []
            for id in entry.optionIDs where available.contains(id) && !ids.contains(id) { ids.append(id) }
            entry.optionIDs = ids.isEmpty ? available : ids
            if !entry.optionIDs.contains(entry.defaultOptionID) {
                let standard = WheelCatalog.defaultOptionID(for: entry.verb, classification: c)
                entry.defaultOptionID = entry.optionIDs.first { $0 == standard } ?? entry.optionIDs[0]
            }
            result[slot] = entry
        }
        return result
    }

    // MARK: Editing

    /// Puts `verb` in `slot`. If the verb is already in another direction, the two directions swap.
    /// Nil empties the direction. Verbs the type does not support are ignored.
    public mutating func assign(_ verb: Verb?, to slot: Slot, type: WheelFileType) {
        guard let verb else {
            self[slot] = nil
            return
        }
        guard WheelCatalog.verbs(for: type.classification).contains(verb) else { return }
        if let current = self.slot(of: verb) {
            swap(current, slot)
        } else {
            self[slot] = .standard(verb, for: type)
        }
    }

    public mutating func swap(_ a: Slot, _ b: Slot) {
        let first = self[a]
        self[a] = self[b]
        self[b] = first
    }

    /// Shows or hides an option in the outer ring. The last shown option cannot be hidden.
    /// Hiding the default makes the first remaining option the default.
    public mutating func setOption(_ id: String, shown: Bool, at slot: Slot) {
        guard var entry = self[slot] else { return }
        if shown {
            if !entry.optionIDs.contains(id) { entry.optionIDs.append(id) }
        } else {
            guard entry.optionIDs.count > 1 else { return }
            entry.optionIDs.removeAll { $0 == id }
            if entry.defaultOptionID == id { entry.defaultOptionID = entry.optionIDs[0] }
        }
        self[slot] = entry
    }

    /// Moves a shown option to the position another shown option has.
    public mutating func moveOption(_ id: String, onto target: String, at slot: Slot) {
        guard var entry = self[slot] else { return }
        entry.optionIDs = Reorder.move(id, onto: target, in: entry.optionIDs)
        self[slot] = entry
    }

    public mutating func setDefault(_ id: String, at slot: Slot) {
        guard var entry = self[slot], entry.optionIDs.contains(id) else { return }
        entry.defaultOptionID = id
        self[slot] = entry
    }

    public mutating func setRemembersLastUsed(_ remembers: Bool, at slot: Slot) {
        self[slot]?.remembersLastUsed = remembers
    }
}

/// The user's wheels for all file types.
public struct WheelConfigurations: Equatable, Sendable {
    private var byType: [WheelFileType: WheelConfiguration]

    public init(_ byType: [WheelFileType: WheelConfiguration] = [:]) {
        self.byType = byType
    }

    public static let standard = WheelConfigurations()

    public subscript(type: WheelFileType) -> WheelConfiguration {
        get { byType[type] ?? .standard(for: type) }
        set { byType[type] = newValue }
    }
}
