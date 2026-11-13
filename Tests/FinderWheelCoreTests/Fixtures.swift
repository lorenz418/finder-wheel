import Foundation
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
}
