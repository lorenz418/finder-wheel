import Testing
import Foundation
import PDFKit
import UniformTypeIdentifiers
@testable import FinderWheelCore

@Suite struct PDFToImagesActionTests {
    private let context = ActionContext(settings: SettingsSnapshot(), progress: { _ in })

    private func names(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    @Test func rendersEveryPageIntoAFolder() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("report.pdf"), pages: 3)
        let outcome = try await PDFToImagesAction(target: .png).run(input: input, context: context)
        let folder = tmp.file("report-pages")
        #expect(outcome == .produced([folder]))
        #expect(try names(in: folder) == ["report-p01.png", "report-p02.png", "report-p03.png"])
        #expect(Fixtures.imageType(folder.appendingPathComponent("report-p01.png")) == .png)
    }

    @Test func rendersAt200DPI() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("a.pdf"), pages: 1)
        _ = try await PDFToImagesAction(target: .jpg).run(input: input, context: context)
        let size = Fixtures.pixelSize(tmp.file("a-pages/a-p01.jpg"))
        // A4 is 595 x 842 pt; at 200 dpi that is 1653 x 2339 px.
        #expect(size.width == 1653)
        #expect(size.height == 2339)
        #expect(Fixtures.imageType(tmp.file("a-pages/a-p01.jpg")) == .jpeg)
    }

    @Test func rotatedPagesAreRenderedRotated() async throws {
        let tmp = TempFolder()
        let plain = Fixtures.writePDF(to: tmp.file("plain.pdf"), pages: 1)
        let doc = PDFDocument(url: plain)!
        doc.page(at: 0)!.rotation = 90
        let input = tmp.file("rotated.pdf")
        #expect(doc.write(to: input))
        _ = try await PDFToImagesAction(target: .png).run(input: input, context: context)
        let size = Fixtures.pixelSize(tmp.file("rotated-pages/rotated-p01.png"))
        #expect(size.width == 2339)
        #expect(size.height == 1653)
    }

    @Test func secondRunUsesANewFolder() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("a.pdf"), pages: 1)
        _ = try await PDFToImagesAction(target: .png).run(input: input, context: context)
        let outcome = try await PDFToImagesAction(target: .png).run(input: input, context: context)
        #expect(outcome == .produced([tmp.file("a-pages-2")]))
    }

    @Test func unreadablePDFThrows() async {
        let tmp = TempFolder()
        let input = tmp.touch("broken.pdf")
        await #expect(throws: ActionError("Could not read PDF")) {
            _ = try await PDFToImagesAction(target: .png).run(input: input, context: context)
        }
    }

    @Test func lockedPDFThrows() async throws {
        let tmp = TempFolder()
        let plain = Fixtures.writePDF(to: tmp.file("plain.pdf"), pages: 1)
        let input = tmp.file("locked.pdf")
        #expect(PDFDocument(url: plain)!.write(to: input, withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "owner"]))
        await #expect(throws: ActionError("PDF is password-protected")) {
            _ = try await PDFToImagesAction(target: .png).run(input: input, context: context)
        }
    }
}
