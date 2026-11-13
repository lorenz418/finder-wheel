import Testing
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import FinderWheelCore

@Suite struct CutOutActionTests {
    private let context = ActionContext(settings: SettingsSnapshot(), progress: { _ in })

    @Test func producesTransparentPNGOrReportsNoSubject() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeImage(to: tmp.file("photo.jpg"), type: .jpeg, width: 800, height: 600)
        do {
            let outcome = try await CutOutAction().run(input: input, context: context)
            #expect(outcome == .produced([tmp.file("photo-cutout.png")]))
            #expect(Fixtures.imageType(tmp.file("photo-cutout.png")) == .png)
            #expect(Fixtures.imageProperties(tmp.file("photo-cutout.png"))[kCGImagePropertyHasAlpha] as? Bool == true)
        } catch let error as ActionError {
            #expect(error.message == "No subject found in this image")
            #expect(!FileManager.default.fileExists(atPath: tmp.file("photo-cutout.png").path))
        }
    }

    @Test func unreadableFileThrows() async {
        let tmp = TempFolder()
        let input = tmp.touch("broken.jpg")
        await #expect(throws: (any Error).self) {
            _ = try await CutOutAction().run(input: input, context: context)
        }
    }

    @Test func routerKnowsCutOut() {
        #expect(ActionRouter.action(for: .cutOut, fileKind: .image) is CutOutAction)
        #expect(ActionRouter.action(for: .cutOut, fileKind: .pdf) == nil)
    }

    @Test func cutsOutARealSubject() async throws {
        let source = URL(fileURLWithPath: "/Library/User Pictures/Animals/Parrot.heic")
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let tmp = TempFolder()
        let input = tmp.file("Parrot.heic")
        try Data(contentsOf: source).write(to: input)  // the system files are symlinks, so copy the bytes
        let outcome = try await CutOutAction().run(input: input, context: context)
        let output = tmp.file("Parrot-cutout.png")
        #expect(outcome == .produced([output]))
        #expect(Fixtures.imageType(output) == .png)
        #expect(Fixtures.imageProperties(output)[kCGImagePropertyHasAlpha] as? Bool == true)

        let src = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        var pixel: [UInt8] = [0, 0, 0, 0]  // start clear, so alpha 0 afterwards means the source pixel was transparent
        let ctx = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Draw so that the image's top-left pixel (0,0) lands in the single context pixel.
        ctx.draw(image, in: CGRect(x: 0, y: -(image.height - 1), width: image.width, height: image.height))
        #expect(pixel[3] == 0)
    }
}
