import Foundation

public struct ActionContext: Sendable {
    public let settings: SettingsSnapshot
    /// Report progress for the current file, 0 to 1. Safe to call from any thread.
    public let progress: @Sendable (Double) -> Void

    public init(settings: SettingsSnapshot, progress: @escaping @Sendable (Double) -> Void) {
        self.settings = settings
        self.progress = progress
    }
}

public enum ActionOutcome: Equatable, Sendable {
    /// Files or folders that now exist next to the original.
    case produced([URL])
    /// Nothing was written; the reason is shown in the menu.
    case skipped(String)
}

/// A failure with a message that is shown to the user as is.
public struct ActionError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }

    public static let missingMistralKey = ActionError("Mistral API key missing. Add it in Settings.")
}

/// One action on one input file. Implementations never modify or overwrite the input
/// and write outputs through `AtomicOutput`.
public protocol FileAction: Sendable {
    func run(input: URL, context: ActionContext) async throws -> ActionOutcome
}
