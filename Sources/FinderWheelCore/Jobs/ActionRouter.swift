import Foundation

/// Maps what the user chose plus the kind of one file to the action that handles it.
/// Returns nil when the combination has no implementation.
/// Plans 2 and 3 add the remaining cases to this switch.
public enum ActionRouter {
    public static func action(for kind: ActionKind, fileKind: FileKind) -> FileAction? {
        switch (kind, fileKind) {
        case (.convert(let target), .image) where target.imageType != nil:
            return ImageConvertAction(target: target)
        case (.compress(let preset), .image):
            return ImageCompressAction(preset: preset)
        case (.cutOut, .image):
            return CutOutAction()
        default:
            return nil
        }
    }
}
