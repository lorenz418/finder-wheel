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

    let settings = AppSettings()
    @ObservationIgnored private let settingsWindow = SettingsWindowController()
    @ObservationIgnored private let trigger: HotkeyTrigger
    @ObservationIgnored private let reader = FinderSelectionReader()
    @ObservationIgnored private let wheel = WheelController(lastUsed: LastUsedStore())
    @ObservationIgnored private let reorder = ReorderPanelController()

    init() {
        trigger = HotkeyTrigger(combo: settings.hotkey)
        hotkeyLabel = settings.hotkey.label
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
        observeHotkey()
    }

    func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    private func settingsSnapshot() -> SettingsSnapshot {
        settings.snapshot()
    }

    func openSettings() {
        settingsWindow.show(settings: settings)
    }

    /// Re-registers the hotkey whenever the setting changes.
    private func observeHotkey() {
        withObservationTracking {
            _ = settings.hotkeyID
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.trigger.setCombo(self.settings.hotkey)
                self.hotkeyLabel = self.settings.hotkey.label
                self.observeHotkey()
            }
        }
    }

    private func hotkeyPressed() {
        guard !reorder.isShowing else { return }
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
        guard trigger.isHeld else { return }
        wheel.show(inputs: inputs, classification: classification)
        trigger.setEscapeEnabled(true)
    }

    private func endWheel(commit: Bool) {
        trigger.setEscapeEnabled(false)
        wheel.hide(commit: commit)
    }

    /// For actions that upload to Mistral: makes sure a key exists and the user has
    /// acknowledged the upload once. Returns false if the action must not start.
    private func confirmMistralUpload() -> Bool {
        guard settings.snapshot().mistralKey != nil else {
            openSettings()
            return false
        }
        let acknowledgedKey = "mistralUploadAcknowledged"
        if UserDefaults.standard.bool(forKey: acknowledgedKey) { return true }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Send files to Mistral?"
        alert.informativeText = "Markdown for PDFs and images uploads the selected files to Mistral's OCR service. Every other Finder Wheel action stays on this Mac. This notice is shown once."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        UserDefaults.standard.set(true, forKey: acknowledgedKey)
        return true
    }

    private func run(_ choice: WheelChoice) {
        let settings = settingsSnapshot()
        if choice.option.action == .combine {
            reorder.show(urls: choice.inputs, near: NSEvent.mouseLocation) { [weak self] ordered in
                guard let self, let ordered else { return }
                self.jobCenter.startBatch(title: "Combine", settings: settings) { context in
                    [try await CombineAction().run(inputs: ordered, context: context)]
                }
            }
            return
        }
        let usesMistral = choice.option.action == .markdown
            && [Classification.pdf, .image, .pdfImage].contains(choice.classification)
        if usesMistral && !confirmMistralUpload() { return }
        let title = choice.entry.options.count > 1 ? "\(choice.entry.title): \(choice.option.title)" : choice.entry.title
        jobCenter.start(title: title, inputs: choice.inputs, kind: choice.option.action, settings: settings)
    }
}
