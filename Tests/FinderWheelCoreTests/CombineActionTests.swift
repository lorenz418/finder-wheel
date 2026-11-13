import Testing
import Foundation
import PDFKit
import UniformTypeIdentifiers
@testable import FinderWheelCore

@Suite struct CombineActionTests {
    private let context = ActionContext(settings: SettingsSnapshot(), progress: { _ in })

    @Test func mergesPDFsInTheGivenOrder() async throws {
        let tmp = TempFolder()
        let a = Fixtures.writePDF(to: tmp.file("a.pdf"), pages: 2, label: "A")
        let b = Fixtures.writePDF(to: tmp.file("b.pdf"), pages: 1, label: "B")
        let out = try await CombineAction().run(inputs: [b, a], context: context)
        #expect(out == tmp.file("b-merged.pdf"))
        #expect(Fixtures.pdfPageTexts(out) == ["B 1", "A 1", "A 2"])
        #expect(Fixtures.pdfPageTexts(a).count == 2)
    }

    @Test func imagesBecomePages() async throws {
        let tmp = TempFolder()
        let one = Fixtures.writeImage(to: tmp.file("1.png"), type: .png, width: 400, height: 300)
        let two = Fixtures.writeImage(to: tmp.file("2.jpg"), type: .jpeg, width: 300, height: 400)
        let out = try await CombineAction().run(inputs: [one, two], context: context)
        #expect(out == tmp.file("1-merged.pdf"))
        let doc = PDFDocument(url: out)!
        #expect(doc.pageCount == 2)
        let first = doc.page(at: 0)!.bounds(for: .mediaBox)
        let second = doc.page(at: 1)!.bounds(for: .mediaBox)
        // 400 x 300 fits a landscape A4 page at 793 x 595; 300 x 400 fits portrait at 595 x 793.
        #expect(abs(first.width - 793.3) < 1)
        #expect(abs(first.height - 595) < 1)
        #expect(abs(second.width - 595) < 1)
        #expect(abs(second.height - 793.3) < 1)
    }

    @Test func mixesPDFsAndImages() async throws {
        let tmp = TempFolder()
        let pdf = Fixtures.writePDF(to: tmp.file("doc.pdf"), pages: 2)
        let image = Fixtures.writeImage(to: tmp.file("photo.jpg"), type: .jpeg)
        let out = try await CombineAction().run(inputs: [image, pdf], context: context)
        #expect(out == tmp.file("photo-merged.pdf"))
        #expect(PDFDocument(url: out)!.pageCount == 3)
    }

    @Test func singleImageBecomesAOnePagePDF() async throws {
        let tmp = TempFolder()
        let image = Fixtures.writeImage(to: tmp.file("photo.jpg"), type: .jpeg)
        let out = try await CombineAction().run(inputs: [image], context: context)
        #expect(PDFDocument(url: out)!.pageCount == 1)
    }

    @Test func lockedPDFFailsAndNamesTheFile() async throws {
        let tmp = TempFolder()
        let plain = Fixtures.writePDF(to: tmp.file("plain.pdf"), pages: 1)
        let locked = tmp.file("locked.pdf")
        #expect(PDFDocument(url: plain)!.write(to: locked, withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "owner"]))
        await #expect(throws: ActionError("locked.pdf: PDF is password-protected")) {
            _ = try await CombineAction().run(inputs: [plain, locked], context: context)
        }
        #expect(!FileManager.default.fileExists(atPath: tmp.file("plain-merged.pdf").path))
    }

    @Test func emptyInputFails() async {
        await #expect(throws: ActionError("Nothing to combine")) {
            _ = try await CombineAction().run(inputs: [], context: context)
        }
    }
}
