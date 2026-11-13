import Testing
import Foundation
@testable import FinderWheelCore

@Suite struct VideoCompressActionTests {
    private let context = ActionContext(settings: SettingsSnapshot(), progress: { _ in })

    @Test func strongPresetShrinksANoisy720pClip() async throws {
        let tmp = TempFolder()
        let input = try await MediaFixtures.writeVideo(to: tmp.file("clip.mov"), seconds: 2, width: 1280, height: 720, noisy: true)
        let outcome = try await VideoCompressAction(preset: .strong).run(input: input, context: context)
        let out = tmp.file("clip-compressed.mp4")
        #expect(outcome == .produced([out]))
        #expect(Fixtures.fileSize(out) < Fixtures.fileSize(input))
        let size = try await MediaFixtures.videoSize(out)
        #expect(size.width == 960)
        #expect(size.height == 540)
    }

    @Test func smallFlatClipIsSkippedOrSmaller() async throws {
        let tmp = TempFolder()
        let input = try await MediaFixtures.writeVideo(to: tmp.file("tiny.mov"), seconds: 1, width: 320, height: 240)
        switch try await VideoCompressAction(preset: .light).run(input: input, context: context) {
        case .skipped(let reason):
            #expect(reason == "Already as small as it gets")
            #expect(!FileManager.default.fileExists(atPath: tmp.file("tiny-compressed.mp4").path))
        case .produced(let urls):
            #expect(Fixtures.fileSize(urls[0]) < Fixtures.fileSize(input))
        }
    }
}
