import Foundation
import AVFoundation
import CoreMedia

enum AudioEncoder {
    /// Encodes the first audio track of `input` as AAC into a new M4A file at `output`.
    /// `stereoBitrate` is in bits per second for two channels; mono uses half.
    static func encodeM4A(from input: URL, to output: URL, stereoBitrate: Int,
                          progress: @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: input)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ActionError("No audio track")
        }
        let duration = try await asset.load(.duration).seconds
        let description = try await track.load(.formatDescriptions).first
        let sourceChannels = description.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame } ?? 2
        let channels = sourceChannels >= 2 ? 2 : 1

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: output, fileType: .m4a)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: stereoBitrate * channels / 2,
        ])
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)

        guard reader.startReading() else { throw ActionError("Could not read audio") }
        guard writer.startWriting() else { throw ActionError("Could not encode audio") }
        writer.startSession(atSourceTime: .zero)

        var lastReported = -1.0
        do {
            while let sample = readerOutput.copyNextSampleBuffer() {
                try Task.checkCancellation()
                while !writerInput.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(5))
                }
                guard writerInput.append(sample) else { throw ActionError("Could not encode audio") }
                if duration > 0 {
                    let fraction = min(1, CMSampleBufferGetPresentationTimeStamp(sample).seconds / duration)
                    if fraction - lastReported >= 0.01 || (fraction >= 1 && lastReported < 1) {
                        lastReported = fraction
                        progress(fraction)
                    }
                }
            }
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            throw error
        }
        writerInput.markAsFinished()
        await writer.finishWriting()
        guard reader.status == .completed, writer.status == .completed else {
            throw ActionError("Could not encode audio")
        }
    }
}
