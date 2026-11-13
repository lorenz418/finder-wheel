import Foundation
import AVFoundation
import CoreMedia
import CoreVideo

enum MediaFixtures {
    /// A WAV file with a 440 Hz tone.
    @discardableResult
    static func writeTone(to url: URL, seconds: Double = 3, channels: AVAudioChannelCount = 2) throws -> URL {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: channels)!
        let frames = AVAudioFrameCount(44_100 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            let samples = buffer.floatChannelData![channel]
            for i in 0..<Int(frames) {
                samples[i] = sin(Float(i) * 2 * .pi * 440 / 44_100) * 0.5
            }
        }
        // The file is closed when `file` goes out of scope.
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        return url
    }

    /// A QuickTime movie with a video track and, unless `silent`, a tone as its audio track.
    /// `noisy` fills frames with random pixels so the file is large enough to compress.
    @discardableResult
    static func writeVideo(to url: URL, seconds: Int = 2, width: Int = 640, height: Int = 480,
                           noisy: Bool = false, silent: Bool = false,
                           codec: AVVideoCodecType = .h264) async throws -> URL {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("FinderWheelMedia-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let videoOnly = silent ? url : scratch.appendingPathComponent("video.mov")
        try await writeVideoTrack(to: videoOnly, seconds: seconds, width: width, height: height, noisy: noisy, codec: codec)
        if silent { return url }

        let tone = try writeTone(to: scratch.appendingPathComponent("tone.wav"), seconds: Double(seconds))
        let videoAsset = AVURLAsset(url: videoOnly)
        let audioAsset = AVURLAsset(url: tone)
        let range = CMTimeRange(start: .zero, duration: try await videoAsset.load(.duration))
        let composition = AVMutableComposition()
        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try videoTrack.insertTimeRange(range, of: try await videoAsset.loadTracks(withMediaType: .video)[0], at: .zero)
        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try audioTrack.insertTimeRange(range, of: try await audioAsset.loadTracks(withMediaType: .audio)[0], at: .zero)
        let session = AVAssetExportSession(asset: composition, presetName: codec == .h264 ? AVAssetExportPresetHighestQuality : AVAssetExportPresetPassthrough)!
        try await session.export(to: url, as: .mov)
        return url
    }

    private static func writeVideoTrack(to url: URL, seconds: Int, width: Int, height: Int, noisy: Bool,
                                        codec: AVVideoCodecType) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        let fps: Int32 = 10
        var seed: UInt32 = 99
        for frame in 0..<(seconds * Int(fps)) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var created: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &created)
            let buffer = created!
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let count = CVPixelBufferGetDataSize(buffer)
            if noisy {
                for i in 0..<count {
                    seed = seed &* 1_664_525 &+ 1_013_904_223
                    base[i] = UInt8(truncatingIfNeeded: seed >> 16)
                }
            } else {
                memset(base, Int32(40 + frame * 8 % 200), count)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    static func duration(_ url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    static func trackCount(_ url: URL, _ type: AVMediaType) async throws -> Int {
        try await AVURLAsset(url: url).loadTracks(withMediaType: type).count
    }

    static func videoSize(_ url: URL) async throws -> CGSize {
        guard let track = try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first else { return .zero }
        return try await track.load(.naturalSize)
    }
}

import Testing

@Suite struct MediaFixturesTests {
    @Test func fixturesAreValidMedia() async throws {
        let tmp = TempFolder()
        let tone = try MediaFixtures.writeTone(to: tmp.file("tone.wav"))
        #expect(abs(try await MediaFixtures.duration(tone) - 3) < 0.1)
        let video = try await MediaFixtures.writeVideo(to: tmp.file("clip.mov"))
        #expect(abs(try await MediaFixtures.duration(video) - 2) < 0.3)
        #expect(try await MediaFixtures.trackCount(video, .video) == 1)
        #expect(try await MediaFixtures.trackCount(video, .audio) == 1)
        let silent = try await MediaFixtures.writeVideo(to: tmp.file("silent.mov"), silent: true)
        #expect(try await MediaFixtures.trackCount(silent, .audio) == 0)
    }
}
