import Foundation
import ImageIO
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
        // JPEG and HEIC keep their format, HEIF is written as HEIC (ImageIO cannot write public.heif),
        // and everything else becomes JPG. Only formats this Mac can write are kept.
        let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        let isHEIF = sourceType.conforms(to: .heif) && !sourceType.conforms(to: .heic)
        let target: UTType = isHEIF ? .heic : sourceType
        let keepsFormat = (target.conforms(to: .jpeg) || target.conforms(to: .heic))
            && writable.contains(target.identifier)
        let type: UTType = keepsFormat ? target : .jpeg
        // The extension must match the content, so a JPEG named .png is not trusted by its name.
        let ext: String
        if !keepsFormat {
            ext = "jpg"
        } else if let nameType = UTType(filenameExtension: input.pathExtension), nameType.conforms(to: target) {
            ext = input.pathExtension
        } else {
            // UTType.jpeg prefers "jpeg"; this app names JPEGs ".jpg".
            ext = target.conforms(to: .jpeg) ? "jpg" : (target.preferredFilenameExtension ?? "jpg")
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
