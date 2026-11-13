import AppKit

enum FinderSelectionError: Error {
    /// The user has not allowed Finder Wheel to control Finder.
    case notAuthorized
    case failed(String)
}

/// Reads the files currently selected in Finder. Must be called on the main thread.
final class FinderSelectionReader {
    private let script = NSAppleScript(source: """
        tell application "Finder"
            set theItems to selection as alias list
        end tell
        set thePaths to {}
        repeat with anItem in theItems
            set end of thePaths to POSIX path of anItem
        end repeat
        return thePaths
        """)!

    func read() throws -> [URL] {
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 { throw FinderSelectionError.notAuthorized }
            throw FinderSelectionError.failed(errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error \(code)")
        }
        guard result.numberOfItems > 0 else { return [] }
        return (1...result.numberOfItems).compactMap { index in
            result.atIndex(index)?.stringValue.map { URL(fileURLWithPath: $0) }
        }
    }
}
