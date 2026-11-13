import Testing
import Foundation
import ImageIO
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
}
