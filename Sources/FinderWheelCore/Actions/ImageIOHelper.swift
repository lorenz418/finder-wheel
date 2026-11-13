import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ImageIOHelper {
    static func source(for url: URL) throws -> (source: CGImageSource, type: UTType) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let id = CGImageSourceGetType(source),
              let type = UTType(id as String) else {
            throw ActionError("Could not read image")
        }
        return (source, type)
    }

    /// Re-encodes the first image of `source`. Metadata is carried over, minus location if asked.
    static func write(source: CGImageSource, to url: URL, type: UTType, quality: Double,
                      maxPixel: Int? = nil, stripLocation: Bool, flattenAlpha: Bool) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ActionError("This Mac cannot write \(type.preferredFilenameExtension?.uppercased() ?? "that format")")
        }
        var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        if stripLocation { props[kCGImagePropertyGPSDictionary] = kCFNull! }
        if let maxPixel { props[kCGImageDestinationImageMaxPixelSize] = maxPixel }
        if flattenAlpha { props[kCGImageDestinationBackgroundColor] = CGColor(red: 1, green: 1, blue: 1, alpha: 1) }
        CGImageDestinationAddImageFromSource(dest, source, CGImageSourceGetPrimaryImageIndex(source), props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ActionError("Could not write image") }
    }

    /// The first image of `source` as JPEG data, transparency flattened onto white.
    static func jpegData(source: CGImageSource, quality: Double = 0.9) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ActionError("Could not encode image")
        }
        let props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImageDestinationBackgroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        ]
        CGImageDestinationAddImageFromSource(dest, source, 0, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ActionError("Could not encode image") }
        return data as Data
    }
}

extension ConvertTarget {
    /// The image type for image targets, nil for media targets.
    var imageType: UTType? {
        switch self {
        case .jpg: return .jpeg
        case .png: return .png
        case .heic: return .heic
        case .tiff: return .tiff
        case .mp4, .gif, .m4a: return nil
        }
    }
}
