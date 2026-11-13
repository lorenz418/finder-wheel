import Foundation
import Speech

/// On-device speech models: which languages exist, which are installed, and installing one.
public enum SpeechModels {
    /// Readable language name in the user's language, for example "German (Germany)".
    public static func displayName(for locale: Locale) -> String {
        // Identifiers can carry a "@calendar=..." suffix that the name lookup does not understand.
        let id = locale.identifier.split(separator: "@", maxSplits: 1).first.map(String.init) ?? locale.identifier
        return Locale.current.localizedString(forIdentifier: id) ?? id
    }

    /// All languages the on-device transcriber supports, sorted by display name.
    public static func supportedLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales.sorted { displayName(for: $0) < displayName(for: $1) }
    }

    /// The supported locale matching `locale`, or nil if the language has no on-device model.
    public static func supported(_ locale: Locale) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: locale)
    }

    public static func isInstalled(_ locale: Locale) async -> Bool {
        guard let match = await supported(locale) else { return false }
        let id = match.identifier(.bcp47)
        return await SpeechTranscriber.installedLocales.contains { $0.identifier(.bcp47) == id }
    }

    /// Downloads and installs the model for `locale`. Returns at once if nothing is needed.
    public static func install(_ locale: Locale) async throws {
        guard let match = await supported(locale) else {
            throw ActionError("Transcription is not available for \(displayName(for: locale))")
        }
        let transcriber = SpeechTranscriber(locale: match, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }
}
