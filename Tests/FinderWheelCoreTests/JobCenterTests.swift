import Testing
import Foundation
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

    @Test func routerKnowsImageConvert() {
        #expect(ActionRouter.action(for: .convert(.jpg), fileKind: .image) is ImageConvertAction)
        #expect(ActionRouter.action(for: .convert(.mp4), fileKind: .image) == nil)
        #expect(ActionRouter.action(for: .convert(.jpg), fileKind: .unsupported) == nil)
    }
}
