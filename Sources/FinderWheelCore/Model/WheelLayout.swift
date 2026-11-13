import Foundation

/// The six fixed directions, clockwise from the top. Raw value times 60 is the angle in degrees.
public enum Slot: Int, CaseIterable, Sendable {
    case up = 0, upperRight, lowerRight, down, lowerLeft, upperLeft
}

public enum Verb: String, Sendable {
    case markdown, convert, compress, extra, combine
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

/// The single source of truth for what the wheel shows.
public enum WheelLayout {
    public static func entries(for classification: Classification, fileCount: Int) -> [WheelEntry] {
        switch classification {
        case .pdf:
            var list = [
                markdown(),
                convert([.png, .jpg], default: .png),
                compress(resize: false),
                single(.lowerLeft, .extra, "Split", "square.split.2x1", .splitPDF),
            ]
            if fileCount >= 2 { list.append(combine()) }
            return list
        case .image:
            return [
                markdown(),
                convert([.jpg, .png, .heic, .tiff], default: .jpg),
                compress(resize: true),
                single(.lowerLeft, .extra, "Cut out", "person.crop.rectangle", .cutOut),
                combine(),
            ]
        case .video:
            return [markdown(), convert([.mp4, .gif, .m4a], default: .mp4), compress(resize: false)]
        case .audio:
            return [markdown(), convert([.m4a], default: .m4a), compress(resize: false)]
        case .videoAudio:
            return [markdown(), convert([.m4a], default: .m4a, remembers: false), compress(resize: false, remembers: false)]
        case .pdfImage:
            return [markdown(), compress(resize: false, remembers: false), combine()]
        case .unsupported:
            return []
        }
    }

    private static func single(_ slot: Slot, _ verb: Verb, _ title: String, _ symbol: String, _ action: ActionKind) -> WheelEntry {
        WheelEntry(slot: slot, verb: verb, title: title, symbol: symbol,
                   options: [WheelOption(id: verb.rawValue, title: title, action: action)],
                   defaultOptionID: verb.rawValue, remembersLastUsed: false)
    }

    private static func markdown() -> WheelEntry {
        single(.up, .markdown, "Markdown", "text.document", .markdown)
    }

    private static func combine() -> WheelEntry {
        single(.upperLeft, .combine, "Combine", "square.on.square", .combine)
    }

    private static func convert(_ targets: [ConvertTarget], default def: ConvertTarget, remembers: Bool = true) -> WheelEntry {
        WheelEntry(slot: .upperRight, verb: .convert, title: "Convert", symbol: "arrow.left.arrow.right",
                   options: targets.map { WheelOption(id: $0.rawValue, title: $0.rawValue.uppercased(), action: .convert($0)) },
                   defaultOptionID: def.rawValue, remembersLastUsed: remembers)
    }

    private static func compress(resize: Bool, remembers: Bool = true) -> WheelEntry {
        var presets: [CompressPreset] = [.light, .medium, .strong]
        if resize { presets.append(.resize) }
        return WheelEntry(slot: .lowerRight, verb: .compress, title: "Compress", symbol: "arrow.down.right.and.arrow.up.left",
                          options: presets.map { WheelOption(id: $0.rawValue, title: $0 == .resize ? "2000 px" : $0.rawValue.capitalized, action: .compress($0)) },
                          defaultOptionID: CompressPreset.medium.rawValue, remembersLastUsed: remembers)
    }
}
