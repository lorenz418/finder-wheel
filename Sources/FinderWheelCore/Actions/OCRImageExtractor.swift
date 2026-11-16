import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Cuts the figures Mistral found out of the original file. Mistral returns only small
/// previews of them; rendering the same area of the PDF again gives full quality.
enum OCRImageExtractor {
    /// Resolution a PDF area is rendered at.
    static let dpi: CGFloat = 600
    /// Longest side of a rendered figure, so a full-page figure stays a reasonable size.
    static let maxPixel: CGFloat = 6000

    /// PNG data by image id, for every figure that could be cut out. Figures that are
    /// missing here (no usable position, unreadable original) fall back to Mistral's preview.
    static func images(from input: URL, isPDF: Bool, pages: [MistralClient.OCRPage]) -> [String: Data] {
        guard pages.contains(where: { !($0.images ?? []).isEmpty }) else { return [:] }
        return isPDF ? fromPDF(input, pages: pages) : fromImage(input, pages: pages)
    }

    /// The figure's rectangle in pixels of Mistral's page, top-left origin.
    private static func box(_ image: MistralClient.OCRImage) -> CGRect? {
        guard let x0 = image.topLeftX, let y0 = image.topLeftY, let x1 = image.bottomRightX, let y1 = image.bottomRightY,
              [x0, y0, x1, y1].allSatisfy(\.isFinite), x1 > x0, y1 > y0 else { return nil }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    private static func fromPDF(_ url: URL, pages: [MistralClient.OCRPage]) -> [String: Data] {
        guard let doc = PDFDocument(url: url), !doc.isLocked else { return [:] }
        var result: [String: Data] = [:]
        for ocrPage in pages {
            guard let images = ocrPage.images, !images.isEmpty, let page = doc.page(at: ocrPage.index) else { continue }
            let bounds = page.bounds(for: .cropBox)
            let sideways = page.rotation % 180 != 0
            let pageSize = sideways ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
            guard pageSize.width > 0, pageSize.height > 0 else { continue }
            // Mistral's pixels per PDF point: from the width it reports, else from its DPI
            // (200 when it reports neither).
            let pixelsPerPoint: CGFloat
            if let width = ocrPage.dimensions?.width, width > 0 {
                pixelsPerPoint = width / pageSize.width
            } else {
                let sourceDPI = ocrPage.dimensions?.dpi ?? 200
                pixelsPerPoint = (sourceDPI > 0 ? sourceDPI : 200) / 72
            }
            for image in images {
                guard let pixels = box(image) else { continue }
                let area = CGRect(x: pixels.minX / pixelsPerPoint, y: pixels.minY / pixelsPerPoint,
                                  width: pixels.width / pixelsPerPoint, height: pixels.height / pixelsPerPoint)
                    .intersection(CGRect(origin: .zero, size: pageSize))
                // Each bitmap is large; release it before the next one.
                autoreleasepool {
                    if let data = render(page, area: area, pageHeight: pageSize.height) { result[image.id] = data }
                }
            }
        }
        return result
    }

    /// Renders `area` of the page (in points, top-left origin, rotation applied) as a PNG.
    private static func render(_ page: PDFPage, area: CGRect, pageHeight: CGFloat) -> Data? {
        guard !area.isNull, area.width >= 2, area.height >= 2 else { return nil }
        let scale = min(dpi / 72, maxPixel / max(area.width, area.height))
        let width = Int((area.width * scale).rounded())
        let height = Int((area.height * scale).rounded())
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: scale, y: scale)
        // The context's origin is bottom left; move the area's bottom-left corner there.
        ctx.translateBy(x: -area.minX, y: -(pageHeight - area.maxY))
        // PDFPage.draw applies the page's rotation and box origin itself.
        page.draw(with: .cropBox, to: ctx)
        return ctx.makeImage().flatMap(png)
    }

    /// For an image that was sent itself: crops the original pixels.
    private static func fromImage(_ url: URL, pages: [MistralClient.OCRPage]) -> [String: Data] {
        guard let page = pages.first, let images = page.images,
              let sentWidth = page.dimensions?.width, let sentHeight = page.dimensions?.height, sentWidth > 0, sentHeight > 0,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [:] }
        // Mistral may or may not have applied the photo's stored rotation; use whichever
        // version has the proportions it reports, and neither if both differ.
        let upright = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 100_000,
        ] as CFDictionary)
        let stored = CGImageSourceCreateImageAtIndex(source, 0, nil)
        func matches(_ image: CGImage) -> Bool {
            abs(CGFloat(image.width) / CGFloat(image.height) - sentWidth / sentHeight) < 0.02 * sentWidth / sentHeight
        }
        guard let original = [upright, stored].compactMap({ $0 }).first(where: matches) else { return [:] }
        let scale = CGFloat(original.width) / sentWidth
        var result: [String: Data] = [:]
        for image in images {
            guard let pixels = box(image) else { continue }
            let area = CGRect(x: pixels.minX * scale, y: pixels.minY * scale, width: pixels.width * scale, height: pixels.height * scale)
                .integral.intersection(CGRect(x: 0, y: 0, width: original.width, height: original.height))
            guard !area.isNull, area.width >= 4, area.height >= 4,
                  let cropped = original.cropping(to: area), let data = png(cropped) else { continue }
            result[image.id] = data
        }
        return result
    }

    private static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}
