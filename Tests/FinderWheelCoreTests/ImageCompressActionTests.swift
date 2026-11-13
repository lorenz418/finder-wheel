import Testing
import Foundation
import UniformTypeIdentifiers
@testable import FinderWheelCore

@Suite struct ImageCompressActionTests {
    private let context = ActionContext(settings: SettingsSnapshot(), progress: { _ in })

    private func output(_ outcome: ActionOutcome) throws -> URL {
        guard case .produced(let urls) = outcome, urls.count == 1 else {
            throw ActionError("expected one output, got \(outcome)")
        }
        return urls[0]
    }

    @Test func jpegStaysJPEGAndGetsSmaller() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeNoiseImage(to: tmp.file("photo.jpg"), type: .jpeg)
        let out = try output(try await ImageCompressAction(preset: .medium).run(input: input, context: context))
        #expect(out.lastPathComponent == "photo-compressed.jpg")
        #expect(Fixtures.imageType(out) == .jpeg)
        #expect(Fixtures.fileSize(out) < Fixtures.fileSize(input))
        #expect(Fixtures.pixelSize(out).width == 1200)
    }

    @Test func strongerPresetsAreSmaller() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeNoiseImage(to: tmp.file("photo.jpg"), type: .jpeg)
        let light = try output(try await ImageCompressAction(preset: .light).run(input: input, context: context))
        let strong = try output(try await ImageCompressAction(preset: .strong).run(input: input, context: context))
        #expect(Fixtures.fileSize(strong) < Fixtures.fileSize(light))
    }

    @Test func heicStaysHEIC() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeNoiseImage(to: tmp.file("photo.heic"), type: .heic)
        let out = try output(try await ImageCompressAction(preset: .strong).run(input: input, context: context))
        #expect(out.lastPathComponent == "photo-compressed.heic")
        #expect(Fixtures.imageType(out) == .heic)
    }

    @Test func pngBecomesJPG() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeNoiseImage(to: tmp.file("shot.png"), type: .png)
        let out = try output(try await ImageCompressAction(preset: .medium).run(input: input, context: context))
        #expect(out.lastPathComponent == "shot-compressed.jpg")
        #expect(Fixtures.imageType(out) == .jpeg)
    }

    @Test func tiffBecomesJPG() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeNoiseImage(to: tmp.file("scan.tiff"), type: .tiff)
        let out = try output(try await ImageCompressAction(preset: .medium).run(input: input, context: context))
        #expect(out.lastPathComponent == "scan-compressed.jpg")
    }

    @Test func resizeLimitsLongestSide() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeNoiseImage(to: tmp.file("big.jpg"), type: .jpeg, width: 3000, height: 1500)
        let out = try output(try await ImageCompressAction(preset: .resize).run(input: input, context: context))
        let size = Fixtures.pixelSize(out)
        #expect(size.width == 2000)
        #expect(size.height == 1000)
    }

    @Test func skipsWhenNotSmaller() async throws {
        let tmp = TempFolder()
        // Already saved at very low quality: recompressing at 0.8 cannot shrink it.
        let input = Fixtures.writeNoiseImage(to: tmp.file("tiny.jpg"), type: .jpeg, width: 200, height: 200, quality: 0.05)
        let outcome = try await ImageCompressAction(preset: .light).run(input: input, context: context)
        #expect(outcome == .skipped("Already as small as it gets"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.url.path) == ["tiny.jpg"])
    }
}
