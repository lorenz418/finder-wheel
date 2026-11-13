import Foundation
import AVFoundation

public struct VideoCompressAction: FileAction {
    public let preset: CompressPreset

    public init(preset: CompressPreset) { self.preset = preset }

    private var exportPreset: String {
        switch preset {
        case .light: return AVAssetExportPreset1920x1080
        case .medium, .resize: return AVAssetExportPreset1280x720
        case .strong: return AVAssetExportPreset960x540
        }
    }

    public func run(input: URL, context: ActionContext) async throws -> ActionOutcome {
        let asset = try await MediaExport.videoAsset(input)
        let output = OutputNamer.fileURL(for: input, suffix: "compressed", ext: "mp4")
        do {
            try await AtomicOutput.write(to: output) { temp in
                try await MediaExport.export(asset, preset: exportPreset, to: temp, as: .mp4, progress: context.progress)
                try SizeCheck.requireSmaller(temp, than: input)
            }
        } catch is SizeCheck.NotSmaller {
            return .skipped(SizeCheck.skipMessage)
        }
        return .produced([output])
    }
}
