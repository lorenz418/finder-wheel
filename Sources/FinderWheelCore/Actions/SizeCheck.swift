import Foundation

/// Used by the Compress actions: an output that is not smaller than its input is discarded.
enum SizeCheck {
    struct NotSmaller: Error {}

    static let skipMessage = "Already as small as it gets"

    static func requireSmaller(_ output: URL, than input: URL) throws {
        let outSize = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        let inSize = try input.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        if outSize >= inSize { throw NotSmaller() }
    }
}
