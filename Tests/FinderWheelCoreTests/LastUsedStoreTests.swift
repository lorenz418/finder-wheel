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
}
