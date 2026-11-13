import Testing
import Foundation
import PDFKit
@testable import FinderWheelCore

@Suite struct PDFCompressActionTests {
    private let context = ActionContext(settings: SettingsSnapshot(), progress: { _ in })

    @Test func imageHeavyPDFGetsSmallerAndKeepsItsPages() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("scan.pdf"), pages: 2, imageHeavy: true)
        let outcome = try await PDFCompressAction(preset: .strong).run(input: input, context: context)
        let out = tmp.file("scan-compressed.pdf")
        #expect(outcome == .produced([out]))
        #expect(Fixtures.fileSize(out) < Fixtures.fileSize(input) / 2)
        #expect(Fixtures.pdfPageTexts(out) == ["Page 1", "Page 2"])
    }

    @Test func strongIsSmallerThanLight() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("scan.pdf"), pages: 1, imageHeavy: true)
        guard case .produced(let light) = try await PDFCompressAction(preset: .light).run(input: input, context: context),
              case .produced(let strong) = try await PDFCompressAction(preset: .strong).run(input: input, context: context) else {
            Issue.record("expected both presets to produce output")
            return
        }
        #expect(Fixtures.fileSize(strong[0]) < Fixtures.fileSize(light[0]))
    }

    @Test func textOnlyPDFIsSkippedOrSmaller() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("text.pdf"), pages: 3)
        switch try await PDFCompressAction(preset: .medium).run(input: input, context: context) {
        case .skipped(let reason):
            #expect(reason == "Already as small as it gets")
            #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.url.path) == ["text.pdf"])
        case .produced(let urls):
            #expect(Fixtures.fileSize(urls[0]) < Fixtures.fileSize(input))
        }
    }

    @Test func lockedPDFThrows() async throws {
        let tmp = TempFolder()
        let plain = Fixtures.writePDF(to: tmp.file("plain.pdf"), pages: 1)
        let input = tmp.file("locked.pdf")
        #expect(PDFDocument(url: plain)!.write(to: input, withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "owner"]))
        await #expect(throws: ActionError("PDF is password-protected")) {
            _ = try await PDFCompressAction(preset: .medium).run(input: input, context: context)
        }
    }

    @Test func routerKnowsPDFCompress() {
        #expect(ActionRouter.action(for: .compress(.light), fileKind: .pdf) is PDFCompressAction)
    }
}
