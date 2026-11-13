import Foundation

/// Immutable copy of the settings an action needs. Passed into every job.
public struct SettingsSnapshot: Sendable {
    public var stripLocation: Bool
    public var mistralKey: String?
    public var transcriptionLocale: Locale

    public init(stripLocation: Bool = true, mistralKey: String? = nil, transcriptionLocale: Locale = .current) {
        self.stripLocation = stripLocation
        self.mistralKey = mistralKey
        self.transcriptionLocale = transcriptionLocale
    }
}

/// A hotkey the user can pick. Values are Carbon virtual key codes and modifier masks.
public struct HotkeyCombo: Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let keyCode: UInt32
    public let modifiers: UInt32

    private static let space: UInt32 = 49       // kVK_Space
    private static let option: UInt32 = 0x0800  // optionKey
    private static let control: UInt32 = 0x1000 // controlKey

    public static let optionSpace = HotkeyCombo(id: "option-space", label: "⌥ Space", keyCode: space, modifiers: option)
    public static let controlSpace = HotkeyCombo(id: "control-space", label: "⌃ Space", keyCode: space, modifiers: control)
    public static let controlOptionSpace = HotkeyCombo(id: "control-option-space", label: "⌃⌥ Space", keyCode: space, modifiers: control | option)

    public static let all: [HotkeyCombo] = [.optionSpace, .controlSpace, .controlOptionSpace]
    public static func named(_ id: String?) -> HotkeyCombo { all.first { $0.id == id } ?? .optionSpace }
}
