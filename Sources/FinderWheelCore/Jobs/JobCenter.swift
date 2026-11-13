import Foundation
import Observation

@MainActor
@Observable
public final class JobCenter {
    public struct Note: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public let file: String
        public let message: String
        public let isFailure: Bool
    }

    public enum State: Equatable, Sendable { case running, finished, cancelled }

    public struct Job: Identifiable, Sendable {
        public let id: UUID
        public let title: String
        public let total: Int
        public var done = 0
        public var currentFraction = 0.0
        public var state: State = .running
        public var outputs: [URL] = []
        public var notes: [Note] = []

        public var progress: Double {
            if state != .running { return 1 }
            guard total > 0 else { return 0 }
            return min(1, (Double(done) + currentFraction) / Double(total))
        }
    }

    /// Newest first. At most 20 are kept.
    public private(set) var jobs: [Job] = []
    public private(set) var hasWarning = false
    /// Called on the main actor with the outputs of a job that produced at least one.
    @ObservationIgnored public var onFinished: (([URL]) -> Void)?

    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let resolve: (ActionKind, FileKind) -> FileAction?
    @ObservationIgnored private let kindOf: (URL) -> FileKind

    public init(resolve: @escaping (ActionKind, FileKind) -> FileAction? = ActionRouter.action(for:fileKind:),
                kindOf: @escaping (URL) -> FileKind = { Classifier.kind(of: $0) }) {
        self.resolve = resolve
        self.kindOf = kindOf
    }

    public var isRunning: Bool { jobs.contains { $0.state == .running } }

    /// Mean progress of the running jobs, 0 when idle.
    public var overallProgress: Double {
        let running = jobs.filter { $0.state == .running }
        guard !running.isEmpty else { return 0 }
        return running.map(\.progress).reduce(0, +) / Double(running.count)
    }

    public func clearWarning() { hasWarning = false }

    /// Runs `kind` on each input in turn.
    @discardableResult
    public func start(title: String, inputs: [URL], kind: ActionKind, settings: SettingsSnapshot) -> UUID {
        let id = addJob(title: title, total: inputs.count)
        tasks[id] = Task { [weak self] in
            var stoppedEarly = false
            for (index, input) in inputs.enumerated() {
                guard let self else { return }
                if Task.isCancelled { stoppedEarly = true; break }
                let name = input.lastPathComponent
                guard let action = self.resolve(kind, self.kindOf(input)) else {
                    self.addNote(id, file: name, message: "This action is not available for this file", isFailure: true)
                    self.update(id) { $0.done += 1 }
                    continue
                }
                do {
                    switch try await action.run(input: input, context: self.context(for: id, fileIndex: index, settings: settings)) {
                    case .produced(let urls): self.update(id) { $0.outputs += urls }
                    case .skipped(let reason): self.addNote(id, file: name, message: reason, isFailure: false)
                    }
                } catch is CancellationError where Task.isCancelled {
                    stoppedEarly = true
                    break
                } catch {
                    // An action that reacts to cancellation with its own error is still a cancellation.
                    if Task.isCancelled { stoppedEarly = true; break }
                    self.addNote(id, file: name, message: error.localizedDescription, isFailure: true)
                }
                self.update(id) { $0.done += 1; $0.currentFraction = 0 }
            }
            self?.finish(id, cancelled: stoppedEarly)
        }
        return id
    }

    /// Runs one operation over the whole selection (used by Combine). It returns the outputs.
    @discardableResult
    public func startBatch(title: String, settings: SettingsSnapshot,
                           operation: @escaping @Sendable (ActionContext) async throws -> [URL]) -> UUID {
        let id = addJob(title: title, total: 1)
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            var stoppedEarly = false
            do {
                let urls = try await operation(self.context(for: id, fileIndex: 0, settings: settings))
                self.update(id) { $0.outputs += urls }
            } catch is CancellationError where Task.isCancelled {
                stoppedEarly = true
            } catch {
                if Task.isCancelled {
                    stoppedEarly = true
                } else {
                    self.addNote(id, file: title, message: error.localizedDescription, isFailure: true)
                }
            }
            self.finish(id, cancelled: stoppedEarly)
        }
        return id
    }

    public func cancel(_ id: UUID) {
        tasks[id]?.cancel()
    }

    /// Suspends until the job has ended. Used by tests.
    public func wait(_ id: UUID) async {
        await tasks[id]?.value
    }

    private func addJob(title: String, total: Int) -> UUID {
        let id = UUID()
        jobs.insert(Job(id: id, title: title, total: total), at: 0)
        // Trim the oldest finished jobs only; a running job is never dropped.
        while jobs.count > 20, let index = jobs.lastIndex(where: { $0.state != .running }) {
            jobs.remove(at: index)
        }
        return id
    }

    private func context(for id: UUID, fileIndex: Int, settings: SettingsSnapshot) -> ActionContext {
        ActionContext(settings: settings) { [weak self] fraction in
            Task { @MainActor [weak self] in
                self?.applyProgress(id, fileIndex: fileIndex, fraction: fraction)
            }
        }
    }

    /// Applies a progress report from file `fileIndex`. Reports from a file the job has already
    /// moved past are dropped, as are changes under 0.01 (except a final 1.0).
    func applyProgress(_ id: UUID, fileIndex: Int, fraction: Double) {
        let value = max(0, min(1, fraction))
        // Read first: assigning into `jobs` notifies observers even when nothing changes.
        guard let index = jobs.firstIndex(where: { $0.id == id }),
              jobs[index].state == .running,
              jobs[index].done == fileIndex,
              value == 1 ? jobs[index].currentFraction != 1 : abs(value - jobs[index].currentFraction) >= 0.01
        else { return }
        jobs[index].currentFraction = value
    }

    private func update(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].state == .running else { return }
        change(&jobs[index])
    }

    private func addNote(_ id: UUID, file: String, message: String, isFailure: Bool) {
        update(id) { $0.notes.append(Note(file: file, message: message, isFailure: isFailure)) }
        if isFailure { hasWarning = true }
    }

    private func finish(_ id: UUID, cancelled: Bool) {
        var outputs: [URL] = []
        update(id) {
            $0.state = cancelled ? .cancelled : .finished
            outputs = $0.outputs
        }
        tasks[id] = nil
        // A cancelled job keeps the files it already finished but does not reveal them.
        if !outputs.isEmpty && !cancelled { onFinished?(outputs) }
    }
}
