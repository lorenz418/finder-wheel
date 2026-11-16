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
        let pages = try MistralClient.parse(data: body, status: status)
        context.progress(0.6)
        try Task.checkCancellation()
        let cutOuts = OCRImageExtractor.images(from: input, isPDF: Classifier.kind(of: input) == .pdf, pages: pages)
        context.progress(0.9)
        try Task.checkCancellation()

        let (output, assets) = OutputNamer.fileAndFolder(for: input, ext: "md", folderSuffix: "assets")
        let (markdown, files) = Self.assemble(pages: pages, cutOuts: cutOuts, assetsName: assets.lastPathComponent)
        if !files.isEmpty {
            try AtomicOutput.write(to: assets) { temp in
                try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
                for file in files {
                    try file.data.write(to: temp.appendingPathComponent(file.name))
                }
            }
        }
        do {
            try AtomicOutput.write(to: output) { temp in
                try Data(markdown.utf8).write(to: temp)
            }
        } catch {
            // Never leave the images behind without their Markdown.
            if !files.isEmpty { try? FileManager.default.removeItem(at: assets) }
            throw error
        }
        return .produced(files.isEmpty ? [output] : [output, assets])
    }

    /// Joins the pages into one Markdown text and collects the image files it refers to.
    /// An image is the cut-out from the original where there is one, else Mistral's preview;
    /// its reference in the text is pointed at the file in the assets folder.
    static func assemble(pages: [MistralClient.OCRPage], cutOuts: [String: Data],
                         assetsName: String) -> (markdown: String, files: [(name: String, data: Data)]) {
        var files: [(name: String, data: Data)] = []
        var texts: [String] = []
        let folder = assetsName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? assetsName
        for page in pages {
            var text = page.markdown
            for image in page.images ?? [] {
                // The id is a file name such as "img-0.jpeg"; never let it point outside the folder.
                let id = (image.id as NSString).lastPathComponent
                guard !id.isEmpty, id != ".", id != ".." else { continue }
                var name: String
                let data: Data
                if let cutOut = cutOuts[image.id] {
                    name = (id as NSString).deletingPathExtension + ".png"
                    data = cutOut
                } else if let preview = image.imageBase64.flatMap(Self.decode) {
                    name = id
                    data = preview
                } else {
                    continue
                }
                if files.contains(where: { $0.name == name }) { name = "p\(page.index + 1)-\(name)" }
                guard !files.contains(where: { $0.name == name }) else { continue }
                files.append((name, data))
                let file = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
                text = text.replacingOccurrences(of: "](\(image.id))", with: "](\(folder)/\(file))")
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { texts.append(text) }
        }
        return (texts.joined(separator: "\n\n") + "\n", files)
    }

    /// Decodes plain base64 or a "data:image/jpeg;base64,..." URL.
    private static func decode(_ string: String) -> Data? {
        let payload = string.hasPrefix("data:") ? String(string[(string.firstIndex(of: ",").map(string.index(after:)) ?? string.startIndex)...]) : string
        return Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
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
