import Foundation
import AVFoundation

enum MediaExport {
    /// Opens a file as a video asset or throws the user-facing error.
    static func videoAsset(_ url: URL) async throws -> AVURLAsset {
        let asset = AVURLAsset(url: url)
        guard try await !asset.loadTracks(withMediaType: .video).isEmpty else {
            throw ActionError("No video track")
        }
        return asset
    }

    /// Runs an export session to `output`, reporting progress. Cancelling the task cancels the export.
    static func export(_ asset: AVAsset, preset: String, to output: URL, as type: AVFileType,
                       progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ActionError("This video cannot be exported")
        }
        let monitor = Task {
            for await state in session.states(updateInterval: 0.25) {
                if case .exporting(let exportProgress) = state {
                    progress(exportProgress.fractionCompleted)
                }
            }
        }
        defer { monitor.cancel() }
        do {
            try await session.export(to: output, as: type)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw ActionError("Export failed: \(error.localizedDescription)")
        }
    }
}
