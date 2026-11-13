import Foundation

public enum Reorder {
    /// Filename order as Finder shows it: "2" sorts before "10", case-insensitive.
    public static func naturalOrder(_ urls: [URL]) -> [URL] {
        urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Moves `item` to the position `target` currently has. Returns the list unchanged
    /// if either is missing or they are the same element.
    public static func move<T: Equatable>(_ item: T, onto target: T, in list: [T]) -> [T] {
        guard item != target,
              let from = list.firstIndex(of: item),
              let to = list.firstIndex(of: target) else { return list }
        var result = list
        result.remove(at: from)
        result.insert(item, at: to)
        return result
    }
}
