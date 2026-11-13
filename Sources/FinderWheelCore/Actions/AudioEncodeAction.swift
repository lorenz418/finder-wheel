import Foundation
import UniformTypeIdentifiers

/// Convert to M4A (for audio and video inputs) and audio Compress.
public struct AudioEncodeAction: FileAction {
    let stereoBitrate: Int
    let suffix: String?
    let skipsM4AInput: Bool
    let mustBeSmaller: Bool

    public static let convert = AudioEncodeAction(stereoBitrate: 192_000, suffix: nil, skipsM4AInput: true, mustBeSmaller: false)

    public static func compress(_ preset: CompressPreset) -> AudioEncodeAction {
        let bitrate: Int
        switch preset {
        case .light: bitrate = 192_000
        case .medium, .resize: bitrate = 128_000
        case .strong: bitrate = 96_000
        }
        return AudioEncodeAction(stereoBitrate: bitrate, suffix: "compressed", skipsM4AInput: false, mustBeSmaller: true)
    }

    public func run(input: URL, context: ActionContext) async throws -> ActionOutcome {
        if skipsM4AInput {
            let type = (try? input.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            if type?.conforms(to: .mpeg4Audio) == true { return .skipped("Already M4A") }
        }
        let output = OutputNamer.fileURL(for: input, suffix: suffix, ext: "m4a")
        do {
            try await AtomicOutput.write(to: output) { temp in
                try await AudioEncoder.encodeM4A(from: input, to: temp, stereoBitrate: stereoBitrate, progress: context.progress)
                if mustBeSmaller { try SizeCheck.requireSmaller(temp, than: input) }
            }
        } catch is SizeCheck.NotSmaller {
            return .skipped(SizeCheck.skipMessage)
        }
        return .produced([output])
    }
}
