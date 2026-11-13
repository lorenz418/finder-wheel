import Testing
import Foundation
import AVFoundation
import CoreMedia
import UniformTypeIdentifiers
@testable import FinderWheelCore

@Suite struct VideoConvertActionTests {
    private let context = ActionContext(settings: SettingsSnapshot(), progress: { _ in })

    @Test func convertsMOVToMP4() async throws {
        let tmp = TempFolder()
        let input = try await MediaFixtures.writeVideo(to: tmp.file("clip.mov"))
        let outcome = try await VideoConvertAction().run(input: input, context: context)
        let out = tmp.file("clip.mp4")
        #expect(outcome == .produced([out]))
        #expect(try out.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .mpeg4Movie) == true)
        #expect(abs(try await MediaFixtures.duration(out) - 2) < 0.3)
        #expect(try await MediaFixtures.trackCount(out, .video) == 1)
        #expect(try await MediaFixtures.trackCount(out, .audio) == 1)
        #expect(FileManager.default.fileExists(atPath: input.path))
    }

    @Test func compatibleVideoIsRemuxedWithoutReencoding() async throws {
        func codec(_ url: URL) async throws -> FourCharCode? {
            let track = try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first
            let description = try await track?.load(.formatDescriptions).first
            return description.map { CMFormatDescriptionGetMediaSubType($0) }
        }
        let tmp = TempFolder()
        let input = try await MediaFixtures.writeVideo(to: tmp.file("clip.mov"), codec: .hevc)
        _ = try await VideoConvertAction().run(input: input, context: context)
        let out = tmp.file("clip.mp4")
        let inputCodec = try await codec(input)
        #expect(inputCodec == kCMVideoCodecType_HEVC)
        #expect(try await codec(out) == inputCodec)
        #expect(abs(try await MediaFixtures.duration(out) - MediaFixtures.duration(input)) < 0.1)
    }

    @Test func skipsMP4Input() async throws {
        let tmp = TempFolder()
        let mov = try await MediaFixtures.writeVideo(to: tmp.file("clip.mov"))
        _ = try await VideoConvertAction().run(input: mov, context: context)
        let outcome = try await VideoConvertAction().run(input: tmp.file("clip.mp4"), context: context)
        #expect(outcome == .skipped("Already MP4"))
    }

    @Test func audioFileHasNoVideoTrack() async throws {
        let tmp = TempFolder()
        let input = try MediaFixtures.writeTone(to: tmp.file("memo.wav"))
        await #expect(throws: ActionError("No video track")) {
            _ = try await VideoConvertAction().run(input: input, context: context)
        }
    }

    @Test func routerKnowsVideoConvert() {
        #expect(ActionRouter.action(for: .convert(.mp4), fileKind: .video) is VideoConvertAction)
        #expect(ActionRouter.action(for: .compress(.strong), fileKind: .video) is VideoCompressAction)
    }
}
