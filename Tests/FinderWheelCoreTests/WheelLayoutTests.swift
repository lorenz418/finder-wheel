import Testing
@testable import FinderWheelCore

@Suite struct WheelLayoutTests {
    private func verbs(_ c: Classification, count: Int = 2) -> [Slot: Verb] {
        Dictionary(uniqueKeysWithValues: WheelLayout.entries(for: c, fileCount: count).map { ($0.slot, $0.verb) })
    }
    private func entry(_ c: Classification, _ verb: Verb, count: Int = 2) -> WheelEntry? {
        WheelLayout.entries(for: c, fileCount: count).first { $0.verb == verb }
    }

    @Test func verbsKeepTheirDirection() {
        for c in Classification.allCases {
            for e in WheelLayout.entries(for: c, fileCount: 2) {
                switch e.verb {
                case .markdown: #expect(e.slot == .up)
                case .convert: #expect(e.slot == .upperRight)
                case .compress: #expect(e.slot == .lowerRight)
                case .extra: #expect(e.slot == .lowerLeft)
                case .combine: #expect(e.slot == .upperLeft)
                }
            }
        }
    }

    @Test func verbsPerClassification() {
        #expect(Set(verbs(.pdf).values) == [.markdown, .convert, .compress, .extra, .combine])
        #expect(Set(verbs(.image).values) == [.markdown, .convert, .compress, .extra, .combine])
        #expect(Set(verbs(.video).values) == [.markdown, .convert, .compress])
        #expect(Set(verbs(.audio).values) == [.markdown, .convert, .compress])
        #expect(Set(verbs(.videoAudio).values) == [.markdown, .convert, .compress])
        #expect(Set(verbs(.pdfImage).values) == [.markdown, .compress, .combine])
        #expect(WheelLayout.entries(for: .unsupported, fileCount: 1).isEmpty)
    }

    @Test func combineNeedsTwoPDFsButOneImageIsEnough() {
        #expect(entry(.pdf, .combine, count: 1) == nil)
        #expect(entry(.pdf, .combine, count: 2) != nil)
        #expect(entry(.image, .combine, count: 1) != nil)
    }

    @Test func convertOptionsAndDefaults() {
        #expect(entry(.pdf, .convert)?.options.map(\.id) == ["png", "jpg"])
        #expect(entry(.pdf, .convert)?.defaultOptionID == "png")
        #expect(entry(.image, .convert)?.options.map(\.id) == ["jpg", "png", "heic", "tiff"])
        #expect(entry(.image, .convert)?.defaultOptionID == "jpg")
        #expect(entry(.video, .convert)?.options.map(\.id) == ["mp4", "gif", "m4a"])
        #expect(entry(.video, .convert)?.defaultOptionID == "mp4")
        #expect(entry(.audio, .convert)?.options.map(\.id) == ["m4a"])
        #expect(entry(.videoAudio, .convert)?.options.map(\.id) == ["m4a"])
    }

    @Test func compressOptionsAndDefaults() {
        #expect(entry(.pdf, .compress)?.options.map(\.id) == ["light", "medium", "strong"])
        #expect(entry(.image, .compress)?.options.map(\.id) == ["light", "medium", "strong", "resize"])
        #expect(entry(.pdfImage, .compress)?.options.map(\.id) == ["light", "medium", "strong"])
        for c in [Classification.pdf, .image, .video, .audio, .videoAudio, .pdfImage] {
            #expect(entry(c, .compress)?.defaultOptionID == "medium")
        }
    }

    @Test func mixesDoNotRememberLastUsed() {
        for e in WheelLayout.entries(for: .pdfImage, fileCount: 2) { #expect(!e.remembersLastUsed) }
        for e in WheelLayout.entries(for: .videoAudio, fileCount: 2) { #expect(!e.remembersLastUsed) }
        #expect(entry(.image, .convert)?.remembersLastUsed == true)
    }

    @Test func optionsCarryActions() {
        #expect(entry(.image, .convert)?.options.first?.action == .convert(.jpg))
        #expect(entry(.pdf, .extra)?.options.first?.action == .splitPDF)
        #expect(entry(.image, .extra)?.options.first?.action == .cutOut)
        #expect(entry(.pdf, .combine)?.options.first?.action == .combine)
        #expect(entry(.video, .markdown)?.options.first?.action == .markdown)
        #expect(entry(.image, .compress)?.options.last?.action == .compress(.resize))
    }
}
