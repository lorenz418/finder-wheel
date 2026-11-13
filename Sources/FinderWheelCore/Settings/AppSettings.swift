import Foundation
import Observation

/// User settings. UserDefaults for plain values, a `SecretStore` for the API key.
@MainActor
@Observable
public final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let secrets: SecretStore

    public var hotkeyID: String {
        didSet { defaults.set(hotkeyID, forKey: "hotkeyID") }
    }
    public var stripLocation: Bool {
        didSet { defaults.set(stripLocation, forKey: "stripLocation") }
    }
    /// Locale identifier for transcription, for example "de_DE".
    public var transcriptionLocaleID: String {
        didSet { defaults.set(transcriptionLocaleID, forKey: "transcriptionLocaleID") }
    }
    /// Empty when no key is stored. Surrounding whitespace is ignored when storing.
    public var mistralKey: String {
        didSet {
            let trimmed = mistralKey.trimmingCharacters(in: .whitespacesAndNewlines)
            secrets.set(trimmed.isEmpty ? nil : trimmed)
        }
    }

    public init(defaults: UserDefaults = .standard, secrets: SecretStore = KeychainSecretStore()) {
        self.defaults = defaults
        self.secrets = secrets
        hotkeyID = HotkeyCombo.named(defaults.string(forKey: "hotkeyID")).id
        stripLocation = defaults.object(forKey: "stripLocation") as? Bool ?? true
        // Drop locale overrides ("en_US@rg=dezzzz") so the default is a plain language and region.
        transcriptionLocaleID = defaults.string(forKey: "transcriptionLocaleID")
            ?? Locale.current.identifier.components(separatedBy: "@")[0]
        mistralKey = secrets.get() ?? ""
    }

    public var hotkey: HotkeyCombo { HotkeyCombo.named(hotkeyID) }

    public func snapshot() -> SettingsSnapshot {
        let key = mistralKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return SettingsSnapshot(stripLocation: stripLocation, mistralKey: key.isEmpty ? nil : key,
                                transcriptionLocale: Locale(identifier: transcriptionLocaleID))
    }
}
