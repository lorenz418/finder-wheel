import Foundation

/// Outputs are produced in a private temp folder and moved into place only on success,
/// so a failed or cancelled action never leaves a partial file next to the original.
public enum AtomicOutput {
    /// Calls `body` with a temp URL that has the same last path component as `final`.
    /// `body` creates a file or a folder there. On success it is moved to `final`.
    /// Throws if `final` already exists; nothing is ever overwritten.
    public static func write(to final: URL, _ body: (URL) throws -> Void) throws {
        let (dir, temp) = try makeTemp(for: final)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(temp)
        try FileManager.default.moveItem(at: temp, to: final)
    }

    public static func write(to final: URL, _ body: (URL) async throws -> Void) async throws {
        let (dir, temp) = try makeTemp(for: final)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await body(temp)
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: temp, to: final)
    }

    private static func makeTemp(for final: URL) throws -> (dir: URL, temp: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FinderWheel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, dir.appendingPathComponent(final.lastPathComponent))
    }
}
