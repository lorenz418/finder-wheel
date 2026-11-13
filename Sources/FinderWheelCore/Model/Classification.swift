import Foundation
import UniformTypeIdentifiers

public enum FileKind: Hashable, Sendable {
    case pdf, image, video, audio, unsupported
}

/// What the whole Finder selection is. Exactly one value per selection.
public enum Classification: String, CaseIterable, Sendable {
    case pdf, image, video, audio, videoAudio, pdfImage, unsupported
}

public enum Classifier {
    /// Image formats accepted as input. GIF is deliberately absent.
    static let imageTypes: [UTType] = [.jpeg, .png, .heic, .heif, .tiff, .webP]

    public static func kind(of type: UTType?, isDirectory: Bool) -> FileKind {
        guard let type, !isDirectory else { return .unsupported }
        if type.conforms(to: .pdf) { return .pdf }
        if imageTypes.contains(where: { type.conforms(to: $0) }) { return .image }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .audio) { return .audio }
        return .unsupported
    }

    public static func kind(of url: URL) -> FileKind {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey])
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension)
        return kind(of: type, isDirectory: values?.isDirectory ?? false)
    }

    public static func classify(_ kinds: [FileKind]) -> Classification {
        let set = Set(kinds)
        if set.isEmpty || set.contains(.unsupported) { return .unsupported }
        switch set {
        case [.pdf]: return .pdf
        case [.image]: return .image
        case [.video]: return .video
        case [.audio]: return .audio
        case [.video, .audio]: return .videoAudio
        case [.pdf, .image]: return .pdfImage
        default: return .unsupported
        }
    }
}
