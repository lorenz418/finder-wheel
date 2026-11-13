import Foundation

public enum ConvertTarget: String, CaseIterable, Sendable {
    case jpg, png, heic, tiff, mp4, gif, m4a
}

public enum CompressPreset: String, CaseIterable, Sendable {
    case light, medium, strong, resize
}

/// What the user chose on the wheel. Which concrete implementation runs
/// is decided per file by `ActionRouter`, using the file's `FileKind`.
public enum ActionKind: Equatable, Sendable {
    case markdown
    case convert(ConvertTarget)
    case compress(CompressPreset)
    case splitPDF
    case cutOut
    case combine
}
