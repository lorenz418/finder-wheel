import Foundation
import AppKit
import PDFKit

/// Combines PDFs and images, in the given order, into one PDF.
public struct CombineAction: Sendable {
    public init() {}

    public func run(inputs: [URL], context: ActionContext) async throws -> URL {
        guard let first = inputs.first else { throw ActionError("Nothing to combine") }
        let merged = PDFDocument()
        for (index, input) in inputs.enumerated() {
            try Task.checkCancellation()
            do {
                try Self.append(input, to: merged)
            } catch let error as ActionError {
                throw ActionError("\(input.lastPathComponent): \(error.message)")
            }
            context.progress(Double(index + 1) / Double(inputs.count + 1))
        }
        let output = OutputNamer.fileURL(for: first, suffix: "merged", ext: "pdf")
        try AtomicOutput.write(to: output) { temp in
            guard merged.write(to: temp) else { throw ActionError("Could not write PDF") }
        }
        context.progress(1)
        return output
    }

    private static func append(_ input: URL, to merged: PDFDocument) throws {
        switch Classifier.kind(of: input) {
        case .pdf:
            let doc = try PDFLoader.open(input)
            for index in 0..<doc.pageCount {
                guard let page = doc.page(at: index)?.copy() as? PDFPage else { continue }
                merged.insert(page, at: merged.pageCount)
            }
        case .image:
            guard let image = NSImage(contentsOf: input), image.size.width > 0, image.size.height > 0 else {
                throw ActionError("Could not read image")
            }
            // Fit the page to A4 in the image's orientation. Only the page size changes;
            // the pixels are embedded as they are.
            let landscape = image.size.width > image.size.height
            let box = landscape ? CGSize(width: 842, height: 595) : CGSize(width: 595, height: 842)
            let scale = min(box.width / image.size.width, box.height / image.size.height)
            image.size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            guard let page = PDFPage(image: image) else { throw ActionError("Could not read image") }
            merged.insert(page, at: merged.pageCount)
        case .video, .audio, .unsupported:
            throw ActionError("Cannot be combined into a PDF")
        }
    }
}
