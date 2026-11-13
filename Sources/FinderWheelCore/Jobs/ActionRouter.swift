import Foundation

/// Maps what the user chose plus the kind of one file to the action that handles it.
/// Returns nil when the combination has no implementation.
/// Each case below pairs an action kind with the file kind it applies to; anything else falls through to nil.
public enum ActionRouter {
    public static func action(for kind: ActionKind, fileKind: FileKind) -> FileAction? {
        switch (kind, fileKind) {
        case (.convert(let target), .image) where target.imageType != nil:
            return ImageConvertAction(target: target)
        case (.compress(let preset), .image):
            return ImageCompressAction(preset: preset)
        case (.cutOut, .image):
            return CutOutAction()
        case (.convert(let target), .pdf) where target == .png || target == .jpg:
            return PDFToImagesAction(target: target)
        case (.splitPDF, .pdf):
            return PDFSplitAction()
        case (.compress(let preset), .pdf):
            return PDFCompressAction(preset: preset)
        case (.markdown, .pdf), (.markdown, .image):
            return MarkdownOCRAction()
        case (.convert(.m4a), .audio), (.convert(.m4a), .video):
            return AudioEncodeAction.convert
        case (.compress(let preset), .audio):
            return AudioEncodeAction.compress(preset)
        case (.convert(.mp4), .video):
            return VideoConvertAction()
        case (.compress(let preset), .video):
            return VideoCompressAction(preset: preset)
        case (.convert(.gif), .video):
            return VideoToGIFAction()
        case (.markdown, .video), (.markdown, .audio):
            return TranscribeAction()
        default:
            return nil
        }
    }
}
