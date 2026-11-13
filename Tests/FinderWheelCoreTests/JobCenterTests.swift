import Testing
import Foundation
import Observation
@testable import FinderWheelCore

private struct StubAction: FileAction {
    var behaviour: @Sendable (URL, ActionContext) async throws -> ActionOutcome
    func run(input: URL, context: ActionContext) async throws -> ActionOutcome { try await behaviour(input, context) }
}

@MainActor
@Suite struct JobCenterTests {
    private let files = ["a.png", "b.png", "c.png"].map { URL(fileURLWithPath: "/tmp/\($0)") }

    private func center(_ behaviour: @escaping @Sendable (URL, ActionContext) async throws -> ActionOutcome) -> JobCenter {
        JobCenter(resolve: { _, _ in StubAction(behaviour: behaviour) }, kindOf: { _ in .image })
    }

    @Test func runsEveryFileAndCollectsOutputs() async {
        let jobs = center { url, _ in .produced([url.appendingPathExtension("out")]) }
        var finished: [URL] = []
        jobs.onFinished = { finished = $0 }
        let id = jobs.start(title: "Convert", inputs: files, kind: .convert(.jpg), settings: SettingsSnapshot())
        await jobs.wait(id)
        let job = jobs.jobs.first { $0.id == id }!
        #expect(job.state == .finished)
        #expect(job.done == 3)
        #expect(job.progress == 1)
        #expect(job.outputs.count == 3)
        #expect(finished.count == 3)
        #expect(!jobs.isRunning)
        #expect(!jobs.hasWarning)
    }

    @Test func oneFailureDoesNotStopTheBatch() async {
        let jobs = center { url, _ in
            if url.lastPathComponent == "b.png" { throw ActionError("Could not read image") }
            return .produced([url])
        }
        let id = jobs.start(title: "Convert", inputs: files, kind: .convert(.jpg), settings: SettingsSnapshot())
        await jobs.wait(id)
        let job = jobs.jobs.first { $0.id == id }!
        #expect(job.outputs.count == 2)
        #expect(job.notes.count == 1)
        #expect(job.notes[0].file == "b.png")
        #expect(job.notes[0].message == "Could not read image")
        #expect(job.notes[0].isFailure)
        #expect(jobs.hasWarning)
        jobs.clearWarning()
        #expect(!jobs.hasWarning)
    }

    @Test func skipsAreNotedButAreNotWarnings() async {
        let jobs = center { _, _ in .skipped("Already JPG") }
        var finishedCalled = false
        jobs.onFinished = { _ in finishedCalled = true }
        let id = jobs.start(title: "Convert", inputs: files, kind: .convert(.jpg), settings: SettingsSnapshot())
        await jobs.wait(id)
        let job = jobs.jobs.first { $0.id == id }!
        #expect(job.notes.count == 3)
        #expect(job.notes.allSatisfy { !$0.isFailure && $0.message == "Already JPG" })
        #expect(!jobs.hasWarning)
        #expect(!finishedCalled)
    }

    @Test func unresolvableActionIsAFailureNote() async {
        let jobs = JobCenter(resolve: { _, _ in nil }, kindOf: { _ in .image })
        let id = jobs.start(title: "Split", inputs: [files[0]], kind: .splitPDF, settings: SettingsSnapshot())
        await jobs.wait(id)
        let job = jobs.jobs.first { $0.id == id }!
        #expect(job.notes.first?.message == "This action is not available for this file")
        #expect(job.notes.first?.isFailure == true)
    }

    @Test func cancelStopsBeforeRemainingFiles() async {
        let jobs = center { url, _ in
            try await Task.sleep(for: .seconds(30))
            return .produced([url])
        }
        let id = jobs.start(title: "Convert", inputs: files, kind: .convert(.jpg), settings: SettingsSnapshot())
        #expect(jobs.isRunning)
        jobs.cancel(id)
        await jobs.wait(id)
        let job = jobs.jobs.first { $0.id == id }!
        #expect(job.state == .cancelled)
        #expect(job.outputs.isEmpty)
        #expect(job.notes.isEmpty)
    }

    @Test func batchJobReportsOutputs() async {
        let jobs = center { _, _ in .skipped("unused") }
        let out = URL(fileURLWithPath: "/tmp/merged.pdf")
        let id = jobs.startBatch(title: "Combine", settings: SettingsSnapshot()) { _ in [out] }
        await jobs.wait(id)
        let job = jobs.jobs.first { $0.id == id }!
        #expect(job.state == .finished)
        #expect(job.outputs == [out])
    }

    @Test func batchFailureIsANote() async {
        let jobs = center { _, _ in .skipped("unused") }
        let id = jobs.startBatch(title: "Combine", settings: SettingsSnapshot()) { _ in throw ActionError("PDF is password-protected") }
        await jobs.wait(id)
        let job = jobs.jobs.first { $0.id == id }!
        #expect(job.notes.first?.message == "PDF is password-protected")
        #expect(jobs.hasWarning)
    }

    @Test func routerKnowsImageActions() {
        #expect(ActionRouter.action(for: .convert(.jpg), fileKind: .image) is ImageConvertAction)
        #expect(ActionRouter.action(for: .convert(.mp4), fileKind: .image) == nil)
        #expect(ActionRouter.action(for: .convert(.jpg), fileKind: .unsupported) == nil)
        #expect(ActionRouter.action(for: .compress(.medium), fileKind: .image) is ImageCompressAction)
    }

    @Test func cancelDuringLastFileStillFinishesWhenTheFileCompletes() async throws {
        let jobs = center { url, _ in
            try? await Task.sleep(for: .milliseconds(300)) // swallows the cancellation, completes anyway
            return .produced([url])
        }
        var finished: [URL] = []
        jobs.onFinished = { finished = $0 }
        let id = jobs.start(title: "Convert", inputs: [files[0]], kind: .convert(.jpg), settings: SettingsSnapshot())
        try await Task.sleep(for: .milliseconds(50))
        jobs.cancel(id)
        await jobs.wait(id)
        let job = jobs.jobs.first { $0.id == id }!
        #expect(job.state == .finished)
        #expect(job.outputs == [files[0]])
        #expect(finished == [files[0]])
    }

    @Test func strayCancellationErrorIsAFailureNoteAndTheBatchContinues() async {
        let jobs = center { url, _ in
            if url.lastPathComponent == "b.png" { throw CancellationError() }
            return .produced([url])
        }
        let id = jobs.start(title: "Convert", inputs: files, kind: .convert(.jpg), settings: SettingsSnapshot())
        await jobs.wait(id)
        let job = jobs.jobs.first { $0.id == id }!
        #expect(job.state == .finished)
        #expect(job.outputs.count == 2)
        #expect(job.notes.count == 1)
        #expect(job.notes[0].file == "b.png")
        #expect(job.notes[0].isFailure)
    }

    @Test func jobCapNeverDropsRunningJobs() async {
        let jobs = center { url, _ in
            try await Task.sleep(for: .seconds(30))
            return .produced([url])
        }
        let ids = (0..<21).map { _ in
            jobs.start(title: "Convert", inputs: [files[0]], kind: .convert(.jpg), settings: SettingsSnapshot())
        }
        #expect(jobs.jobs.count == 21)
        #expect(jobs.jobs.allSatisfy { $0.state == .running })
        for id in ids { jobs.cancel(id) }
        for id in ids { await jobs.wait(id) }
        #expect(jobs.jobs.allSatisfy { $0.state == .cancelled })
    }

    @Test func cancelWithNonCancellationErrorIsNotAFailure() async throws {
        let jobs = center { _, _ in
            try? await Task.sleep(for: .seconds(30))
            throw ActionError("Upload cancelled")
        }
        let id = jobs.start(title: "Convert", inputs: files, kind: .convert(.jpg), settings: SettingsSnapshot())
        try await Task.sleep(for: .milliseconds(50))
        jobs.cancel(id)
        await jobs.wait(id)
        let job = jobs.jobs.first { $0.id == id }!
        #expect(job.state == .cancelled)
        #expect(job.notes.isEmpty)
        #expect(!jobs.hasWarning)
    }

    @Test func batchCancelWithNonCancellationErrorIsNotAFailure() async throws {
        let jobs = center { _, _ in .skipped("unused") }
        let id = jobs.startBatch(title: "Combine", settings: SettingsSnapshot()) { _ in
            try? await Task.sleep(for: .seconds(30))
            throw ActionError("Upload cancelled")
        }
        try await Task.sleep(for: .milliseconds(50))
        jobs.cancel(id)
        await jobs.wait(id)
        let job = jobs.jobs.first { $0.id == id }!
        #expect(job.state == .cancelled)
        #expect(job.notes.isEmpty)
        #expect(!jobs.hasWarning)
    }

    @Test func progressUpdatesAreAppliedAndJobEndsAtOne() async {
        let jobs = center { url, context in
            context.progress(0.5)
            return .produced([url])
        }
        let id = jobs.start(title: "Convert", inputs: files, kind: .convert(.jpg), settings: SettingsSnapshot())
        await jobs.wait(id)
        let job = jobs.jobs.first { $0.id == id }!
        #expect(job.done == 3)
        #expect(job.progress == 1)
    }

    @Test func lateProgressFromAnEarlierFileDoesNotLeakIntoTheNextOne() async {
        // The first file reports 0.7 from a detached task 100 ms after it returned.
        // The second file starts at fraction 0, waits 400 ms, then snapshots the job.
        final class Box: @unchecked Sendable { var fractionDuringSecondFile: Double? }
        let box = Box()
        let holder = HolderBox()
        let jobs = JobCenter(resolve: { _, _ in
            StubAction { url, context in
                if url.lastPathComponent == "a.png" {
                    let progress = context.progress
                    Task.detached {
                        try? await Task.sleep(for: .milliseconds(100))
                        progress(0.7)
                    }
                } else {
                    try? await Task.sleep(for: .milliseconds(400))
                    box.fractionDuringSecondFile = await MainActor.run { holder.jobs?.jobs.first?.currentFraction }
                }
                return .produced([url])
            }
        }, kindOf: { _ in .image })
        holder.jobs = jobs
        let id = jobs.start(title: "Convert", inputs: Array(files.prefix(2)), kind: .convert(.jpg), settings: SettingsSnapshot())
        await jobs.wait(id)
        #expect(box.fractionDuringSecondFile == 0)
        #expect(jobs.jobs.first { $0.id == id }!.progress == 1)
    }

    @Test func progressHelperIgnoresStaleIndexAndTinyChanges() async {
        let jobs = center { url, _ in
            try await Task.sleep(for: .seconds(30))
            return .produced([url])
        }
        let id = jobs.start(title: "Convert", inputs: files, kind: .convert(.jpg), settings: SettingsSnapshot())
        func fraction() -> Double { jobs.jobs.first { $0.id == id }!.currentFraction }
        jobs.applyProgress(id, fileIndex: 0, fraction: 0.4)
        #expect(fraction() == 0.4)
        jobs.applyProgress(id, fileIndex: 0, fraction: 0.405)
        #expect(fraction() == 0.4)
        jobs.applyProgress(id, fileIndex: 0, fraction: 0.45)
        #expect(fraction() == 0.45)
        jobs.applyProgress(id, fileIndex: 1, fraction: 0.9)
        #expect(fraction() == 0.45)
        jobs.applyProgress(id, fileIndex: 0, fraction: 1)
        #expect(fraction() == 1)
        jobs.cancel(id)
        await jobs.wait(id)
    }
}

extension JobCenterTests {
    @Test func droppedProgressReportsDoNotNotifyObservers() async {
        let jobs = center { url, _ in
            try await Task.sleep(for: .seconds(30))
            return .produced([url])
        }
        let id = jobs.start(title: "Convert", inputs: files, kind: .convert(.jpg), settings: SettingsSnapshot())
        jobs.applyProgress(id, fileIndex: 0, fraction: 0.4)

        func notified(_ change: () -> Void) -> Bool {
            var flag = false
            withObservationTracking { _ = jobs.jobs } onChange: { flag = true }
            change()
            return flag
        }
        #expect(!notified { jobs.applyProgress(id, fileIndex: 1, fraction: 0.9) })
        #expect(!notified { jobs.applyProgress(id, fileIndex: 0, fraction: 0.405) })
        #expect(notified { jobs.applyProgress(id, fileIndex: 0, fraction: 0.6) })
        jobs.cancel(id)
        await jobs.wait(id)
    }
}

@MainActor private final class HolderBox { var jobs: JobCenter? }
