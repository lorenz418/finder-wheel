import Foundation
import UniformTypeIdentifiers

/// Markdown for PDFs and images, through Mistral OCR. The only action that uploads a file.
public struct MarkdownOCRAction: FileAction {
    private let transport: MistralClient.Transport

    public init(transport: @escaping MistralClient.Transport = MistralClient.urlSessionTransport) {
        self.transport = transport
    }

    public func run(input: URL, context: ActionContext) async throws -> ActionOutcome {
        guard let key = context.settings.mistralKey, !key.isEmpty else { throw ActionError.missingMistralKey }
        let (data, mimeType) = try Self.payload(for: input)
        let request = try MistralClient.makeRequest(apiKey: key, data: data, mimeType: mimeType)
        context.progress(0.1)
        let (body, status): (Data, Int)
        do {
            (body, status) = try await transport(request)
        } catch let error as URLError {
            throw ActionError("Could not reach Mistral: \(error.localizedDescription)")
        }
        let markdown = try MistralClient.parse(data: body, status: status)
        context.progress(0.9)
        let output = OutputNamer.fileURL(for: input, suffix: nil, ext: "md")
        try AtomicOutput.write(to: output) { temp in
            try Data(markdown.utf8).write(to: temp)
        }
        return .produced([output])
    }

    private static func payload(for input: URL) throws -> (Data, String) {
        if Classifier.kind(of: input) == .pdf {
            guard let data = try? Data(contentsOf: input) else { throw ActionError("Could not read PDF") }
            return (data, "application/pdf")
        }
        let (source, type) = try ImageIOHelper.source(for: input)
        if type.conforms(to: .jpeg) || type.conforms(to: .png) {
            guard let data = try? Data(contentsOf: input) else { throw ActionError("Could not read image") }
            return (data, type.conforms(to: .png) ? "image/png" : "image/jpeg")
        }
        return (try ImageIOHelper.jpegData(source: source), "image/jpeg")
    }
}
