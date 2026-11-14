import Testing
import Foundation
@testable import FinderWheelCore

@Suite(.serialized) struct LastUsedStoreTests {
    private static let suiteName = "com.lorenz.finderwheel.tests"

    private func makeStore() -> LastUsedStore {
        UserDefaults().removePersistentDomain(forName: Self.suiteName)
        return LastUsedStore(defaults: UserDefaults(suiteName: Self.suiteName)!)
    }
    private var imageConvert: WheelEntry {
        WheelLayout.entries(for: .image, fileCount: 1).first { $0.verb == .convert }!
    }

    @Test func fallsBackToDefault() {
        #expect(makeStore().option(for: imageConvert, classification: .image).id == "jpg")
    }

    @Test func remembersPerClassificationAndVerb() {
        let store = makeStore()
        store.remember(optionID: "heic", for: imageConvert, classification: .image)
        #expect(store.option(for: imageConvert, classification: .image).id == "heic")
        let pdfConvert = WheelLayout.entries(for: .pdf, fileCount: 1).first { $0.verb == .convert }!
        #expect(store.option(for: pdfConvert, classification: .pdf).id == "png")
    }

    @Test func forgettingRestoresTheDefault() {
        let store = makeStore()
        store.remember(optionID: "heic", for: imageConvert, classification: .image)
        store.forget(.convert, classification: .pdf)
        #expect(store.option(for: imageConvert, classification: .image).id == "heic")
        store.forget(.convert, classification: .image)
        #expect(store.option(for: imageConvert, classification: .image).id == "jpg")
    }

    @Test func ignoresStoredValueThatIsNoLongerAnOption() {
        let store = makeStore()
        store.remember(optionID: "bmp", for: imageConvert, classification: .image)
        #expect(store.option(for: imageConvert, classification: .image).id == "jpg")
    }

    @Test func entriesThatDoNotRememberAlwaysUseDefault() {
        let store = makeStore()
        let mixCompress = WheelLayout.entries(for: .pdfImage, fileCount: 2).first { $0.verb == .compress }!
        store.remember(optionID: "strong", for: mixCompress, classification: .pdfImage)
        #expect(store.option(for: mixCompress, classification: .pdfImage).id == "medium")
    }

    @Test func editsThatChangeTheDefaultForgetTheRememberedChoice() {
        let standard = WheelConfiguration.standard(for: .image)
        let edits: [(inout WheelConfiguration) -> Void] = [
            { $0.setDefault("png", at: .upperRight) },
            { $0.setOption("jpg", shown: false, at: .upperRight) },
            { $0.setRemembersLastUsed(false, at: .upperRight) },
            { $0.assign(nil, to: .upperRight, type: .image) },
        ]
        for edit in edits {
            let store = makeStore()
            store.remember(optionID: "heic", for: imageConvert, classification: .image)
            var edited = standard
            edit(&edited)
            store.forgetChanges(from: standard, to: edited, type: .image)
            #expect(store.option(for: imageConvert, classification: .image).id == "jpg")
        }
    }

    @Test func movingOrReorderingKeepsTheRememberedChoice() {
        let standard = WheelConfiguration.standard(for: .image)
        let store = makeStore()
        store.remember(optionID: "heic", for: imageConvert, classification: .image)
        var edited = standard
        edited.swap(.upperRight, .down)
        edited.moveOption("tiff", onto: "jpg", at: .down)
        edited.assign(nil, to: .up, type: .image)
        store.forgetChanges(from: standard, to: edited, type: .image)
        #expect(store.option(for: imageConvert, classification: .image).id == "heic")
        // Resetting from a wheel with another default does forget.
        edited.setDefault("png", at: .down)
        store.forgetChanges(from: edited, to: standard, type: .image)
        #expect(store.option(for: imageConvert, classification: .image).id == "jpg")
    }
}
