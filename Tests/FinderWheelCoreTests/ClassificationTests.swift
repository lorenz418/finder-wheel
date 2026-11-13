import Testing
import UniformTypeIdentifiers
@testable import FinderWheelCore

@Suite struct ClassificationTests {
    @Test func kindFromType() {
        #expect(Classifier.kind(of: .pdf, isDirectory: false) == .pdf)
        #expect(Classifier.kind(of: .jpeg, isDirectory: false) == .image)
        #expect(Classifier.kind(of: .png, isDirectory: false) == .image)
        #expect(Classifier.kind(of: .heic, isDirectory: false) == .image)
        #expect(Classifier.kind(of: .heif, isDirectory: false) == .image)
        #expect(Classifier.kind(of: .tiff, isDirectory: false) == .image)
        #expect(Classifier.kind(of: .webP, isDirectory: false) == .image)
        #expect(Classifier.kind(of: .quickTimeMovie, isDirectory: false) == .video)
        #expect(Classifier.kind(of: .mpeg4Movie, isDirectory: false) == .video)
        #expect(Classifier.kind(of: .mp3, isDirectory: false) == .audio)
        #expect(Classifier.kind(of: .mpeg4Audio, isDirectory: false) == .audio)
        #expect(Classifier.kind(of: .wav, isDirectory: false) == .audio)
    }

    @Test func unsupportedKinds() {
        #expect(Classifier.kind(of: .gif, isDirectory: false) == .unsupported)
        #expect(Classifier.kind(of: .plainText, isDirectory: false) == .unsupported)
        #expect(Classifier.kind(of: .folder, isDirectory: true) == .unsupported)
        #expect(Classifier.kind(of: nil, isDirectory: false) == .unsupported)
    }

    @Test func singleTypeSelections() {
        #expect(Classifier.classify([.pdf, .pdf]) == .pdf)
        #expect(Classifier.classify([.image]) == .image)
        #expect(Classifier.classify([.video]) == .video)
        #expect(Classifier.classify([.audio, .audio]) == .audio)
    }

    @Test func supportedMixes() {
        #expect(Classifier.classify([.pdf, .image, .image]) == .pdfImage)
        #expect(Classifier.classify([.audio, .video]) == .videoAudio)
    }

    @Test func everythingElseIsUnsupported() {
        #expect(Classifier.classify([]) == .unsupported)
        #expect(Classifier.classify([.pdf, .unsupported]) == .unsupported)
        #expect(Classifier.classify([.pdf, .video]) == .unsupported)
        #expect(Classifier.classify([.image, .audio]) == .unsupported)
        #expect(Classifier.classify([.pdf, .image, .video]) == .unsupported)
    }
}
