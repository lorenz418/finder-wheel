import Testing
import Foundation
@testable import FinderWheelCore

@MainActor
@Suite(.serialized) struct AppSettingsTests {
    /// One fixed test domain, cleared before each use, so test runs never leave
    /// new files in ~/Library/Preferences. Same pattern as LastUsedStoreTests.
    private func defaults() -> UserDefaults {
        let name = "com.lorenz.finderwheel.tests.settings"
        UserDefaults().removePersistentDomain(forName: name)
        return UserDefaults(suiteName: name)!
    }

    @Test func defaultsMatchTheSpec() {
        let settings = AppSettings(defaults: defaults(), secrets: InMemorySecretStore())
        #expect(settings.hotkey == .optionSpace)
        #expect(settings.stripLocation)
        #expect(settings.mistralKey.isEmpty)
        #expect(settings.snapshot().mistralKey == nil)
        #expect(settings.snapshot().stripLocation)
        // The system locale without overrides such as "@rg=dezzzz".
        #expect(settings.snapshot().transcriptionLocale.identifier == Locale.current.identifier.components(separatedBy: "@")[0])
    }

    @Test func valuesPersist() {
        let store = defaults()
        let secrets = InMemorySecretStore()
        let first = AppSettings(defaults: store, secrets: secrets)
        first.hotkeyID = HotkeyCombo.controlSpace.id
        first.stripLocation = false
        first.mistralKey = "key-123"
        first.transcriptionLocaleID = "de_DE"

        let second = AppSettings(defaults: store, secrets: secrets)
        #expect(second.hotkey == .controlSpace)
        #expect(!second.stripLocation)
        #expect(second.mistralKey == "key-123")
        #expect(second.snapshot().mistralKey == "key-123")
        #expect(second.snapshot().transcriptionLocale.identifier == "de_DE")
    }

    @Test func keyIsStoredOnlyInTheSecretStore() {
        let store = defaults()
        let secrets = InMemorySecretStore()
        let settings = AppSettings(defaults: store, secrets: secrets)
        settings.mistralKey = "  key-123 \n"
        #expect(secrets.get() == "key-123")
        #expect(!store.dictionaryRepresentation().values.contains { ($0 as? String)?.contains("key-123") == true })
        settings.mistralKey = ""
        #expect(secrets.get() == nil)
    }

    @Test func unknownHotkeyFallsBackToDefault() {
        let store = defaults()
        store.set("nonsense", forKey: "hotkeyID")
        #expect(AppSettings(defaults: store, secrets: InMemorySecretStore()).hotkey == .optionSpace)
    }
}
