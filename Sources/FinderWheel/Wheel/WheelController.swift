import AppKit
import FinderWheelCore

/// What the user chose on the wheel.
struct WheelChoice {
    let inputs: [URL]
    let classification: Classification
    let entry: WheelEntry
    let option: WheelOption
}

/// Shows the wheel while the hotkey is held and reports the choice on release.
@MainActor
final class WheelController {
    var onChoice: ((WheelChoice) -> Void)?
    /// Called on every cursor tick so the trigger can detect a missed key release.
    var onTick: (() -> Void)?

    private let model = WheelModel()
    private lazy var panel = WheelPanel(model: model)
    private let lastUsed: LastUsedStore
    private var tracker: WheelTracker?
    private var timer: Timer?
    private var origin: NSPoint = .zero
    private var inputs: [URL] = []
    private var classification: Classification = .unsupported

    init(lastUsed: LastUsedStore) {
        self.lastUsed = lastUsed
    }

    var isShowing: Bool { timer != nil }

    func show(inputs: [URL], classification: Classification) {
        guard !isShowing else { return }
        self.inputs = inputs
        self.classification = classification
        let entries = WheelLayout.entries(for: classification, fileCount: inputs.count)

        model.entries = entries
        model.isUnsupported = entries.isEmpty
        model.summary = Self.summary(count: inputs.count, classification: classification)
        model.releaseOptionTitles = Dictionary(uniqueKeysWithValues: entries.filter { $0.options.count > 1 }.map {
            ($0.slot, lastUsed.option(for: $0, classification: classification).title)
        })
        model.hit = .none
        model.isVisible = false

        tracker = WheelTracker(optionCounts: Dictionary(uniqueKeysWithValues: entries.map { ($0.slot, $0.options.count) }),
                               metrics: model.metrics)
        origin = NSEvent.mouseLocation
        panel.show(centeredAt: origin)
        DispatchQueue.main.async { self.model.isVisible = true }

        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Hides the wheel. With `commit`, the current hit is reported through `onChoice`.
    func hide(commit: Bool) {
        guard isShowing else { return }
        timer?.invalidate()
        timer = nil
        panel.orderOut(nil)
        model.isVisible = false
        let hit = tracker?.hit ?? .none
        tracker = nil
        guard commit else { return }

        let slot: Slot
        let optionIndex: Int?
        switch hit {
        case .none: return
        case .entry(let s): slot = s; optionIndex = nil
        case .option(let s, let i): slot = s; optionIndex = i
        }
        guard let entry = model.entry(at: slot) else { return }
        let option: WheelOption
        if let optionIndex {
            option = entry.options[optionIndex]
            lastUsed.remember(optionID: option.id, for: entry, classification: classification)
        } else {
            option = lastUsed.option(for: entry, classification: classification)
        }
        onChoice?(WheelChoice(inputs: inputs, classification: classification, entry: entry, option: option))
    }

    private func tick() {
        guard var tracker else { return }
        let location = NSEvent.mouseLocation
        tracker.update(dx: location.x - origin.x, dy: location.y - origin.y)
        self.tracker = tracker
        if model.hit != tracker.hit { model.hit = tracker.hit }
        onTick?()
    }

    private static func summary(count: Int, classification: Classification) -> String {
        let noun: String
        switch classification {
        case .pdf: noun = count == 1 ? "PDF" : "PDFs"
        case .image: noun = count == 1 ? "image" : "images"
        case .video: noun = count == 1 ? "video" : "videos"
        case .audio: noun = count == 1 ? "audio file" : "audio files"
        case .videoAudio, .pdfImage, .unsupported: noun = count == 1 ? "item" : "items"
        }
        return "\(count) \(noun)"
    }
}
