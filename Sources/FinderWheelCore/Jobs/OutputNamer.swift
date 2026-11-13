import Foundation

public enum OutputNamer {
    public static func fileURL(for input: URL, suffix: String?, ext: String) -> URL {
        let stem = input.deletingPathExtension().lastPathComponent + (suffix.map { "-\($0)" } ?? "")
        return unique(directory: input.deletingLastPathComponent(), stem: stem, ext: ext)
    }

    public static func folderURL(for input: URL, suffix: String) -> URL {
        let stem = input.deletingPathExtension().lastPathComponent + "-\(suffix)"
        return unique(directory: input.deletingLastPathComponent(), stem: stem, ext: nil)
    }

    public static func pageFileName(base: String, index: Int, count: Int, ext: String) -> String {
        let width = max(2, String(count).count)
        let number = String(index + 1)
        let padded = String(repeating: "0", count: max(0, width - number.count)) + number
        return "\(base)-p\(padded).\(ext)"
    }

    private static func unique(directory: URL, stem: String, ext: String?) -> URL {
        func candidate(_ n: Int) -> URL {
            let name = n == 1 ? stem : "\(stem)-\(n)"
            // A folder gets a directory URL (trailing slash), so it equals the URL that
            // Foundation builds for the same path once the folder exists.
            guard let ext else { return directory.appendingPathComponent(name, isDirectory: true) }
            return directory.appendingPathComponent(name).appendingPathExtension(ext)
        }
        var n = 1
        while FileManager.default.fileExists(atPath: candidate(n).path) { n += 1 }
        return candidate(n)
    }
}
