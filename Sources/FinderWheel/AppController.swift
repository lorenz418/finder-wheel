import AppKit
import SwiftUI
import FinderWheelCore

/// Owns the long-lived objects and connects them: hotkey, selection, wheel, jobs.
@MainActor
@Observable
final class AppController {
    let jobCenter = JobCenter()
    /// Non-nil when Finder automation is not allowed; shown in the menu.
    private(set) var permissionProblem: String?
    private(set) var hotkeyLabel = HotkeyCombo.optionSpace.label

    @ObservationIgnored private let trigger = HotkeyTrigger(combo: .optionSpace)
    @ObservationIgnored private let reader = FinderSelectionReader()
    @ObservationIgnored private let wheel = WheelController(lastUsed: LastUsedStore())

    init() {
        jobCenter.onFinished = { urls in
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
        trigger.onPress = { [weak self] in self?.hotkeyPressed() }
        trigger.onRelease = { [weak self] in self?.endWheel(commit: true) }
        trigger.onEscape = { [weak self] in self?.endWheel(commit: false) }
        wheel.onTick = { [weak self] in self?.trigger.pollRelease() }
        // Deferred to the next run-loop turn so nothing started by a choice (a panel, an alert)
        // runs inside the hotkey's event handler.
        wheel.onChoice = { [weak self] choice in
            DispatchQueue.main.async { self?.run(choice) }
        }
        trigger.start()
    }

    func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    /// Settings passed to every job. Plan 2 replaces this with the stored settings.
    private func settingsSnapshot() -> SettingsSnapshot {
        SettingsSnapshot()
    }

    private func hotkeyPressed() {
        let inputs: [URL]
        do {
            inputs = try reader.read()
            permissionProblem = nil
        } catch FinderSelectionError.notAuthorized {
            permissionProblem = "Finder Wheel is not allowed to read the Finder selection. Enable Finder under Finder Wheel in Automation settings."
            return
        } catch {
            NSLog("FinderWheel: could not read selection: \(error)")
            return
        }
        // Spec: with nothing selected the keystroke is consumed and nothing is shown.
        guard !inputs.isEmpty else { return }
        let classification = Classifier.classify(inputs.map { Classifier.kind(of: $0) })
        wheel.show(inputs: inputs, classification: classification)
        trigger.setEscapeEnabled(true)
    }

    private func endWheel(commit: Bool) {
        trigger.setEscapeEnabled(false)
        wheel.hide(commit: commit)
    }

    private func run(_ choice: WheelChoice) {
        let title = choice.entry.options.count > 1 ? "\(choice.entry.title): \(choice.option.title)" : choice.entry.title
        jobCenter.start(title: title, inputs: choice.inputs, kind: choice.option.action, settings: settingsSnapshot())
    }
}
