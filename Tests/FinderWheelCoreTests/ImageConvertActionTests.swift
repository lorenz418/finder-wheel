import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import FinderWheelCore

@Suite struct ImageConvertActionTests {
    private func context(strip: Bool = true) -> ActionContext {
        ActionContext(settings: SettingsSnapshot(stripLocation: strip), progress: { _ in })
    }

    @Test func convertsPNGToJPGNextToOriginal() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeImage(to: tmp.file("shot.png"), type: .png)
        let outcome = try await ImageConvertAction(target: .jpg).run(input: input, context: context())
        #expect(outcome == .produced([tmp.file("shot.jpg")]))
        #expect(Fixtures.imageType(tmp.file("shot.jpg")) == .jpeg)
        #expect(FileManager.default.fileExists(atPath: input.path))
    }

    @Test func convertsToEachTarget() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeImage(to: tmp.file("a.jpg"), type: .jpeg)
        for (target, type) in [(ConvertTarget.png, UTType.png), (.heic, .heic), (.tiff, .tiff)] {
            let outcome = try await ImageConvertAction(target: target).run(input: input, context: context())
            guard case .produced(let urls) = outcome else { Issue.record("expected output"); continue }
            #expect(urls.count == 1)
            #expect(Fixtures.imageType(urls[0]) == type)
            #expect(urls[0].pathExtension == target.rawValue)
        }
    }

    @Test func skipsWhenAlreadyInTargetFormat() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeImage(to: tmp.file("a.jpeg"), type: .jpeg)
        let outcome = try await ImageConvertAction(target: .jpg).run(input: input, context: context())
        #expect(outcome == .skipped("Already JPG"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.url.path).count == 1)
    }

    @Test func stripsLocationByDefault() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeImage(to: tmp.file("a.jpg"), type: .jpeg, gps: true)
        #expect(Fixtures.imageProperties(input)[kCGImagePropertyGPSDictionary] != nil)
        _ = try await ImageConvertAction(target: .heic).run(input: input, context: context(strip: true))
        #expect(Fixtures.imageProperties(tmp.file("a.heic"))[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test func keepsLocationWhenStrippingIsOff() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeImage(to: tmp.file("a.jpg"), type: .jpeg, gps: true)
        _ = try await ImageConvertAction(target: .heic).run(input: input, context: context(strip: false))
        #expect(Fixtures.imageProperties(tmp.file("a.heic"))[kCGImagePropertyGPSDictionary] != nil)
    }

    @Test func doesNotOverwriteExistingOutput() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeImage(to: tmp.file("a.png"), type: .png)
        tmp.touch("a.jpg")
        let outcome = try await ImageConvertAction(target: .jpg).run(input: input, context: context())
        #expect(outcome == .produced([tmp.file("a-2.jpg")]))
    }

    @Test func unreadableFileThrows() async {
        let tmp = TempFolder()
        let input = tmp.touch("broken.png")
        await #expect(throws: ActionError.self) {
            _ = try await ImageConvertAction(target: .jpg).run(input: input, context: context())
        }
    }

    @Test func rejectsNonImageTarget() async {
        let tmp = TempFolder()
        let input = Fixtures.writeImage(to: tmp.file("a.png"), type: .png)
        await #expect(throws: ActionError.self) {
            _ = try await ImageConvertAction(target: .mp4).run(input: input, context: context())
        }
    }
}
