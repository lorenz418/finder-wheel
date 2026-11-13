import Foundation
import PDFKit

public struct PDFSplitAction: FileAction {
    public init() {}

    public func run(input: URL, context: ActionContext) async throws -> ActionOutcome {
        let doc = try PDFLoader.open(input)
        let base = input.deletingPathExtension().lastPathComponent
        let folder = OutputNamer.folderURL(for: input, suffix: "pages")
        try AtomicOutput.write(to: folder) { temp in
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            for index in 0..<doc.pageCount {
                try Task.checkCancellation()
                guard let page = doc.page(at: index)?.copy() as? PDFPage else { continue }
                let single = PDFDocument()
                single.insert(page, at: 0)
                let name = OutputNamer.pageFileName(base: base, index: index, count: doc.pageCount, ext: "pdf")
                guard single.write(to: temp.appendingPathComponent(name)) else {
                    throw ActionError("Could not write page \(index + 1)")
                }
                context.progress(Double(index + 1) / Double(doc.pageCount))
            }
        }
        return .produced([folder])
    }
}
