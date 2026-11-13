import Foundation
import AVFoundation
import UniformTypeIdentifiers

/// Convert a video to MP4.
public struct VideoConvertAction: FileAction {
    public init() {}

    public func run(input: URL, context: ActionContext) async throws -> ActionOutcome {
        let asset = try await MediaExport.videoAsset(input)
        let type = (try? input.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        if type?.conforms(to: .mpeg4Movie) == true { return .skipped("Already MP4") }
        let output = OutputNamer.fileURL(for: input, suffix: nil, ext: "mp4")
        try await AtomicOutput.write(to: output) { temp in
            try await MediaExport.export(asset, preset: AVAssetExportPresetHighestQuality, to: temp, as: .mp4,
                                         progress: context.progress)
        }
        return .produced([output])
    }
}
