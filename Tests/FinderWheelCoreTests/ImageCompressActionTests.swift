import Testing
import Foundation
import UniformTypeIdentifiers
import CoreGraphics
import ImageIO
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

    @Test func jpegNamedPngKeepsJPEGExtension() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeNoiseImage(to: tmp.file("photo.png"), type: .jpeg)
        let out = try output(try await ImageCompressAction(preset: .medium).run(input: input, context: context))
        #expect(out.lastPathComponent == "photo-compressed.jpg")
        #expect(Fixtures.imageType(out) == .jpeg)
    }

    /// RGBA bytes of the pixel at (x, y), counted from the top-left of the image.
    private func pixel(_ url: URL, x: Int, y: Int) -> [UInt8] {
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        var bytes = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return bytes
    }

    @Test func transparentPNGBecomesJPGWithWhiteBackground() async throws {
        let tmp = TempFolder()
        // Noisy pixels (so the JPG is smaller than the PNG) with a transparent top-left quarter.
        let noise = Fixtures.noiseImage(width: 1200, height: 800)
        let ctx = CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(noise, in: CGRect(x: 0, y: 0, width: 1200, height: 800))
        ctx.clear(CGRect(x: 0, y: 400, width: 600, height: 400)) // CoreGraphics origin is bottom-left
        let input = tmp.file("logo.png")
        let dest = CGImageDestinationCreateWithURL(input as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(dest))
        #expect(pixel(input, x: 0, y: 0)[3] == 0)
        let out = try output(try await ImageCompressAction(preset: .medium).run(input: input, context: context))
        #expect(out.lastPathComponent == "logo-compressed.jpg")
        let rgba = pixel(out, x: 0, y: 0)
        #expect(rgba[0] > 240 && rgba[1] > 240 && rgba[2] > 240)
    }

    @Test func trueHEIFBecomesHEIC() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeNoiseImage(to: tmp.file("camera.hif"), type: .heic)
        // Turn the HEIC brands (major brand and the last compatible brand) into generic HEIF
        // brands, as camera .HIF files have: ftyp mif1, compatible mif1 MiHE miaf miaf.
        var data = try Data(contentsOf: input)
        data.replaceSubrange(8..<12, with: Data("mif1".utf8))
        data.replaceSubrange(28..<32, with: Data("miaf".utf8))
        try data.write(to: input)
        #expect(Fixtures.imageType(input) == .heif)
        let out = try output(try await ImageCompressAction(preset: .strong).run(input: input, context: context))
        #expect(out.lastPathComponent == "camera-compressed.heic")
        #expect(Fixtures.imageType(out) == .heic)
    }
}
