import Testing
import Foundation
@testable import FinderWheelCore

private final class TaskBox: @unchecked Sendable {
    var task: Task<ActionOutcome, Error>?
}

@Suite struct TranscribeActionTests {
    private let english = Locale(identifier: "en_US")

    private func context(_ locale: Locale) -> ActionContext {
        ActionContext(settings: SettingsSnapshot(transcriptionLocale: locale), progress: { _ in })
    }

    /// Uses the system's English voice to create a spoken audio file.
    /// Returns false if the voice is not installed; the caller then skips the test.
    private func speak(_ text: String, to url: URL) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-v", "Samantha", "-o", url.path, text]
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: url.path)
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
        guard try speak("The quick brown fox jumps over the lazy dog.", to: input) else { return }
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

    @Test func cancelStopsTranscriptionAndWritesNothing() async throws {
        guard await SpeechModels.isInstalled(english) else { return }
        let tmp = TempFolder()
        let input = tmp.file("long.aiff")
        let sentence = "The quick brown fox jumps over the lazy dog. "
        guard try speak(String(repeating: sentence, count: 30), to: input) else { return }
        // Cancel from inside the job on the first transcription result, so the test does not depend on timing.
        let box = TaskBox()
        let ctx = ActionContext(settings: SettingsSnapshot(transcriptionLocale: english), progress: { fraction in
            if fraction > 0 { box.task?.cancel() }
        })
        let task = Task { try await TranscribeAction().run(input: input, context: ctx) }
        box.task = task
        do {
            _ = try await task.value
            Issue.record("expected the cancelled job to throw")
        } catch {
            #expect(error is CancellationError || task.isCancelled)
        }
        #expect(!FileManager.default.fileExists(atPath: tmp.file("long.md").path))
    }

    @Test func routerKnowsTranscription() {
        #expect(ActionRouter.action(for: .markdown, fileKind: .video) is TranscribeAction)
        #expect(ActionRouter.action(for: .markdown, fileKind: .audio) is TranscribeAction)
    }
}
