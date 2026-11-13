import Testing
import Foundation
import AVFoundation
import UniformTypeIdentifiers
@testable import FinderWheelCore

@Suite struct AudioEncodeActionTests {
    private let context = ActionContext(settings: SettingsSnapshot(), progress: { _ in })

    @Test func convertsWAVToM4A() async throws {
        let tmp = TempFolder()
        let input = try MediaFixtures.writeTone(to: tmp.file("memo.wav"))
        let outcome = try await AudioEncodeAction.convert.run(input: input, context: context)
        let out = tmp.file("memo.m4a")
        #expect(outcome == .produced([out]))
        #expect(Classifier.kind(of: out) == .audio)
        #expect(abs(try await MediaFixtures.duration(out) - 3) < 0.2)
        #expect(Fixtures.fileSize(out) < Fixtures.fileSize(input))
    }

    @Test func convertsMonoInput() async throws {
        let tmp = TempFolder()
        let input = try MediaFixtures.writeTone(to: tmp.file("mono.wav"), channels: 1)
        let outcome = try await AudioEncodeAction.convert.run(input: input, context: context)
        #expect(outcome == .produced([tmp.file("mono.m4a")]))
    }

    @Test func convertSkipsM4A() async throws {
        let tmp = TempFolder()
        let wav = try MediaFixtures.writeTone(to: tmp.file("memo.wav"))
        _ = try await AudioEncodeAction.convert.run(input: wav, context: context)
        let outcome = try await AudioEncodeAction.convert.run(input: tmp.file("memo.m4a"), context: context)
        #expect(outcome == .skipped("Already M4A"))
    }

    @Test func extractsAudioFromVideo() async throws {
        let tmp = TempFolder()
        let input = try await MediaFixtures.writeVideo(to: tmp.file("clip.mov"))
        let outcome = try await AudioEncodeAction.convert.run(input: input, context: context)
        let out = tmp.file("clip.m4a")
        #expect(outcome == .produced([out]))
        #expect(try await MediaFixtures.trackCount(out, .audio) == 1)
        #expect(try await MediaFixtures.trackCount(out, .video) == 0)
    }

    @Test func videoWithoutAudioFails() async throws {
        let tmp = TempFolder()
        let input = try await MediaFixtures.writeVideo(to: tmp.file("silent.mov"), silent: true)
        await #expect(throws: ActionError("No audio track")) {
            _ = try await AudioEncodeAction.convert.run(input: input, context: context)
        }
        #expect(!FileManager.default.fileExists(atPath: tmp.file("silent.m4a").path))
    }

    @Test func compressWritesSmallerM4AAndStrongerIsSmaller() async throws {
        let tmp = TempFolder()
        let input = try MediaFixtures.writeTone(to: tmp.file("memo.wav"), seconds: 6)
        guard case .produced(let light) = try await AudioEncodeAction.compress(.light).run(input: input, context: context),
              case .produced(let strong) = try await AudioEncodeAction.compress(.strong).run(input: input, context: context) else {
            Issue.record("expected both presets to produce output")
            return
        }
        #expect(light[0].lastPathComponent == "memo-compressed.m4a")
        #expect(strong[0].lastPathComponent == "memo-compressed-2.m4a")
        #expect(Fixtures.fileSize(light[0]) < Fixtures.fileSize(input))
        #expect(Fixtures.fileSize(strong[0]) < Fixtures.fileSize(light[0]))
    }

    @Test func compressAcceptsM4AInput() async throws {
        let tmp = TempFolder()
        let wav = try MediaFixtures.writeTone(to: tmp.file("memo.wav"), seconds: 6)
        _ = try await AudioEncodeAction.convert.run(input: wav, context: context)
        switch try await AudioEncodeAction.compress(.strong).run(input: tmp.file("memo.m4a"), context: context) {
        case .produced(let urls): #expect(Fixtures.fileSize(urls[0]) < Fixtures.fileSize(tmp.file("memo.m4a")))
        case .skipped(let reason): #expect(reason == "Already as small as it gets")
        }
    }

    @Test func routerKnowsAudioActions() {
        #expect(ActionRouter.action(for: .convert(.m4a), fileKind: .audio) is AudioEncodeAction)
        #expect(ActionRouter.action(for: .convert(.m4a), fileKind: .video) is AudioEncodeAction)
        #expect(ActionRouter.action(for: .compress(.medium), fileKind: .audio) is AudioEncodeAction)
        #expect(ActionRouter.action(for: .convert(.mp4), fileKind: .audio) == nil)
    }
}
