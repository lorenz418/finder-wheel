import Foundation
import UniformTypeIdentifiers

public struct ImageCompressAction: FileAction {
    public let preset: CompressPreset

    public init(preset: CompressPreset) { self.preset = preset }

    private var quality: Double {
        switch preset {
        case .light: return 0.8
        case .medium, .resize: return 0.6
        case .strong: return 0.4
        }
    }

    public func run(input: URL, context: ActionContext) async throws -> ActionOutcome {
        let (source, sourceType) = try ImageIOHelper.source(for: input)
        // JPG, HEIC and HEIF keep their format; everything else becomes JPG.
        let keepsFormat = sourceType.conforms(to: .jpeg) || sourceType.conforms(to: .heic) || sourceType.conforms(to: .heif)
        let type: UTType = keepsFormat ? sourceType : .jpeg
        // The extension must match the content, so a JPEG named .png is not trusted by its name.
        let ext: String
        if !keepsFormat {
            ext = "jpg"
        } else if let nameType = UTType(filenameExtension: input.pathExtension), nameType.conforms(to: sourceType) {
            ext = input.pathExtension
        } else {
            // UTType.jpeg prefers "jpeg"; this app names JPEGs ".jpg".
            ext = sourceType.conforms(to: .jpeg) ? "jpg" : (sourceType.preferredFilenameExtension ?? "jpg")
        }
        let output = OutputNamer.fileURL(for: input, suffix: "compressed", ext: ext)
        do {
            try AtomicOutput.write(to: output) { temp in
                try ImageIOHelper.write(source: source, to: temp, type: type, quality: quality,
                                        maxPixel: preset == .resize ? 2000 : nil,
                                        stripLocation: context.settings.stripLocation,
                                        flattenAlpha: type.conforms(to: .jpeg))
                try SizeCheck.requireSmaller(temp, than: input)
            }
        } catch is SizeCheck.NotSmaller {
            return .skipped(SizeCheck.skipMessage)
        }
        return .produced([output])
    }
}
