import Testing
import Foundation
@testable import FinderWheelCore

@Suite final class LastUsedStoreTests {
    private var created: [(name: String, defaults: UserDefaults)] = []

    /// Called at the end of every test (deinit would race with the process exiting).
    private func cleanUp() {
        // removePersistentDomain empties the domain but leaves an empty .plist behind, so delete that too.
        let preferences = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Preferences")
        for (name, defaults) in created {
            defaults.removePersistentDomain(forName: name)
            defaults.synchronize()
        }
        let names = created.map(\.name)
        created.removeAll()
        Thread.sleep(forTimeInterval: 0.5) // cfprefsd writes the emptied domain asynchronously
        for name in names { try? FileManager.default.removeItem(at: preferences.appendingPathComponent("\(name).plist")) }
    }

    private func makeStore() -> LastUsedStore {
        let name = "LastUsedStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        created.append((name, defaults))
        return LastUsedStore(defaults: defaults)
    }
    private var imageConvert: WheelEntry {
        WheelLayout.entries(for: .image, fileCount: 1).first { $0.verb == .convert }!
    }

    @Test func fallsBackToDefault() {
        defer { cleanUp() }
        #expect(makeStore().option(for: imageConvert, classification: .image).id == "jpg")
    }

    @Test func remembersPerClassificationAndVerb() {
        defer { cleanUp() }
        let store = makeStore()
        store.remember(optionID: "heic", for: imageConvert, classification: .image)
        #expect(store.option(for: imageConvert, classification: .image).id == "heic")
        let pdfConvert = WheelLayout.entries(for: .pdf, fileCount: 1).first { $0.verb == .convert }!
        #expect(store.option(for: pdfConvert, classification: .pdf).id == "png")
    }

    @Test func ignoresStoredValueThatIsNoLongerAnOption() {
        defer { cleanUp() }
        let store = makeStore()
        store.remember(optionID: "bmp", for: imageConvert, classification: .image)
        #expect(store.option(for: imageConvert, classification: .image).id == "jpg")
    }

    @Test func entriesThatDoNotRememberAlwaysUseDefault() {
        defer { cleanUp() }
        let store = makeStore()
        let mixCompress = WheelLayout.entries(for: .pdfImage, fileCount: 2).first { $0.verb == .compress }!
        store.remember(optionID: "strong", for: mixCompress, classification: .pdfImage)
        #expect(store.option(for: mixCompress, classification: .pdfImage).id == "medium")
    }
}
