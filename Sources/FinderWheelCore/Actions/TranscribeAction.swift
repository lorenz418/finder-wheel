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
        let isVideo = Classifier.kind(of: input) == .video
        let base = isVideo ? 0.2 : 0.0
        if isVideo {
            audioURL = scratch.appendingPathComponent("audio.m4a")
            try await AudioEncoder.encodeM4A(from: input, to: audioURL, stereoBitrate: 128_000) { fraction in
                context.progress(fraction * 0.2)
            }
        }
        guard let audioFile = try? AVAudioFile(forReading: audioURL) else {
            throw ActionError("Could not read audio")
        }

        let seconds = Double(audioFile.length) / audioFile.processingFormat.sampleRate
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collector = Task { () throws -> String in
            var text = ""
            for try await result in transcriber.results {
                text += String(result.text.characters)
                if seconds > 0 {
                    context.progress(base + (0.95 - base) * min(1, result.range.end.seconds / seconds))
                }
            }
            return text
        }
        do {
            // finalizeAndFinish ignores task cancellation, so stop the analyzer explicitly.
            try await withTaskCancellationHandler {
                if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                    try await analyzer.finalizeAndFinish(through: lastSample)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
            } onCancel: {
                Task { await analyzer.cancelAndFinishNow() }
            }
        } catch {
            collector.cancel()
            if Task.isCancelled { throw CancellationError() }
            throw ActionError("Transcription failed: \(error.localizedDescription)")
        }
        let transcript = try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { throw ActionError("No speech found") }
        context.progress(0.95)

        try Task.checkCancellation()
        let output = OutputNamer.fileURL(for: input, suffix: nil, ext: "md")
        try AtomicOutput.write(to: output) { temp in
            try Data((transcript + "\n").utf8).write(to: temp)
        }
        return .produced([output])
    }
}
