import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import FinderWheelCore

@Suite struct VideoToGIFActionTests {
    private let context = ActionContext(settings: SettingsSnapshot(), progress: { _ in })

    @Test func writesALoopingGIFAt12FPSAnd480Wide() async throws {
        let tmp = TempFolder()
        let input = try await MediaFixtures.writeVideo(to: tmp.file("clip.mov"), seconds: 2, width: 640, height: 480)
        let outcome = try await VideoToGIFAction().run(input: input, context: context)
        let out = tmp.file("clip.gif")
        #expect(outcome == .produced([out]))
        let source = try #require(CGImageSourceCreateWithURL(out as CFURL, nil))
        #expect(UTType(CGImageSourceGetType(source)! as String) == .gif)
        #expect(abs(CGImageSourceGetCount(source) - 24) <= 1)
        let size = Fixtures.pixelSize(out)
        #expect(size.width == 480)
        #expect(size.height == 360)
        let fileProps = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let gifProps = fileProps?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        #expect(gifProps?[kCGImagePropertyGIFLoopCount] as? Int == 0)
        let frameProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let frameGIF = frameProps?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let delay = frameGIF?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? 0
        #expect(abs(delay - 1.0 / 12) < 0.02)
    }

    @Test func audioFileHasNoVideoTrack() async throws {
        let tmp = TempFolder()
        let input = try MediaFixtures.writeTone(to: tmp.file("memo.wav"))
        await #expect(throws: ActionError("No video track")) {
            _ = try await VideoToGIFAction().run(input: input, context: context)
        }
    }

    @Test func routerKnowsGIF() {
        #expect(ActionRouter.action(for: .convert(.gif), fileKind: .video) is VideoToGIFAction)
        #expect(ActionRouter.action(for: .convert(.gif), fileKind: .image) == nil)
    }
}
