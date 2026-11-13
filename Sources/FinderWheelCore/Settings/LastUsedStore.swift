import Foundation

/// Remembers the last option chosen for a verb, per classification.
public final class LastUsedStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ entry: WheelEntry, _ classification: Classification) -> String {
        "lastUsed.\(classification.rawValue).\(entry.verb.rawValue)"
    }

    public func option(for entry: WheelEntry, classification: Classification) -> WheelOption {
        let fallback = entry.options.first { $0.id == entry.defaultOptionID } ?? entry.options[0]
        guard entry.remembersLastUsed, let stored = defaults.string(forKey: key(entry, classification)) else { return fallback }
        return entry.options.first { $0.id == stored } ?? fallback
    }

    public func remember(optionID: String, for entry: WheelEntry, classification: Classification) {
        guard entry.remembersLastUsed else { return }
        defaults.set(optionID, forKey: key(entry, classification))
    }
}
