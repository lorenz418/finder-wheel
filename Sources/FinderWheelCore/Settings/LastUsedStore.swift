import Foundation

/// Remembers the last option chosen for a verb, per classification.
public final class LastUsedStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ verb: Verb, _ classification: Classification) -> String {
        "lastUsed.\(classification.rawValue).\(verb.rawValue)"
    }

    public func option(for entry: WheelEntry, classification: Classification) -> WheelOption {
        let fallback = entry.options.first { $0.id == entry.defaultOptionID } ?? entry.options[0]
        guard entry.remembersLastUsed, let stored = defaults.string(forKey: key(entry.verb, classification)) else { return fallback }
        return entry.options.first { $0.id == stored } ?? fallback
    }

    public func remember(optionID: String, for entry: WheelEntry, classification: Classification) {
        guard entry.remembersLastUsed else { return }
        defaults.set(optionID, forKey: key(entry.verb, classification))
    }

    /// Drops the remembered choice, so the configured default applies again.
    public func forget(_ verb: Verb, classification: Classification) {
        defaults.removeObject(forKey: key(verb, classification))
    }

    /// Drops remembered choices that an edit of a wheel made stale: for every action that was
    /// removed, or whose default, set of shown options or remember switch changed. Otherwise an
    /// earlier pick would keep overriding what Settings shows as the default.
    public func forgetChanges(from old: WheelConfiguration, to new: WheelConfiguration, type: WheelFileType) {
        for verb in Verb.allCases {
            let before = old.slot(of: verb).flatMap { old[$0] }
            let after = new.slot(of: verb).flatMap { new[$0] }
            let unchanged = before?.defaultOptionID == after?.defaultOptionID
                && before?.remembersLastUsed == after?.remembersLastUsed
                && before.map { Set($0.optionIDs) } == after.map { Set($0.optionIDs) }
            if !unchanged { forget(verb, classification: type.classification) }
        }
    }
}
