# Finder Wheel, Plan 3 of 3: Video, Audio, Transcription and Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The video and audio wheels work (Convert to MP4, GIF and M4A; Compress; Markdown by on-device transcription), settings gain the transcription language, and the wheel gets its final animation polish.

**Architecture:** Same pattern as Plan 2: one `FileAction` per job in `FinderWheelCore/Actions`, registered in `ActionRouter`. Video export goes through `AVAssetExportSession`; audio encoding through one shared `AudioEncoder` built on `AVAssetReader` and `AVAssetWriter` so the bitrate can be set; transcription through the Speech framework's `SpeechAnalyzer`.

**Tech Stack:** AVFoundation, ImageIO (GIF), Speech (`SpeechAnalyzer`, `SpeechTranscriber`, `AssetInventory`), SwiftUI.

**Spec:** `docs/superpowers/specs/2026-11-12-finder-wheel-design.md`
**Prerequisite:** Plans 1 and 2 are complete. The "Conventions for all three plans" section of Plan 1 applies here.

---

## API notes

Verified against the installed SDK (Xcode 27) before writing this plan:

- `SpeechTranscriber(locale:preset:)` with preset `.transcription`
- `SpeechTranscriber.supportedLocale(equivalentTo:)`, `SpeechTranscriber.supportedLocales`, `SpeechTranscriber.installedLocales` (all `async`)
- `transcriber.results` is an async sequence whose elements have `text: AttributedString`
- `analyzeSequence(from: AVAudioFile) async throws -> CMTime?`, `finalizeAndFinish(through:)`, `cancelAndFinishNow()`
- `assetInstallationRequest(supporting:) async throws -> AssetInstallationRequest?` and `AssetInstallationRequest.downloadAndInstall()`

Not verified, confirm before use and adapt the call if it differs:

- The `SpeechAnalyzer` initialiser is written below as `SpeechAnalyzer(modules: [transcriber])`, and the type that owns `assetInstallationRequest` as `AssetInventory`. Check with:
  `grep -n -E "class SpeechAnalyzer|class AssetInventory|init\(modules|init\(inputSequence" "$(xcrun --show-sdk-path)/System/Library/Frameworks/Speech.framework/Modules/Speech.swiftmodule/arm64e-apple-macos.swiftinterface"`
- `AVAssetExportSession.export(to:as:)` and `states(updateInterval:)` (macOS 15 and later). If `states` is unavailable, drop the progress monitor in `MediaExport` and call `progress(1)` when the export ends.

## File structure (added by this plan)

```
Sources/FinderWheelCore/
  Actions/MediaExport.swift          AVAssetExportSession wrapper with progress
  Actions/AudioEncoder.swift         any audio track to M4A (AAC) at a bitrate
  Actions/AudioEncodeAction.swift    Convert to M4A and audio Compress
  Actions/VideoConvertAction.swift   Convert to MP4
  Actions/VideoToGIFAction.swift
  Actions/VideoCompressAction.swift
  Actions/SpeechModels.swift         supported and installed languages, download
  Actions/TranscribeAction.swift
Tests/FinderWheelCoreTests/
  MediaFixtures.swift
  AudioEncodeActionTests.swift, VideoConvertActionTests.swift, VideoToGIFActionTests.swift,
  VideoCompressActionTests.swift, TranscribeActionTests.swift
README.md
```

Modified: `Jobs/ActionRouter.swift`, `Settings/SettingsView.swift`, `Wheel/WheelView.swift`, `Wheel/WheelController.swift`, `docs/manual-checks.md`.

---

### Task 1: Media test fixtures

**Files:**
- Create: `Tests/FinderWheelCoreTests/MediaFixtures.swift`

- [ ] **Step 1: Write the fixtures**

```swift
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
                           noisy: Bool = false, silent: Bool = false) async throws -> URL {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("FinderWheelMedia-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let videoOnly = silent ? url : scratch.appendingPathComponent("video.mov")
        try await writeVideoTrack(to: videoOnly, seconds: seconds, width: width, height: height, noisy: noisy)
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
        let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
        try await session.export(to: url, as: .mov)
        return url
    }

    private static func writeVideoTrack(to url: URL, seconds: Int, width: Int, height: Int, noisy: Bool) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
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
```

- [ ] **Step 2: Add a self-check test at the bottom of the same file**

```swift
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
```

- [ ] **Step 3: Run it**

Run: `swift test --filter MediaFixturesTests`
Expected: PASS. If `session.export(to:as:)` does not exist in this SDK, see the API notes at the top and use the older `session.outputURL`, `session.outputFileType` and `await session.export()` here and in Task 3.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Add media test fixtures"
```

---

### Task 2: Audio encoder, Convert to M4A and audio Compress

Behaviour:
- `AudioEncoder.encodeM4A` writes the first audio track of any file as AAC in an M4A container, 44.1 kHz, mono or stereo (more channels are mixed down to stereo). The bitrate given is for stereo; mono uses half.
- Convert to M4A (`AudioEncodeAction.convert`): 192 kbps, output `<name>.m4a`. An input that is already M4A is skipped with "Already M4A". Works on videos (extracts the audio) and audio files.
- Audio Compress (`AudioEncodeAction.compress(preset)`): 192, 128, 96 kbps for light, medium, strong; output `<name>-compressed.m4a`; never skipped for being M4A; skipped with "Already as small as it gets" if not smaller.
- A file without an audio track fails with "No audio track".

**Files:**
- Create: `Sources/FinderWheelCore/Actions/AudioEncoder.swift`
- Create: `Sources/FinderWheelCore/Actions/AudioEncodeAction.swift`
- Create: `Tests/FinderWheelCoreTests/AudioEncodeActionTests.swift`
- Modify: `Sources/FinderWheelCore/Jobs/ActionRouter.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
import AVFoundation
import UniformTypeIdentifiers
@testable import FinderWheelCore

@Suite struct AudioEncodeActionTests {
    private let context = ActionContext(settings: SettingsSnapshot(), progress: { _ in })

    @Test func convertsWAVToM4A() async throws {
        let tmp = TempFolder()
        let input = try MediaFixtures.writeTone(to: tmp.file("memo.wav"))
        let outcome = try await AudioEncodeAction.convert.run(input: input, context: context)
        let out = tmp.file("memo.m4a")
        #expect(outcome == .produced([out]))
        #expect(Classifier.kind(of: out) == .audio)
        #expect(abs(try await MediaFixtures.duration(out) - 3) < 0.2)
        #expect(Fixtures.fileSize(out) < Fixtures.fileSize(input))
    }

    @Test func convertsMonoInput() async throws {
        let tmp = TempFolder()
        let input = try MediaFixtures.writeTone(to: tmp.file("mono.wav"), channels: 1)
        let outcome = try await AudioEncodeAction.convert.run(input: input, context: context)
        #expect(outcome == .produced([tmp.file("mono.m4a")]))
    }

    @Test func convertSkipsM4A() async throws {
        let tmp = TempFolder()
        let wav = try MediaFixtures.writeTone(to: tmp.file("memo.wav"))
        _ = try await AudioEncodeAction.convert.run(input: wav, context: context)
        let outcome = try await AudioEncodeAction.convert.run(input: tmp.file("memo.m4a"), context: context)
        #expect(outcome == .skipped("Already M4A"))
    }

    @Test func extractsAudioFromVideo() async throws {
        let tmp = TempFolder()
        let input = try await MediaFixtures.writeVideo(to: tmp.file("clip.mov"))
        let outcome = try await AudioEncodeAction.convert.run(input: input, context: context)
        let out = tmp.file("clip.m4a")
        #expect(outcome == .produced([out]))
        #expect(try await MediaFixtures.trackCount(out, .audio) == 1)
        #expect(try await MediaFixtures.trackCount(out, .video) == 0)
    }

    @Test func videoWithoutAudioFails() async throws {
        let tmp = TempFolder()
        let input = try await MediaFixtures.writeVideo(to: tmp.file("silent.mov"), silent: true)
        await #expect(throws: ActionError("No audio track")) {
            _ = try await AudioEncodeAction.convert.run(input: input, context: context)
        }
        #expect(!FileManager.default.fileExists(atPath: tmp.file("silent.m4a").path))
    }

    @Test func compressWritesSmallerM4AAndStrongerIsSmaller() async throws {
        let tmp = TempFolder()
        let input = try MediaFixtures.writeTone(to: tmp.file("memo.wav"), seconds: 6)
        guard case .produced(let light) = try await AudioEncodeAction.compress(.light).run(input: input, context: context),
              case .produced(let strong) = try await AudioEncodeAction.compress(.strong).run(input: input, context: context) else {
            Issue.record("expected both presets to produce output")
            return
        }
        #expect(light[0].lastPathComponent == "memo-compressed.m4a")
        #expect(strong[0].lastPathComponent == "memo-compressed-2.m4a")
        #expect(Fixtures.fileSize(light[0]) < Fixtures.fileSize(input))
        #expect(Fixtures.fileSize(strong[0]) < Fixtures.fileSize(light[0]))
    }

    @Test func compressAcceptsM4AInput() async throws {
        let tmp = TempFolder()
        let wav = try MediaFixtures.writeTone(to: tmp.file("memo.wav"), seconds: 6)
        _ = try await AudioEncodeAction.convert.run(input: wav, context: context)
        switch try await AudioEncodeAction.compress(.strong).run(input: tmp.file("memo.m4a"), context: context) {
        case .produced(let urls): #expect(Fixtures.fileSize(urls[0]) < Fixtures.fileSize(tmp.file("memo.m4a")))
        case .skipped(let reason): #expect(reason == "Already as small as it gets")
        }
    }

    @Test func routerKnowsAudioActions() {
        #expect(ActionRouter.action(for: .convert(.m4a), fileKind: .audio) is AudioEncodeAction)
        #expect(ActionRouter.action(for: .convert(.m4a), fileKind: .video) is AudioEncodeAction)
        #expect(ActionRouter.action(for: .compress(.medium), fileKind: .audio) is AudioEncodeAction)
        #expect(ActionRouter.action(for: .convert(.mp4), fileKind: .audio) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AudioEncodeActionTests`
Expected: FAIL to compile, "cannot find 'AudioEncodeAction' in scope".

- [ ] **Step 3: Implement `AudioEncoder.swift`**

```swift
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

        do {
            while let sample = readerOutput.copyNextSampleBuffer() {
                try Task.checkCancellation()
                while !writerInput.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(5))
                }
                guard writerInput.append(sample) else { throw ActionError("Could not encode audio") }
                if duration > 0 {
                    progress(min(1, CMSampleBufferGetPresentationTimeStamp(sample).seconds / duration))
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
```

- [ ] **Step 4: Implement `AudioEncodeAction.swift`**

```swift
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
```

- [ ] **Step 5: Register in `ActionRouter`**

```swift
        case (.convert(.m4a), .audio), (.convert(.m4a), .video):
            return AudioEncodeAction.convert
        case (.compress(let preset), .audio):
            return AudioEncodeAction.compress(preset)
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter AudioEncodeActionTests`
Expected: PASS, 8 tests.

If `writer.startWriting()` fails for mono input, the AAC encoder rejected the bitrate: use `max(64_000, stereoBitrate * channels / 2)` for the mono case and re-run.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add audio encoder, convert to M4A and audio compress"
```

---

### Task 3: Convert video to MP4 and Compress video

Behaviour:
- Convert to MP4: re-exports with the system's highest-quality preset into an MP4 container, output `<name>.mp4`. An input that is already MP4 is skipped with "Already MP4".
- Video Compress (spec presets): light, medium, strong use the system export presets 1920x1080, 1280x720, 960x540 (these never upscale), output `<name>-compressed.mp4`; skipped with "Already as small as it gets" if not smaller.
- A file without a video track fails with "No video track".
- Progress comes from the export session.

**Files:**
- Create: `Sources/FinderWheelCore/Actions/MediaExport.swift`
- Create: `Sources/FinderWheelCore/Actions/VideoConvertAction.swift`
- Create: `Sources/FinderWheelCore/Actions/VideoCompressAction.swift`
- Create: `Tests/FinderWheelCoreTests/VideoConvertActionTests.swift`
- Create: `Tests/FinderWheelCoreTests/VideoCompressActionTests.swift`
- Modify: `Sources/FinderWheelCore/Jobs/ActionRouter.swift`

- [ ] **Step 1: Write the failing tests**

`VideoConvertActionTests.swift`:

```swift
import Testing
import Foundation
import UniformTypeIdentifiers
@testable import FinderWheelCore

@Suite struct VideoConvertActionTests {
    private let context = ActionContext(settings: SettingsSnapshot(), progress: { _ in })

    @Test func convertsMOVToMP4() async throws {
        let tmp = TempFolder()
        let input = try await MediaFixtures.writeVideo(to: tmp.file("clip.mov"))
        let outcome = try await VideoConvertAction().run(input: input, context: context)
        let out = tmp.file("clip.mp4")
        #expect(outcome == .produced([out]))
        #expect(try out.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .mpeg4Movie) == true)
        #expect(abs(try await MediaFixtures.duration(out) - 2) < 0.3)
        #expect(try await MediaFixtures.trackCount(out, .video) == 1)
        #expect(try await MediaFixtures.trackCount(out, .audio) == 1)
        #expect(FileManager.default.fileExists(atPath: input.path))
    }

    @Test func skipsMP4Input() async throws {
        let tmp = TempFolder()
        let mov = try await MediaFixtures.writeVideo(to: tmp.file("clip.mov"))
        _ = try await VideoConvertAction().run(input: mov, context: context)
        let outcome = try await VideoConvertAction().run(input: tmp.file("clip.mp4"), context: context)
        #expect(outcome == .skipped("Already MP4"))
    }

    @Test func audioFileHasNoVideoTrack() async throws {
        let tmp = TempFolder()
        let input = try MediaFixtures.writeTone(to: tmp.file("memo.wav"))
        await #expect(throws: ActionError("No video track")) {
            _ = try await VideoConvertAction().run(input: input, context: context)
        }
    }

    @Test func routerKnowsVideoConvert() {
        #expect(ActionRouter.action(for: .convert(.mp4), fileKind: .video) is VideoConvertAction)
        #expect(ActionRouter.action(for: .compress(.strong), fileKind: .video) is VideoCompressAction)
    }
}
```

`VideoCompressActionTests.swift`:

```swift
import Testing
import Foundation
@testable import FinderWheelCore

@Suite struct VideoCompressActionTests {
    private let context = ActionContext(settings: SettingsSnapshot(), progress: { _ in })

    @Test func strongPresetShrinksANoisy720pClip() async throws {
        let tmp = TempFolder()
        let input = try await MediaFixtures.writeVideo(to: tmp.file("clip.mov"), seconds: 2, width: 1280, height: 720, noisy: true)
        let outcome = try await VideoCompressAction(preset: .strong).run(input: input, context: context)
        let out = tmp.file("clip-compressed.mp4")
        #expect(outcome == .produced([out]))
        #expect(Fixtures.fileSize(out) < Fixtures.fileSize(input))
        let size = try await MediaFixtures.videoSize(out)
        #expect(size.width == 960)
        #expect(size.height == 540)
    }

    @Test func smallFlatClipIsSkippedOrSmaller() async throws {
        let tmp = TempFolder()
        let input = try await MediaFixtures.writeVideo(to: tmp.file("tiny.mov"), seconds: 1, width: 320, height: 240)
        switch try await VideoCompressAction(preset: .light).run(input: input, context: context) {
        case .skipped(let reason):
            #expect(reason == "Already as small as it gets")
            #expect(!FileManager.default.fileExists(atPath: tmp.file("tiny-compressed.mp4").path))
        case .produced(let urls):
            #expect(Fixtures.fileSize(urls[0]) < Fixtures.fileSize(input))
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "VideoConvertActionTests|VideoCompressActionTests"`
Expected: FAIL to compile, "cannot find 'VideoConvertAction' in scope".

- [ ] **Step 3: Implement `MediaExport.swift`**

```swift
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
```

- [ ] **Step 4: Implement `VideoConvertAction.swift`**

```swift
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
```

- [ ] **Step 5: Implement `VideoCompressAction.swift`**

```swift
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
```

- [ ] **Step 6: Register in `ActionRouter`**

```swift
        case (.convert(.mp4), .video):
            return VideoConvertAction()
        case (.compress(let preset), .video):
            return VideoCompressAction(preset: preset)
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `swift test --filter "VideoConvertActionTests|VideoCompressActionTests"`
Expected: PASS, 6 tests.

If `strongPresetShrinksANoisy720pClip` reports a size other than 960x540, the export preset kept a different aspect; assert `size.height <= 540` instead and keep the size comparison.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Add video convert and video compress actions"
```

---

### Task 4: Video to GIF

Behaviour (spec presets): 480 px wide, 12 frames per second, loops forever, output `<name>.gif`. Height follows the video's aspect ratio and orientation. A file without a video track fails with "No video track".

Known limitation of the first version, to be listed in the README: the whole video is converted, so long videos make very large GIFs.

**Files:**
- Create: `Sources/FinderWheelCore/Actions/VideoToGIFAction.swift`
- Create: `Tests/FinderWheelCoreTests/VideoToGIFActionTests.swift`
- Modify: `Sources/FinderWheelCore/Jobs/ActionRouter.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import FinderWheelCore

@Suite struct VideoToGIFActionTests {
    private let context = ActionContext(settings: SettingsSnapshot(), progress: { _ in })

    @Test func writesALoopingGIFAt12FPSAnd480Wide() async throws {
        let tmp = TempFolder()
        let input = try await MediaFixtures.writeVideo(to: tmp.file("clip.mov"), seconds: 2, width: 640, height: 480)
        let outcome = try await VideoToGIFAction().run(input: input, context: context)
        let out = tmp.file("clip.gif")
        #expect(outcome == .produced([out]))
        let source = try #require(CGImageSourceCreateWithURL(out as CFURL, nil))
        #expect(UTType(CGImageSourceGetType(source)! as String) == .gif)
        #expect(abs(CGImageSourceGetCount(source) - 24) <= 1)
        let size = Fixtures.pixelSize(out)
        #expect(size.width == 480)
        #expect(size.height == 360)
        let fileProps = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let gifProps = fileProps?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        #expect(gifProps?[kCGImagePropertyGIFLoopCount] as? Int == 0)
        let frameProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let frameGIF = frameProps?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let delay = frameGIF?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? 0
        #expect(abs(delay - 1.0 / 12) < 0.02)
    }

    @Test func audioFileHasNoVideoTrack() async throws {
        let tmp = TempFolder()
        let input = try MediaFixtures.writeTone(to: tmp.file("memo.wav"))
        await #expect(throws: ActionError("No video track")) {
            _ = try await VideoToGIFAction().run(input: input, context: context)
        }
    }

    @Test func routerKnowsGIF() {
        #expect(ActionRouter.action(for: .convert(.gif), fileKind: .video) is VideoToGIFAction)
        #expect(ActionRouter.action(for: .convert(.gif), fileKind: .image) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter VideoToGIFActionTests`
Expected: FAIL to compile, "cannot find 'VideoToGIFAction' in scope".

- [ ] **Step 3: Implement `VideoToGIFAction.swift`**

```swift
import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

public struct VideoToGIFAction: FileAction {
    static let width: CGFloat = 480
    static let framesPerSecond = 12

    public init() {}

    public func run(input: URL, context: ActionContext) async throws -> ActionOutcome {
        let asset = try await MediaExport.videoAsset(input)
        let duration = try await asset.load(.duration).seconds
        let frameCount = max(1, Int((duration * Double(Self.framesPerSecond)).rounded()))

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // Aspect-fit into a box that is 480 wide and tall enough never to be the limit.
        generator.maximumSize = CGSize(width: Self.width, height: Self.width * 8)
        let tolerance = CMTime(value: 1, timescale: CMTimeScale(Self.framesPerSecond * 2))
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let output = OutputNamer.fileURL(for: input, suffix: nil, ext: "gif")
        try await AtomicOutput.write(to: output) { temp in
            guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
                throw ActionError("Could not write GIF")
            }
            CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(Self.framesPerSecond)]] as CFDictionary
            for frame in 0..<frameCount {
                try Task.checkCancellation()
                let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(Self.framesPerSecond))
                let image = try await generator.image(at: time).image
                CGImageDestinationAddImage(dest, image, frameProps)
                context.progress(Double(frame + 1) / Double(frameCount))
            }
            guard CGImageDestinationFinalize(dest) else { throw ActionError("Could not write GIF") }
        }
        return .produced([output])
    }
}
```

- [ ] **Step 4: Register in `ActionRouter`**

```swift
        case (.convert(.gif), .video):
            return VideoToGIFAction()
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter VideoToGIFActionTests`
Expected: PASS, 3 tests.

If the last frame fails with a "cannot decode" error because its time equals the duration, clamp the request: use `min(time, lastFrameTime)` where `lastFrameTime` is the duration minus one frame.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add video to GIF action"
```

---

### Task 5: Transcription

Behaviour:
- Markdown on a video or audio file transcribes it on device in the language from settings and writes `<name>.md` with the transcript.
- A language with no on-device support fails with "Transcription is not available for <language>".
- A supported language whose model is not installed fails with "Speech model for <language> is not installed. Download it in Settings." (Task 6 adds the download button.)
- A file with no recognisable speech fails with "No speech found".
- Videos have their audio extracted to a temporary M4A first; audio files are read directly.

**Files:**
- Create: `Sources/FinderWheelCore/Actions/SpeechModels.swift`
- Create: `Sources/FinderWheelCore/Actions/TranscribeAction.swift`
- Create: `Tests/FinderWheelCoreTests/TranscribeActionTests.swift`
- Modify: `Sources/FinderWheelCore/Jobs/ActionRouter.swift`

- [ ] **Step 1: Confirm the two unverified API names**

Run the `grep` from "API notes" at the top of this plan. Note the exact `SpeechAnalyzer` initialiser and the name of the type that declares `assetInstallationRequest(supporting:)`. Use those in Steps 4 and 5 if they differ from the code below.

- [ ] **Step 2: Write the failing tests**

The speech tests need the English model. They decide at run time what to expect, so the suite passes on a Mac without the model too.

```swift
import Testing
import Foundation
@testable import FinderWheelCore

@Suite struct TranscribeActionTests {
    private let english = Locale(identifier: "en_US")

    private func context(_ locale: Locale) -> ActionContext {
        ActionContext(settings: SettingsSnapshot(transcriptionLocale: locale), progress: { _ in })
    }

    /// Uses the system voice to create a spoken audio file.
    private func speak(_ text: String, to url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-v", "Samantha", "-o", url.path, text]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test func languageNamesAreReadable() {
        #expect(SpeechModels.displayName(for: Locale(identifier: "de_DE")).contains("German") ||
                SpeechModels.displayName(for: Locale(identifier: "de_DE")).contains("Deutsch"))
    }

    @Test func supportedLocalesIncludeEnglish() async {
        let locales = await SpeechModels.supportedLocales()
        #expect(locales.contains { $0.language.languageCode?.identifier == "en" })
    }

    @Test func transcribesSpeechOrReportsMissingModel() async throws {
        let tmp = TempFolder()
        let input = tmp.file("note.aiff")
        try speak("The quick brown fox jumps over the lazy dog.", to: input)
        if await SpeechModels.isInstalled(english) {
            let outcome = try await TranscribeAction().run(input: input, context: context(english))
            #expect(outcome == .produced([tmp.file("note.md")]))
            let text = try String(contentsOf: tmp.file("note.md"), encoding: .utf8).lowercased()
            #expect(text.contains("quick brown fox"))
            #expect(text.hasSuffix("\n"))
        } else {
            do {
                _ = try await TranscribeAction().run(input: input, context: context(english))
                Issue.record("expected a missing-model error")
            } catch let error as ActionError {
                #expect(error.message.contains("is not installed. Download it in Settings."))
            }
        }
    }

    @Test func toneHasNoSpeech() async throws {
        guard await SpeechModels.isInstalled(english) else { return }
        let tmp = TempFolder()
        let input = try MediaFixtures.writeTone(to: tmp.file("tone.wav"))
        await #expect(throws: ActionError("No speech found")) {
            _ = try await TranscribeAction().run(input: input, context: context(english))
        }
        #expect(!FileManager.default.fileExists(atPath: tmp.file("tone.md").path))
    }

    @Test func routerKnowsTranscription() {
        #expect(ActionRouter.action(for: .markdown, fileKind: .video) is TranscribeAction)
        #expect(ActionRouter.action(for: .markdown, fileKind: .audio) is TranscribeAction)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter TranscribeActionTests`
Expected: FAIL to compile, "cannot find 'SpeechModels' in scope".

- [ ] **Step 4: Implement `SpeechModels.swift`**

```swift
import Foundation
import Speech

/// On-device speech models: which languages exist, which are installed, and installing one.
public enum SpeechModels {
    /// Readable language name in the user's language, for example "German (Germany)".
    public static func displayName(for locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    /// All languages the on-device transcriber supports, sorted by display name.
    public static func supportedLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales.sorted { displayName(for: $0) < displayName(for: $1) }
    }

    /// The supported locale matching `locale`, or nil if the language has no on-device model.
    public static func supported(_ locale: Locale) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: locale)
    }

    public static func isInstalled(_ locale: Locale) async -> Bool {
        guard let match = await supported(locale) else { return false }
        let id = match.identifier(.bcp47)
        return await SpeechTranscriber.installedLocales.contains { $0.identifier(.bcp47) == id }
    }

    /// Downloads and installs the model for `locale`. Returns at once if nothing is needed.
    public static func install(_ locale: Locale) async throws {
        guard let match = await supported(locale) else {
            throw ActionError("Transcription is not available for \(displayName(for: locale))")
        }
        let transcriber = SpeechTranscriber(locale: match, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }
}
```

- [ ] **Step 5: Implement `TranscribeAction.swift`**

```swift
import Foundation
import AVFoundation
import Speech

/// Markdown for video and audio: on-device transcription.
public struct TranscribeAction: FileAction {
    public init() {}

    public func run(input: URL, context: ActionContext) async throws -> ActionOutcome {
        let requested = context.settings.transcriptionLocale
        let language = SpeechModels.displayName(for: requested)
        guard let locale = await SpeechModels.supported(requested) else {
            throw ActionError("Transcription is not available for \(language)")
        }
        guard await SpeechModels.isInstalled(locale) else {
            throw ActionError("Speech model for \(language) is not installed. Download it in Settings.")
        }

        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("FinderWheelSpeech-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        // Videos: pull the audio out first. Audio files are read as they are.
        var audioURL = input
        if Classifier.kind(of: input) == .video {
            audioURL = scratch.appendingPathComponent("audio.m4a")
            try await AudioEncoder.encodeM4A(from: input, to: audioURL, stereoBitrate: 128_000) { fraction in
                context.progress(fraction * 0.2)
            }
        }
        guard let audioFile = try? AVAudioFile(forReading: audioURL) else {
            throw ActionError("Could not read audio")
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collector = Task { () throws -> String in
            var text = ""
            for try await result in transcriber.results {
                text += String(result.text.characters)
            }
            return text
        }
        do {
            if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            collector.cancel()
            if Task.isCancelled { throw CancellationError() }
            throw ActionError("Transcription failed: \(error.localizedDescription)")
        }
        let transcript = try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { throw ActionError("No speech found") }
        context.progress(0.95)

        let output = OutputNamer.fileURL(for: input, suffix: nil, ext: "md")
        try AtomicOutput.write(to: output) { temp in
            try Data((transcript + "\n").utf8).write(to: temp)
        }
        return .produced([output])
    }
}
```

- [ ] **Step 6: Register in `ActionRouter`**

```swift
        case (.markdown, .video), (.markdown, .audio):
            return TranscribeAction()
```

`ActionRouter` is now complete. Its switch should contain exactly these cases, in any order, followed by `default: return nil`:

| `ActionKind` | `FileKind` | Action |
|---|---|---|
| `.markdown` | `.pdf`, `.image` | `MarkdownOCRAction()` |
| `.markdown` | `.video`, `.audio` | `TranscribeAction()` |
| `.convert(jpg/png/heic/tiff)` | `.image` | `ImageConvertAction(target:)` |
| `.convert(png/jpg)` | `.pdf` | `PDFToImagesAction(target:)` |
| `.convert(.mp4)` | `.video` | `VideoConvertAction()` |
| `.convert(.gif)` | `.video` | `VideoToGIFAction()` |
| `.convert(.m4a)` | `.video`, `.audio` | `AudioEncodeAction.convert` |
| `.compress(preset)` | `.image` | `ImageCompressAction(preset:)` |
| `.compress(preset)` | `.pdf` | `PDFCompressAction(preset:)` |
| `.compress(preset)` | `.video` | `VideoCompressAction(preset:)` |
| `.compress(preset)` | `.audio` | `AudioEncodeAction.compress(preset)` |
| `.splitPDF` | `.pdf` | `PDFSplitAction()` |
| `.cutOut` | `.image` | `CutOutAction()` |

`.combine` has no router entry; it runs through `JobCenter.startBatch`.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `swift test --filter TranscribeActionTests`
Expected: PASS, 5 tests. On a Mac without the English model, `transcribesSpeechOrReportsMissingModel` takes the missing-model branch and `toneHasNoSpeech` returns early; after Task 6, install English from Settings and run this suite again so the real transcription path is exercised.

If the transcript is empty for the spoken file although the model is installed, the audio format may not be accepted directly: convert the input to M4A first for audio files too (the same `AudioEncoder.encodeM4A` call used for videos) and re-run.

- [ ] **Step 8: Run the whole suite**

Run: `swift test`
Expected: PASS, all suites.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Add on-device transcription action"
```

---

### Task 6: Transcription language in settings

Spec: settings contain the transcription language (default: system language); if the model for that language is not installed, the app offers to download it.

**Files:**
- Modify: `Sources/FinderWheel/Settings/SettingsView.swift`

- [ ] **Step 1: Add the section**

Add these state properties to `SettingsView`:

```swift
    @State private var locales: [Locale] = []
    @State private var modelInstalled: Bool?
    @State private var isDownloading = false
    @State private var downloadError: String?
```

Add this section to the `Form`, after the "Mistral OCR" section:

```swift
            Section("Transcription") {
                Picker("Language", selection: $settings.transcriptionLocaleID) {
                    ForEach(locales, id: \.identifier) { locale in
                        Text(SpeechModels.displayName(for: locale)).tag(locale.identifier)
                    }
                }
                HStack {
                    if isDownloading {
                        ProgressView().controlSize(.small)
                        Text("Downloading speech model…")
                    } else if modelInstalled == true {
                        Label("Speech model installed", systemImage: "checkmark.circle")
                    } else if modelInstalled == false {
                        Label("Speech model not installed", systemImage: "arrow.down.circle")
                        Spacer()
                        Button("Download") { download() }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let downloadError {
                    Text(downloadError).font(.caption).foregroundStyle(.red)
                }
                Text("Used for the Markdown action on video and audio. Transcription runs on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```

Add these modifiers after `.fixedSize(horizontal: false, vertical: true)`:

```swift
        .task {
            locales = await SpeechModels.supportedLocales()
            // Make sure the stored language is one of the picker's options.
            if let match = await SpeechModels.supported(Locale(identifier: settings.transcriptionLocaleID)) {
                if settings.transcriptionLocaleID != match.identifier { settings.transcriptionLocaleID = match.identifier }
            } else if let first = locales.first(where: { $0.language.languageCode?.identifier == "en" }) ?? locales.first {
                settings.transcriptionLocaleID = first.identifier
            }
        }
        .task(id: settings.transcriptionLocaleID) {
            modelInstalled = nil
            downloadError = nil
            modelInstalled = await SpeechModels.isInstalled(Locale(identifier: settings.transcriptionLocaleID))
        }
```

Add this method to `SettingsView`:

```swift
    private func download() {
        let locale = Locale(identifier: settings.transcriptionLocaleID)
        isDownloading = true
        downloadError = nil
        Task {
            do {
                try await SpeechModels.install(locale)
            } catch {
                downloadError = error.localizedDescription
            }
            isDownloading = false
            modelInstalled = await SpeechModels.isInstalled(locale)
        }
    }
```

- [ ] **Step 2: Build and verify by hand**

Run: `swift test && scripts/build-app.sh && open "build/Finder Wheel.app"`

1. Open Settings. The Transcription section lists languages; the system language (or English if unsupported) is selected.
2. Pick a language whose model is not installed: "Speech model not installed" and a Download button appear. Click Download: a spinner shows, then "Speech model installed".
3. Pick a language without the model and run Markdown on an audio file: the menu lists "Speech model for <language> is not installed. Download it in Settings."
4. Install English if it is not installed, then run `swift test --filter TranscribeActionTests` again. Expected: PASS, now through the real transcription path.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "Add transcription language and model download to settings"
```

---

### Task 7: Wheel polish

Spec, visual design: short, quiet appear and dismiss animations; nothing may delay the gesture; the outer ring fans out from the targeted wedge.

Changes:
1. Dismiss fades out over 0.1 s. The action still starts at the moment of release; only removing the panel from the screen is deferred.
2. The outer ring grows out of the ring edge instead of only fading.
3. The targeted wedge's label lifts slightly.
4. With "Reduce motion" on, scaling is replaced by plain fades.

**Files:**
- Modify: `Sources/FinderWheel/Wheel/WheelView.swift`
- Modify: `Sources/FinderWheel/Wheel/WheelController.swift`

- [ ] **Step 1: Fade out on dismiss in `WheelController.swift`**

In `hide(commit:)`, replace these two lines:

```swift
        panel.orderOut(nil)
        model.isVisible = false
```

with:

```swift
        model.isVisible = false
        // Let the fade finish, unless the wheel was shown again in the meantime.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, !self.isShowing else { return }
            self.panel.orderOut(nil)
        }
```

- [ ] **Step 2: Respect Reduce Motion and animate the outer ring in `WheelView.swift`**

Add to `WheelView`:

```swift
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
```

Replace `.scaleEffect(model.isVisible ? 1 : 0.9)` with:

```swift
        .scaleEffect(model.isVisible || reduceMotion ? 1 : 0.9)
```

Replace `.animation(.easeOut(duration: 0.1), value: model.hit)` with:

```swift
        .animation(.easeOut(duration: 0.1), value: model.hit)
        .animation(.spring(duration: 0.18, bounce: 0.15), value: model.expandedSlot)
```

In `optionWedge`, replace `.transition(.opacity)` with:

```swift
            .transition(reduceMotion ? .opacity : .scale(scale: 0.86).combined(with: .opacity))
```

On the option `Text` inside the `ForEach` that draws the outer-ring labels, add after `.position(...)`:

```swift
                        .transition(.opacity)
```

In `wedgeLabel`, add after `.foregroundStyle(active ? Color.white : Color.primary)`:

```swift
        .scaleEffect(active && !reduceMotion ? 1.06 : 1)
```

- [ ] **Step 3: Build and check by eye**

Run: `swift test && scripts/build-app.sh && open "build/Finder Wheel.app"`

1. The wheel fades and scales in within about a tenth of a second and fades out on release.
2. Releasing on Convert starts the conversion immediately; the result appears no later than before this task.
3. Hold, release, and hold again within a fraction of a second: the wheel appears again and stays visible.
4. Sliding onto Convert makes the outer ring grow outward from the wedge; sliding to another wedge moves it.
5. Turn on System Settings, Accessibility, Display, Reduce motion: the wheel only fades. Turn it off again.
6. Re-run check 16 of the Plan 1 list (fast flick). If outer-ring options are hit by accident, raise `ringOuter` in `WheelMetrics` by 10 and `outerRingOuter` by the same amount, update the radii used in `WheelTrackerTests` if needed, run `swift test`, and re-check.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Polish wheel animations and respect Reduce Motion"
```

---

### Task 8: README and final verification

**Files:**
- Create: `README.md`
- Modify: `docs/manual-checks.md`

- [ ] **Step 1: Write `README.md`**

```markdown
# Finder Wheel

A gesture wheel for Finder. Select files, hold ⌥Space, flick toward an action, release.

Runs on macOS 26 or later. Everything happens on your Mac except Markdown for PDFs and images, which uses the Mistral OCR API.

## Build and run

    scripts/build-app.sh
    open "build/Finder Wheel.app"

Requires Xcode 27 or later. The app lives in the menu bar; there is no Dock icon.

On first use macOS asks whether Finder Wheel may control Finder. Allow it: this is how the app reads which files are selected. Because the app is signed ad hoc, macOS asks again after each rebuild. To avoid that, sign with a development certificate:

    SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/build-app.sh

To start it at login, add the app under System Settings, General, Login Items.

## Actions

| Direction | PDF | Image | Video / audio |
|---|---|---|---|
| Up: Markdown | Mistral OCR | Mistral OCR | On-device transcript |
| Upper right: Convert | PNG, JPG (one image per page) | JPG, PNG, HEIC, TIFF | MP4, GIF, M4A |
| Lower right: Compress | Light, medium, strong | Light, medium, strong, 2000 px | Light, medium, strong |
| Lower left | Split into pages | Cut out the subject | |
| Upper left: Combine | Merge into one PDF | Into one PDF | |

Releasing on a wedge repeats your last choice. Sliding further out shows the alternatives.

Originals are never changed. Results appear next to them and are selected in Finder.

## Settings

Menu bar icon, then Settings: hotkey, Mistral API key (stored in the Keychain), transcription language, and whether location data is removed from images.

## Known limitations

- PDF Compress shrinks scanned and image-heavy PDFs; text-only PDFs are reported as "Already as small as it gets".
- Video to GIF converts the whole video. Trim long videos first.
- Markdown from Mistral keeps image references as plain links; the images themselves are not saved.
- WebP and GIF cannot be written. GIF files are not accepted as input.

## Development

    swift test

Logic and file actions are in `Sources/FinderWheelCore` and covered by tests. The app shell is in `Sources/FinderWheel`. Manual checks are in `docs/manual-checks.md`. The design is in `docs/superpowers/specs/2026-11-12-finder-wheel-design.md`.
```

- [ ] **Step 2: Append to `docs/manual-checks.md`**

```markdown
## Plan 3: video, audio, transcription, polish

Prepare: a screen recording (.mov) of 10 to 20 seconds with sound, an .mp4, a voice memo (.m4a), an .mp3 or .wav with speech, and a 1080p or larger video of a minute or more.

1. Video wheel shows Markdown, Convert and Compress; the lower-left, upper-left and bottom wedges are dimmed. The centre reads "1 video".
2. Convert (default MP4) on the .mov: `name.mp4` appears and plays in QuickTime with sound. On the .mp4: the menu lists "Already MP4".
3. Convert, outer ring GIF: `name.gif` appears; it animates in Quick Look and is 480 px wide.
4. Convert, outer ring M4A on the .mov: `name.m4a` plays the recording's sound.
5. Compress, strong on the large video: the menu bar ring advances; `name-compressed.mp4` is clearly smaller and plays.
6. Cancel a running video Compress from the menu: the job shows "Cancelled" and no `-compressed` file appears.
7. Audio wheel on the .mp3: Convert offers only M4A and writes `name.m4a`. On the voice memo: "Already M4A".
8. Audio Compress, strong on the voice memo: `name-compressed.m4a` is smaller, or the menu lists "Already as small as it gets".
9. Select the .mov and the .mp3 together: the wheel shows Markdown, Convert (M4A only, no outer ring) and Compress. Compress writes an `.mp4` for the video and an `.m4a` for the audio.
10. Markdown on the speech recording: `name.md` contains the spoken text in the language chosen in settings.
11. Markdown on the screen recording with speech: `name.md` with the transcript.
12. Markdown on a recording in a different language than the setting: change the language in settings, download its model if asked, and run again.
13. Select a PDF and a video together: all wedges dimmed, "No actions for this selection".
14. Start a long video Compress and immediately run an image Convert: both jobs appear in the menu and both finish.

## Full regression

Run the Plan 1 and Plan 2 lists again after Plan 3.
```

- [ ] **Step 3: Run everything**

Run: `swift test`
Expected: PASS, all suites.

Run: `scripts/build-app.sh && open "build/Finder Wheel.app"`
Work through all three manual lists. Fix failures at their cause, re-run `swift test`, rebuild, re-check. If a check contradicts the spec, stop and ask the user.

- [ ] **Step 4: Check the spec is fully covered**

Read `docs/superpowers/specs/2026-11-12-finder-wheel-design.md` section by section and confirm each requirement is implemented and was exercised by a test or a manual check. List anything that is not in the final commit message and tell the user.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add README and final manual checks"
```

**Plan 3 is complete when:** `swift test` passes, all three manual lists pass, and the spec walk-through found no gaps.
