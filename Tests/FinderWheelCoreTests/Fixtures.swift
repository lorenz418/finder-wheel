import Foundation
import CoreText
import PDFKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// A temp folder that is deleted when the value is released. Each test makes its own.
final class TempFolder {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("FinderWheelTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func file(_ name: String) -> URL { url.appendingPathComponent(name) }

    @discardableResult
    func touch(_ name: String) -> URL {
        let u = file(name)
        FileManager.default.createFile(atPath: u.path, contents: Data("x".utf8))
        return u
    }
}

enum Fixtures {
    /// A solid-colour bitmap with a diagonal gradient, so lossy formats have something to compress.
    static func cgImage(width: Int = 400, height: Int = 300, alpha: Bool = false) -> CGImage {
        let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
        for i in 0..<20 {
            ctx.setFillColor(red: CGFloat(i) / 20, green: 0.4, blue: 1 - CGFloat(i) / 20, alpha: 1)
            ctx.fill(CGRect(x: i * width / 20, y: 0, width: width / 20 + 1, height: height))
        }
        if alpha { ctx.clear(CGRect(x: 0, y: 0, width: width / 2, height: height / 2)) }
        return ctx.makeImage()!
    }

    /// Writes an image file. With `gps`, the file carries a location.
    @discardableResult
    static func writeImage(to url: URL, type: UTType, width: Int = 400, height: Int = 300, alpha: Bool = false, gps: Bool = false) -> URL {
        let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        var props: [CFString: Any] = [:]
        if gps {
            props[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 48.137, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 11.575, kCGImagePropertyGPSLongitudeRef: "E",
            ] as [CFString: Any]
        }
        CGImageDestinationAddImage(dest, cgImage(width: width, height: height, alpha: alpha), props as CFDictionary)
        precondition(CGImageDestinationFinalize(dest))
        return url
    }

    static func imageProperties(_ url: URL) -> [CFString: Any] {
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    static func imageType(_ url: URL) -> UTType? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let id = CGImageSourceGetType(source) else { return nil }
        return UTType(id as String)
    }

    static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
    }

    /// Pseudo-random pixels. Compresses badly, so size comparisons are meaningful.
    static func noiseImage(width: Int, height: Int) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        var seed: UInt32 = 12345
        for i in 0..<(width * height) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            bytes[i * 4] = UInt8(truncatingIfNeeded: seed >> 16)
            bytes[i * 4 + 1] = UInt8(truncatingIfNeeded: seed >> 8)
            bytes[i * 4 + 2] = UInt8((i % width) * 255 / width)
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// Writes a noisy image at the given lossy quality.
    @discardableResult
    static func writeNoiseImage(to url: URL, type: UTType, width: Int = 1200, height: Int = 800, quality: Double = 1.0) -> URL {
        let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, noiseImage(width: width, height: height),
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        precondition(CGImageDestinationFinalize(dest))
        return url
    }

    static func pixelSize(_ url: URL) -> (width: Int, height: Int) {
        let props = imageProperties(url)
        return (props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    /// Writes an A4 PDF. Page n contains the text "<label> <n>". With `imageHeavy`,
    /// every page also carries a large noisy image.
    @discardableResult
    static func writePDF(to url: URL, pages: Int, label: String = "Page", imageHeavy: Bool = false) -> URL {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
        let font = CTFontCreateWithName("Helvetica" as CFString, 48, nil)
        let image = imageHeavy ? noiseImage(width: 1400, height: 1400) : nil
        for i in 0..<pages {
            ctx.beginPDFPage(nil)
            if let image { ctx.draw(image, in: CGRect(x: 0, y: 0, width: 595, height: 595)) }
            let text = NSAttributedString(string: "\(label) \(i + 1)",
                                          attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            ctx.textPosition = CGPoint(x: 72, y: 720)
            CTLineDraw(CTLineCreateWithAttributedString(text), ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    /// The text of every page of a PDF, trimmed.
    static func pdfPageTexts(_ url: URL) -> [String] {
        guard let doc = PDFDocument(url: url) else { return [] }
        return (0..<doc.pageCount).map { (doc.page(at: $0)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}
