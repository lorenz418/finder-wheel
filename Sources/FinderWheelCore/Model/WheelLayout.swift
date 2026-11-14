import Foundation

/// The six fixed directions, clockwise from the top. Raw value times 60 is the angle in degrees.
public enum Slot: Int, CaseIterable, Sendable {
    case up = 0, upperRight, lowerRight, down, lowerLeft, upperLeft
}

public enum Verb: String, CaseIterable, Codable, Sendable {
    case markdown, convert, compress, split, cutOut, combine

    public var title: String {
        switch self {
        case .markdown: return "Markdown"
        case .convert: return "Convert"
        case .compress: return "Compress"
        case .split: return "Split"
        case .cutOut: return "Cut out"
        case .combine: return "Combine"
        }
    }

    /// SF Symbol name.
    public var symbol: String {
        switch self {
        case .markdown: return "text.document"
        case .convert: return "arrow.left.arrow.right"
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .split: return "square.split.2x1"
        case .cutOut: return "person.crop.rectangle"
        case .combine: return "square.on.square"
        }
    }
}

public struct WheelOption: Equatable, Sendable {
    public let id: String
    public let title: String
    public let action: ActionKind
}

public struct WheelEntry: Equatable, Sendable {
    public let slot: Slot
    public let verb: Verb
    public let title: String
    /// SF Symbol name.
    public let symbol: String
    /// Never empty. An entry with one option has no outer ring.
    public let options: [WheelOption]
    public let defaultOptionID: String
    public let remembersLastUsed: Bool
}

/// Turns the user's wheel configurations into what the wheel shows for a selection.
public enum WheelLayout {
    public static func entries(for classification: Classification, fileCount: Int,
                               configurations: WheelConfigurations = .standard) -> [WheelEntry] {
        switch classification {
        case .pdf, .image, .video, .audio:
            guard let type = WheelFileType.allCases.first(where: { $0.classification == classification }) else { return [] }
            let config = configurations[type].sanitized(for: type)
            return Slot.allCases.compactMap { slot in
                guard let slotConfig = config[slot] else { return nil }
                // Combining a single PDF would only copy it.
                if slotConfig.verb == .combine && classification == .pdf && fileCount < 2 { return nil }
                return entry(slot, slotConfig, classification: classification, remembers: slotConfig.remembersLastUsed)
            }
        case .videoAudio:
            return mixed(classification, of: [.video, .audio], configurations: configurations)
        case .pdfImage:
            return mixed(classification, of: [.pdf, .image], configurations: configurations)
        case .unsupported:
            return []
        }
    }

    /// A mixed selection shows the actions every file supports and that are on the wheel of
    /// every one of `types`: removing an action from one wheel removes it from the mix.
    /// Placement, options and default follow the first type, as far as they apply.
    /// Mixes never remember the last choice.
    private static func mixed(_ classification: Classification, of types: [WheelFileType],
                              configurations: WheelConfigurations) -> [WheelEntry] {
        let configs = types.map { configurations[$0].sanitized(for: $0) }
        let supported = WheelCatalog.verbs(for: classification)
        return Slot.allCases.compactMap { slot in
            guard let slotConfig = configs[0][slot], supported.contains(slotConfig.verb),
                  configs.allSatisfy({ $0.slot(of: slotConfig.verb) != nil }) else { return nil }
            return entry(slot, slotConfig, classification: classification, remembers: false)
        }
    }

    private static func entry(_ slot: Slot, _ config: SlotConfiguration, classification: Classification, remembers: Bool) -> WheelEntry {
        let available = WheelCatalog.options(for: config.verb, classification: classification)
        var options = config.optionIDs.compactMap { id in available.first { $0.id == id } }
        if options.isEmpty { options = available }
        let defaultID = options.contains { $0.id == config.defaultOptionID }
            ? config.defaultOptionID
            : options.first { $0.id == WheelCatalog.defaultOptionID(for: config.verb, classification: classification) }?.id ?? options[0].id
        return WheelEntry(slot: slot, verb: config.verb, title: config.verb.title, symbol: config.verb.symbol,
                          options: options, defaultOptionID: defaultID, remembersLastUsed: remembers && options.count > 1)
    }
}
