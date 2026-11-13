import Testing
import Foundation
import PDFKit
@testable import FinderWheelCore

@Suite struct PDFSplitActionTests {
    private let context = ActionContext(settings: SettingsSnapshot(), progress: { _ in })

    @Test func writesOnePDFPerPage() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("report.pdf"), pages: 3)
        let outcome = try await PDFSplitAction().run(input: input, context: context)
        let folder = tmp.file("report-pages")
        #expect(outcome == .produced([folder]))
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names == ["report-p01.pdf", "report-p02.pdf", "report-p03.pdf"])
        #expect(Fixtures.pdfPageTexts(folder.appendingPathComponent("report-p02.pdf")) == ["Page 2"])
        #expect(Fixtures.pdfPageTexts(input).count == 3)
    }

    @Test func lockedPDFThrows() async throws {
        let tmp = TempFolder()
        let plain = Fixtures.writePDF(to: tmp.file("plain.pdf"), pages: 2)
        let input = tmp.file("locked.pdf")
        #expect(PDFDocument(url: plain)!.write(to: input, withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "owner"]))
        await #expect(throws: ActionError("PDF is password-protected")) {
            _ = try await PDFSplitAction().run(input: input, context: context)
        }
    }

    @Test func routerKnowsPDFPageActions() {
        #expect(ActionRouter.action(for: .splitPDF, fileKind: .pdf) is PDFSplitAction)
        #expect(ActionRouter.action(for: .convert(.png), fileKind: .pdf) is PDFToImagesAction)
        #expect(ActionRouter.action(for: .convert(.jpg), fileKind: .pdf) is PDFToImagesAction)
        #expect(ActionRouter.action(for: .convert(.heic), fileKind: .pdf) == nil)
        #expect(ActionRouter.action(for: .splitPDF, fileKind: .image) == nil)
    }
}
