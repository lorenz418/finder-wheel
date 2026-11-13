import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum PDFLoader {
    /// Opens a PDF for reading, with the user-facing errors the spec asks for.
    static func open(_ url: URL) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else { throw ActionError("Could not read PDF") }
        if doc.isLocked { throw ActionError("PDF is password-protected") }
        return doc
    }
}

public struct PDFToImagesAction: FileAction {
    /// `.png` or `.jpg`.
    public let target: ConvertTarget
    static let dpi: CGFloat = 200

    public init(target: ConvertTarget) { self.target = target }

    public func run(input: URL, context: ActionContext) async throws -> ActionOutcome {
        guard target == .png || target == .jpg, let type = target.imageType else {
            throw ActionError("Cannot convert a PDF to \(target.rawValue.uppercased())")
        }
        let doc = try PDFLoader.open(input)
        let base = input.deletingPathExtension().lastPathComponent
        let folder = OutputNamer.folderURL(for: input, suffix: "pages")
        try AtomicOutput.write(to: folder) { temp in
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            for index in 0..<doc.pageCount {
                try Task.checkCancellation()
                // Each page bitmap is large; release it before the next page.
                try autoreleasepool {
                    guard let page = doc.page(at: index) else { return }
                    let name = OutputNamer.pageFileName(base: base, index: index, count: doc.pageCount, ext: target.rawValue)
                    try Self.render(page, to: temp.appendingPathComponent(name), type: type)
                }
                context.progress(Double(index + 1) / Double(doc.pageCount))
            }
        }
        return .produced([folder])
    }

    private static func render(_ page: PDFPage, to url: URL, type: UTType) throws {
        let box = page.bounds(for: .cropBox)
        let sideways = page.rotation % 180 != 0
        let pointSize = sideways ? CGSize(width: box.height, height: box.width) : box.size
        let scale = dpi / 72
        let width = Int((pointSize.width * scale).rounded())
        let height = Int((pointSize.height * scale).rounded())
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ActionError("Could not render PDF page")
        }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        // PDFPage.draw applies the page's rotation and box origin itself.
        page.draw(with: .cropBox, to: ctx)
        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ActionError("Could not render PDF page")
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ActionError("Could not write image") }
    }
}
