import Testing
import Foundation
import UniformTypeIdentifiers
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
