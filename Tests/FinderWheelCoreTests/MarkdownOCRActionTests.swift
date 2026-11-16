import Testing
import Foundation
import UniformTypeIdentifiers
import CoreGraphics
import ImageIO
@testable import FinderWheelCore

/// Records the requests it receives and answers with a fixed response.
private final class TransportSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    let status: Int
    let body: String

    init(status: Int = 200, body: String = ##"{"pages":[{"index":0,"markdown":"# Hello"}]}"##) {
        self.status = status
        self.body = body
    }

    var requests: [URLRequest] { lock.withLock { recorded } }

    var transport: MistralClient.Transport {
        { [self] request in
            lock.withLock { recorded.append(request) }
            return (Data(body.utf8), status)
        }
    }

    func documentField(_ name: String) -> String? {
        guard let data = requests.first?.httpBody,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let document = json["document"] as? [String: String] else { return nil }
        return document[name]
    }
}

@Suite struct MarkdownOCRActionTests {
    private func context(key: String? = "key-1") -> ActionContext {
        ActionContext(settings: SettingsSnapshot(mistralKey: key), progress: { _ in })
    }

    @Test func writesMarkdownNextToAPDF() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("scan.pdf"), pages: 1)
        let spy = TransportSpy()
        let outcome = try await MarkdownOCRAction(transport: spy.transport).run(input: input, context: context())
        #expect(outcome == .produced([tmp.file("scan.md")]))
        #expect(try String(contentsOf: tmp.file("scan.md"), encoding: .utf8) == "# Hello\n")
        #expect(spy.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer key-1")
        #expect(spy.documentField("document_url")?.hasPrefix("data:application/pdf;base64,") == true)
    }

    /// True if the image at `url` has any pixel that is clearly not white.
    private func hasInk(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let data = { ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)); return ctx.data }() else { return false }
        let bytes = data.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * image.height)
        // Rows may be padded; look only at real pixels.
        return (0..<image.height).contains { row in
            (0..<image.width).contains { bytes[row * ctx.bytesPerRow + $0 * 4] < 128 }
        }
    }

    @Test func cutsFiguresOutOfThePDFAtHighResolution() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("my scan.pdf"), pages: 2)
        // Mistral rendered the A4 page (595 x 842 pt) at 2 px per point. On page 2, img-0 covers
        // the text line "Page 2" (72 pt from the left, about 74 to 122 pt from the top);
        // img-1 covers an empty area of the same size.
        let spy = TransportSpy(body: #"""
        {"pages":[{"index":1,"markdown":"Text\n\n![img-0.jpeg](img-0.jpeg)\n\n![blank](img-1.jpeg)",
          "images":[{"id":"img-0.jpeg","top_left_x":120,"top_left_y":140,"bottom_right_x":520,"bottom_right_y":260,"image_base64":"QUJD"},
                    {"id":"img-1.jpeg","top_left_x":120,"top_left_y":1000,"bottom_right_x":520,"bottom_right_y":1120,"image_base64":"QUJD"}],
          "dimensions":{"dpi":200,"height":1684,"width":1190}},
         {"index":0,"markdown":"# First"}]}
        """#)
        let outcome = try await MarkdownOCRAction(transport: spy.transport).run(input: input, context: context())
        let assets = tmp.url.appendingPathComponent("my scan-assets", isDirectory: true)
        #expect(outcome == .produced([tmp.file("my scan.md"), assets]))
        #expect(try String(contentsOf: tmp.file("my scan.md"), encoding: .utf8)
                == "# First\n\nText\n\n![img-0.jpeg](my%20scan-assets/img-0.png)\n\n![blank](my%20scan-assets/img-1.png)\n")
        // 200 x 60 pt at 600 DPI.
        let size = Fixtures.pixelSize(assets.appendingPathComponent("img-0.png"))
        #expect(size.width == 1667 && size.height == 500)
        #expect(Fixtures.imageType(assets.appendingPathComponent("img-0.png")) == .png)
        #expect(hasInk(assets.appendingPathComponent("img-0.png")))
        #expect(!hasInk(assets.appendingPathComponent("img-1.png")))
    }

    @Test func fallsBackToMistralsPreviewWithoutAPosition() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("scan.pdf"), pages: 1)
        let spy = TransportSpy(body: #"""
        {"pages":[{"index":0,"markdown":"![a](img-0.jpeg) ![b](img-1.jpeg)",
          "images":[{"id":"img-0.jpeg","image_base64":"data:image/jpeg;base64,QUJD"},{"id":"img-1.jpeg"}]}]}
        """#)
        _ = try await MarkdownOCRAction(transport: spy.transport).run(input: input, context: context())
        #expect(try Data(contentsOf: tmp.file("scan-assets/img-0.jpeg")) == Data("ABC".utf8))
        #expect(!FileManager.default.fileExists(atPath: tmp.file("scan-assets/img-1.jpeg").path))
        // A figure with neither a position nor a preview keeps its plain reference.
        #expect(try String(contentsOf: tmp.file("scan.md"), encoding: .utf8) == "![a](scan-assets/img-0.jpeg) ![b](img-1.jpeg)\n")
    }

    @Test func cropsFiguresOutOfAnImage() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeImage(to: tmp.file("shot.png"), type: .png, width: 400, height: 300)
        // Mistral saw the image at half size.
        let spy = TransportSpy(body: #"""
        {"pages":[{"index":0,"markdown":"![f](img-0.jpeg)",
          "images":[{"id":"img-0.jpeg","top_left_x":10,"top_left_y":20,"bottom_right_x":110,"bottom_right_y":70,"image_base64":"QUJD"}],
          "dimensions":{"dpi":200,"height":150,"width":200}}]}
        """#)
        _ = try await MarkdownOCRAction(transport: spy.transport).run(input: input, context: context())
        let size = Fixtures.pixelSize(tmp.file("shot-assets/img-0.png"))
        #expect(size.width == 200 && size.height == 100)
    }

    @Test func textWithoutFiguresMakesNoFolder() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("scan.pdf"), pages: 1)
        _ = try await MarkdownOCRAction(transport: TransportSpy().transport).run(input: input, context: context())
        #expect(!FileManager.default.fileExists(atPath: tmp.file("scan-assets").path))
    }

    @Test func markdownAndFolderAreNumberedAlike() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("scan.pdf"), pages: 1)
        try FileManager.default.createDirectory(at: tmp.file("scan-assets"), withIntermediateDirectories: true)
        let spy = TransportSpy(body: #"{"pages":[{"index":0,"markdown":"![a](img-0.jpeg)","images":[{"id":"img-0.jpeg","image_base64":"QUJD"}]}]}"#)
        let outcome = try await MarkdownOCRAction(transport: spy.transport).run(input: input, context: context())
        #expect(outcome == .produced([tmp.file("scan-2.md"), tmp.url.appendingPathComponent("scan-2-assets", isDirectory: true)]))
        #expect(try String(contentsOf: tmp.file("scan-2.md"), encoding: .utf8) == "![a](scan-2-assets/img-0.jpeg)\n")
    }

    @Test func sendsPNGAsIs() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeImage(to: tmp.file("shot.png"), type: .png)
        let spy = TransportSpy()
        _ = try await MarkdownOCRAction(transport: spy.transport).run(input: input, context: context())
        let expected = "data:image/png;base64,\(try Data(contentsOf: input).base64EncodedString())"
        #expect(spy.documentField("image_url") == expected)
    }

    @Test func reencodesOtherImageFormatsAsJPEG() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeImage(to: tmp.file("photo.heic"), type: .heic)
        let spy = TransportSpy()
        _ = try await MarkdownOCRAction(transport: spy.transport).run(input: input, context: context())
        let url = try #require(spy.documentField("image_url"))
        #expect(url.hasPrefix("data:image/jpeg;base64,"))
        let data = try #require(Data(base64Encoded: String(url.dropFirst("data:image/jpeg;base64,".count))))
        #expect(data.prefix(2) == Data([0xFF, 0xD8]))
    }

    @Test func missingKeyThrowsBeforeAnyRequest() async {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("scan.pdf"), pages: 1)
        let spy = TransportSpy()
        await #expect(throws: ActionError.missingMistralKey) {
            _ = try await MarkdownOCRAction(transport: spy.transport).run(input: input, context: context(key: nil))
        }
        #expect(spy.requests.isEmpty)
    }

    @Test func serverErrorWritesNothing() async {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("scan.pdf"), pages: 1)
        let spy = TransportSpy(status: 401, body: #"{"message":"Unauthorized"}"#)
        await #expect(throws: ActionError("Mistral: Unauthorized (HTTP 401)")) {
            _ = try await MarkdownOCRAction(transport: spy.transport).run(input: input, context: context())
        }
        #expect(!FileManager.default.fileExists(atPath: tmp.file("scan.md").path))
    }

    @Test func routerKnowsMarkdownForPDFsAndImages() {
        #expect(ActionRouter.action(for: .markdown, fileKind: .pdf) is MarkdownOCRAction)
        #expect(ActionRouter.action(for: .markdown, fileKind: .image) is MarkdownOCRAction)
    }
}
