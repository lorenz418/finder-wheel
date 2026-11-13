# Finder Wheel, Plan 1 of 3: Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A running menu bar app where holding ⌥Space in Finder shows the glass wheel for the selection, and flicking to Convert on images converts them end to end with progress in the menu bar.

**Architecture:** One Swift package with a library target `FinderWheelCore` (all logic and file actions, fully unit-tested, no UI) and an executable target `FinderWheel` (hotkey, Finder selection, wheel panel, menu bar). A shell script wraps the executable into a `.app` bundle. The wheel is driven by a pure geometry struct and a layout table; actions share one protocol and are run by a job centre.

**Tech Stack:** Swift 6.4 toolchain (Swift 5 language mode), SwiftUI + AppKit, macOS 26 SDK (Liquid Glass `glassEffect`), Carbon hotkey API, NSAppleScript, ImageIO, Swift Testing (`swift test`).

**Spec:** `docs/superpowers/specs/2026-11-12-finder-wheel-design.md`. Read it before starting.

**Plan series:** Plan 1 (this file) covers spec build step 1. Plan 2 (`2026-11-12-finder-wheel-2-pdf-image-ocr.md`) covers steps 2 and 3. Plan 3 (`2026-11-12-finder-wheel-3-media-polish.md`) covers steps 4 and 5. Each plan ends with working software.

---

## Conventions for all three plans

- Run every command from the repository root `/Users/lorenz/Desktop/finder-wheel`.
- Run tests with `swift test`. Run one suite with `swift test --filter <SuiteName>`.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.
- Both targets compile in Swift 5 language mode to avoid strict-concurrency friction. Do not change this.
- Commit after every task with the message given. End every commit message with the line `Co-Authored-By: Claude <noreply@anthropic.com>`.
- If code from this plan does not compile because an SDK API differs, check the SDK interface before improvising. Example: `grep -n "glassEffect" "$(xcrun --show-sdk-path)/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface"`. Keep the behaviour described in the plan; change only the call.
- APIs already verified against the installed SDK (Xcode 27): `glassEffect(_:in:)`, `Glass.regular`, `Glass.tint(_:)`, `GlassEffectContainer`, `kCGImageDestinationBackgroundColor`, `kCGImageDestinationImageMaxPixelSize`.

## File structure (created by this plan)

```
Package.swift
Resources/Info.plist
scripts/build-app.sh
Sources/FinderWheelCore/
  Model/Classification.swift      FileKind, Classification, Classifier
  Model/ActionKind.swift          ConvertTarget, CompressPreset, ActionKind
  Model/WheelLayout.swift         Slot, Verb, WheelOption, WheelEntry, WheelLayout (the layout table)
  Wheel/WheelTracker.swift        WheelMetrics, WheelHit, WheelTracker (pure geometry)
  Settings/SettingsSnapshot.swift SettingsSnapshot, HotkeyCombo
  Settings/LastUsedStore.swift    remembers the last option per classification and verb
  Jobs/OutputNamer.swift          output file and folder names, collision handling
  Jobs/AtomicOutput.swift         write to a temp location, move into place on success
  Jobs/FileAction.swift           FileAction protocol, ActionContext, ActionOutcome, ActionError
  Jobs/ActionRouter.swift         ActionKind + FileKind to a FileAction
  Jobs/JobCenter.swift            runs actions, tracks progress, notes, cancel
  Actions/ImageIOHelper.swift     shared ImageIO writer
  Actions/ImageConvertAction.swift
Sources/FinderWheel/
  FinderWheelApp.swift            @main, MenuBarExtra scene
  AppController.swift             wires trigger, selection, wheel, jobs
  Trigger/HotkeyTrigger.swift     Carbon hotkey, Finder-frontmost gating, Esc
  Trigger/FinderSelectionReader.swift
  Wheel/WedgeShape.swift
  Wheel/WheelModel.swift
  Wheel/WheelView.swift
  Wheel/WheelPanel.swift
  Wheel/WheelController.swift     shows the panel, polls the cursor, resolves the choice
  MenuBar/StatusIcon.swift        draws the menu bar icon with progress ring
  MenuBar/MenuBarView.swift       job list
Tests/FinderWheelCoreTests/
  Fixtures.swift                  builds sample files in a temp folder
  ClassificationTests.swift
  WheelLayoutTests.swift
  WheelTrackerTests.swift
  LastUsedStoreTests.swift
  OutputNamerTests.swift
  ImageConvertActionTests.swift
  JobCenterTests.swift
```

---

### Task 1: Package scaffold and app bundle script

**Files:**
- Create: `Package.swift`, `Resources/Info.plist`, `scripts/build-app.sh`
- Create: `Sources/FinderWheelCore/Model/Classification.swift` (placeholder type only)
- Create: `Sources/FinderWheel/FinderWheelApp.swift`
- Create: `Tests/FinderWheelCoreTests/ClassificationTests.swift` (smoke test only)
- Modify: `.gitignore`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FinderWheel",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "FinderWheelCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "FinderWheel",
            dependencies: ["FinderWheelCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "FinderWheelCoreTests",
            dependencies: ["FinderWheelCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

- [ ] **Step 2: Write the placeholder source and smoke test**

`Sources/FinderWheelCore/Model/Classification.swift`:

```swift
import Foundation

public enum FileKind: Hashable, Sendable {
    case pdf, image, video, audio, unsupported
}
```

`Tests/FinderWheelCoreTests/ClassificationTests.swift`:

```swift
import Testing
@testable import FinderWheelCore

@Suite struct ClassificationTests {
    @Test func packageBuilds() {
        #expect(FileKind.pdf != FileKind.image)
    }
}
```

`Sources/FinderWheel/FinderWheelApp.swift`:

```swift
import SwiftUI

@main
struct FinderWheelApp: App {
    var body: some Scene {
        MenuBarExtra("Finder Wheel", systemImage: "circle.dashed") {
            Button("Quit Finder Wheel") { NSApplication.shared.terminate(nil) }
        }
    }
}
```

- [ ] **Step 3: Run the tests**

Run: `swift test`
Expected: build succeeds, `packageBuilds` passes.

- [ ] **Step 4: Write `Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.lorenz.finderwheel</string>
    <key>CFBundleName</key><string>Finder Wheel</string>
    <key>CFBundleDisplayName</key><string>Finder Wheel</string>
    <key>CFBundleExecutable</key><string>FinderWheel</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Finder Wheel reads which files are selected in Finder so it can offer actions for them.</string>
    <key>NSSpeechRecognitionUsageDescription</key><string>Finder Wheel transcribes audio and video files on this Mac.</string>
</dict>
</plist>
```

- [ ] **Step 5: Write `scripts/build-app.sh`**

```bash
#!/bin/bash
# Builds "build/Finder Wheel.app" from the Swift package.
# Set SIGN_IDENTITY to a development certificate name to keep macOS permissions
# across rebuilds; the default ad-hoc signature makes macOS ask again after each rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="build/Finder Wheel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/FinderWheel "$APP/Contents/MacOS/FinderWheel"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
```

Run: `chmod +x scripts/build-app.sh`

- [ ] **Step 6: Add build output to `.gitignore`**

Append these lines to `.gitignore`:

```
.build/
build/
```

- [ ] **Step 7: Build and launch the app**

Run: `scripts/build-app.sh && open "build/Finder Wheel.app"`
Expected: prints `Built build/Finder Wheel.app`; a dashed-circle icon appears in the menu bar; no Dock icon; the menu has "Quit Finder Wheel". Quit it from the menu.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Scaffold Swift package and app bundle script"
```

---

### Task 2: Selection classification

**Files:**
- Modify: `Sources/FinderWheelCore/Model/Classification.swift`
- Modify: `Tests/FinderWheelCoreTests/ClassificationTests.swift`

- [ ] **Step 1: Write the failing tests** (replace the file contents)

```swift
import Testing
import UniformTypeIdentifiers
@testable import FinderWheelCore

@Suite struct ClassificationTests {
    @Test func kindFromType() {
        #expect(Classifier.kind(of: .pdf, isDirectory: false) == .pdf)
        #expect(Classifier.kind(of: .jpeg, isDirectory: false) == .image)
        #expect(Classifier.kind(of: .png, isDirectory: false) == .image)
        #expect(Classifier.kind(of: .heic, isDirectory: false) == .image)
        #expect(Classifier.kind(of: .tiff, isDirectory: false) == .image)
        #expect(Classifier.kind(of: .webP, isDirectory: false) == .image)
        #expect(Classifier.kind(of: .quickTimeMovie, isDirectory: false) == .video)
        #expect(Classifier.kind(of: .mpeg4Movie, isDirectory: false) == .video)
        #expect(Classifier.kind(of: .mp3, isDirectory: false) == .audio)
        #expect(Classifier.kind(of: .mpeg4Audio, isDirectory: false) == .audio)
        #expect(Classifier.kind(of: .wav, isDirectory: false) == .audio)
    }

    @Test func unsupportedKinds() {
        #expect(Classifier.kind(of: .gif, isDirectory: false) == .unsupported)
        #expect(Classifier.kind(of: .plainText, isDirectory: false) == .unsupported)
        #expect(Classifier.kind(of: .folder, isDirectory: true) == .unsupported)
        #expect(Classifier.kind(of: nil, isDirectory: false) == .unsupported)
    }

    @Test func singleTypeSelections() {
        #expect(Classifier.classify([.pdf, .pdf]) == .pdf)
        #expect(Classifier.classify([.image]) == .image)
        #expect(Classifier.classify([.video]) == .video)
        #expect(Classifier.classify([.audio, .audio]) == .audio)
    }

    @Test func supportedMixes() {
        #expect(Classifier.classify([.pdf, .image, .image]) == .pdfImage)
        #expect(Classifier.classify([.audio, .video]) == .videoAudio)
    }

    @Test func everythingElseIsUnsupported() {
        #expect(Classifier.classify([]) == .unsupported)
        #expect(Classifier.classify([.pdf, .unsupported]) == .unsupported)
        #expect(Classifier.classify([.pdf, .video]) == .unsupported)
        #expect(Classifier.classify([.image, .audio]) == .unsupported)
        #expect(Classifier.classify([.pdf, .image, .video]) == .unsupported)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ClassificationTests`
Expected: FAIL to compile, "cannot find 'Classifier' in scope".

- [ ] **Step 3: Implement** (replace `Classification.swift`)

```swift
import Foundation
import UniformTypeIdentifiers

public enum FileKind: Hashable, Sendable {
    case pdf, image, video, audio, unsupported
}

/// What the whole Finder selection is. Exactly one value per selection.
public enum Classification: String, CaseIterable, Sendable {
    case pdf, image, video, audio, videoAudio, pdfImage, unsupported
}

public enum Classifier {
    /// Image formats accepted as input. GIF is deliberately absent.
    static let imageTypes: [UTType] = [.jpeg, .png, .heic, .tiff, .webP]

    public static func kind(of type: UTType?, isDirectory: Bool) -> FileKind {
        guard let type, !isDirectory else { return .unsupported }
        if type.conforms(to: .pdf) { return .pdf }
        if imageTypes.contains(where: { type.conforms(to: $0) }) { return .image }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .audio) { return .audio }
        return .unsupported
    }

    public static func kind(of url: URL) -> FileKind {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey])
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension)
        return kind(of: type, isDirectory: values?.isDirectory ?? false)
    }

    public static func classify(_ kinds: [FileKind]) -> Classification {
        let set = Set(kinds)
        if set.isEmpty || set.contains(.unsupported) { return .unsupported }
        switch set {
        case [.pdf]: return .pdf
        case [.image]: return .image
        case [.video]: return .video
        case [.audio]: return .audio
        case [.video, .audio]: return .videoAudio
        case [.pdf, .image]: return .pdfImage
        default: return .unsupported
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ClassificationTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add selection classification"
```

---

### Task 3: Action kinds and the wheel layout table

**Files:**
- Create: `Sources/FinderWheelCore/Model/ActionKind.swift`
- Create: `Sources/FinderWheelCore/Model/WheelLayout.swift`
- Create: `Tests/FinderWheelCoreTests/WheelLayoutTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import FinderWheelCore

@Suite struct WheelLayoutTests {
    private func verbs(_ c: Classification, count: Int = 2) -> [Slot: Verb] {
        Dictionary(uniqueKeysWithValues: WheelLayout.entries(for: c, fileCount: count).map { ($0.slot, $0.verb) })
    }
    private func entry(_ c: Classification, _ verb: Verb, count: Int = 2) -> WheelEntry? {
        WheelLayout.entries(for: c, fileCount: count).first { $0.verb == verb }
    }

    @Test func verbsKeepTheirDirection() {
        for c in Classification.allCases {
            for e in WheelLayout.entries(for: c, fileCount: 2) {
                switch e.verb {
                case .markdown: #expect(e.slot == .up)
                case .convert: #expect(e.slot == .upperRight)
                case .compress: #expect(e.slot == .lowerRight)
                case .extra: #expect(e.slot == .lowerLeft)
                case .combine: #expect(e.slot == .upperLeft)
                }
            }
        }
    }

    @Test func verbsPerClassification() {
        #expect(Set(verbs(.pdf).values) == [.markdown, .convert, .compress, .extra, .combine])
        #expect(Set(verbs(.image).values) == [.markdown, .convert, .compress, .extra, .combine])
        #expect(Set(verbs(.video).values) == [.markdown, .convert, .compress])
        #expect(Set(verbs(.audio).values) == [.markdown, .convert, .compress])
        #expect(Set(verbs(.videoAudio).values) == [.markdown, .convert, .compress])
        #expect(Set(verbs(.pdfImage).values) == [.markdown, .compress, .combine])
        #expect(WheelLayout.entries(for: .unsupported, fileCount: 1).isEmpty)
    }

    @Test func combineNeedsTwoPDFsButOneImageIsEnough() {
        #expect(entry(.pdf, .combine, count: 1) == nil)
        #expect(entry(.pdf, .combine, count: 2) != nil)
        #expect(entry(.image, .combine, count: 1) != nil)
    }

    @Test func convertOptionsAndDefaults() {
        #expect(entry(.pdf, .convert)?.options.map(\.id) == ["png", "jpg"])
        #expect(entry(.pdf, .convert)?.defaultOptionID == "png")
        #expect(entry(.image, .convert)?.options.map(\.id) == ["jpg", "png", "heic", "tiff"])
        #expect(entry(.image, .convert)?.defaultOptionID == "jpg")
        #expect(entry(.video, .convert)?.options.map(\.id) == ["mp4", "gif", "m4a"])
        #expect(entry(.video, .convert)?.defaultOptionID == "mp4")
        #expect(entry(.audio, .convert)?.options.map(\.id) == ["m4a"])
        #expect(entry(.videoAudio, .convert)?.options.map(\.id) == ["m4a"])
    }

    @Test func compressOptionsAndDefaults() {
        #expect(entry(.pdf, .compress)?.options.map(\.id) == ["light", "medium", "strong"])
        #expect(entry(.image, .compress)?.options.map(\.id) == ["light", "medium", "strong", "resize"])
        #expect(entry(.pdfImage, .compress)?.options.map(\.id) == ["light", "medium", "strong"])
        for c in [Classification.pdf, .image, .video, .audio, .videoAudio, .pdfImage] {
            #expect(entry(c, .compress)?.defaultOptionID == "medium")
        }
    }

    @Test func mixesDoNotRememberLastUsed() {
        for e in WheelLayout.entries(for: .pdfImage, fileCount: 2) { #expect(!e.remembersLastUsed) }
        for e in WheelLayout.entries(for: .videoAudio, fileCount: 2) { #expect(!e.remembersLastUsed) }
        #expect(entry(.image, .convert)?.remembersLastUsed == true)
    }

    @Test func optionsCarryActions() {
        #expect(entry(.image, .convert)?.options.first?.action == .convert(.jpg))
        #expect(entry(.pdf, .extra)?.options.first?.action == .splitPDF)
        #expect(entry(.image, .extra)?.options.first?.action == .cutOut)
        #expect(entry(.pdf, .combine)?.options.first?.action == .combine)
        #expect(entry(.video, .markdown)?.options.first?.action == .markdown)
        #expect(entry(.image, .compress)?.options.last?.action == .compress(.resize))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter WheelLayoutTests`
Expected: FAIL to compile, "cannot find 'WheelLayout' in scope".

- [ ] **Step 3: Implement `ActionKind.swift`**

```swift
import Foundation

public enum ConvertTarget: String, CaseIterable, Sendable {
    case jpg, png, heic, tiff, mp4, gif, m4a
}

public enum CompressPreset: String, CaseIterable, Sendable {
    case light, medium, strong, resize
}

/// What the user chose on the wheel. Which concrete implementation runs
/// is decided per file by `ActionRouter`, using the file's `FileKind`.
public enum ActionKind: Equatable, Sendable {
    case markdown
    case convert(ConvertTarget)
    case compress(CompressPreset)
    case splitPDF
    case cutOut
    case combine
}
```

- [ ] **Step 4: Implement `WheelLayout.swift`**

```swift
import Foundation

/// The six fixed directions, clockwise from the top. Raw value times 60 is the angle in degrees.
public enum Slot: Int, CaseIterable, Sendable {
    case up = 0, upperRight, lowerRight, down, lowerLeft, upperLeft
}

public enum Verb: String, Sendable {
    case markdown, convert, compress, extra, combine
}

public struct WheelOption: Equatable, Sendable {
    public let id: String
    public let title: String
    public let action: ActionKind
}

public struct WheelEntry: Equatable, Sendable {
    public let slot: Slot
    public let verb: Verb
    public let title: String
    /// SF Symbol name.
    public let symbol: String
    /// Never empty. An entry with one option has no outer ring.
    public let options: [WheelOption]
    public let defaultOptionID: String
    public let remembersLastUsed: Bool
}

/// The single source of truth for what the wheel shows.
public enum WheelLayout {
    public static func entries(for classification: Classification, fileCount: Int) -> [WheelEntry] {
        switch classification {
        case .pdf:
            var list = [
                markdown(),
                convert([.png, .jpg], default: .png),
                compress(resize: false),
                single(.lowerLeft, .extra, "Split", "square.split.2x1", .splitPDF),
            ]
            if fileCount >= 2 { list.append(combine()) }
            return list
        case .image:
            return [
                markdown(),
                convert([.jpg, .png, .heic, .tiff], default: .jpg),
                compress(resize: true),
                single(.lowerLeft, .extra, "Cut out", "person.crop.rectangle", .cutOut),
                combine(),
            ]
        case .video:
            return [markdown(), convert([.mp4, .gif, .m4a], default: .mp4), compress(resize: false)]
        case .audio:
            return [markdown(), convert([.m4a], default: .m4a), compress(resize: false)]
        case .videoAudio:
            return [markdown(), convert([.m4a], default: .m4a, remembers: false), compress(resize: false, remembers: false)]
        case .pdfImage:
            return [markdown(), compress(resize: false, remembers: false), combine()]
        case .unsupported:
            return []
        }
    }

    private static func single(_ slot: Slot, _ verb: Verb, _ title: String, _ symbol: String, _ action: ActionKind) -> WheelEntry {
        WheelEntry(slot: slot, verb: verb, title: title, symbol: symbol,
                   options: [WheelOption(id: verb.rawValue, title: title, action: action)],
                   defaultOptionID: verb.rawValue, remembersLastUsed: false)
    }

    private static func markdown() -> WheelEntry {
        single(.up, .markdown, "Markdown", "text.document", .markdown)
    }

    private static func combine() -> WheelEntry {
        single(.upperLeft, .combine, "Combine", "square.on.square", .combine)
    }

    private static func convert(_ targets: [ConvertTarget], default def: ConvertTarget, remembers: Bool = true) -> WheelEntry {
        WheelEntry(slot: .upperRight, verb: .convert, title: "Convert", symbol: "arrow.left.arrow.right",
                   options: targets.map { WheelOption(id: $0.rawValue, title: $0.rawValue.uppercased(), action: .convert($0)) },
                   defaultOptionID: def.rawValue, remembersLastUsed: remembers)
    }

    private static func compress(resize: Bool, remembers: Bool = true) -> WheelEntry {
        var presets: [CompressPreset] = [.light, .medium, .strong]
        if resize { presets.append(.resize) }
        return WheelEntry(slot: .lowerRight, verb: .compress, title: "Compress", symbol: "arrow.down.right.and.arrow.up.left",
                          options: presets.map { WheelOption(id: $0.rawValue, title: $0 == .resize ? "2000 px" : $0.rawValue.capitalized, action: .compress($0)) },
                          defaultOptionID: CompressPreset.medium.rawValue, remembersLastUsed: remembers)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter WheelLayoutTests`
Expected: PASS, 7 tests.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add action kinds and wheel layout table"
```

---

### Task 4: Settings snapshot and last-used store

**Files:**
- Create: `Sources/FinderWheelCore/Settings/SettingsSnapshot.swift`
- Create: `Sources/FinderWheelCore/Settings/LastUsedStore.swift`
- Create: `Tests/FinderWheelCoreTests/LastUsedStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import FinderWheelCore

@Suite struct LastUsedStoreTests {
    private func makeStore() -> LastUsedStore {
        let name = "LastUsedStoreTests-\(UUID().uuidString)"
        return LastUsedStore(defaults: UserDefaults(suiteName: name)!)
    }
    private var imageConvert: WheelEntry {
        WheelLayout.entries(for: .image, fileCount: 1).first { $0.verb == .convert }!
    }

    @Test func fallsBackToDefault() {
        #expect(makeStore().option(for: imageConvert, classification: .image).id == "jpg")
    }

    @Test func remembersPerClassificationAndVerb() {
        let store = makeStore()
        store.remember(optionID: "heic", for: imageConvert, classification: .image)
        #expect(store.option(for: imageConvert, classification: .image).id == "heic")
        let pdfConvert = WheelLayout.entries(for: .pdf, fileCount: 1).first { $0.verb == .convert }!
        #expect(store.option(for: pdfConvert, classification: .pdf).id == "png")
    }

    @Test func ignoresStoredValueThatIsNoLongerAnOption() {
        let store = makeStore()
        store.remember(optionID: "bmp", for: imageConvert, classification: .image)
        #expect(store.option(for: imageConvert, classification: .image).id == "jpg")
    }

    @Test func entriesThatDoNotRememberAlwaysUseDefault() {
        let store = makeStore()
        let mixCompress = WheelLayout.entries(for: .pdfImage, fileCount: 2).first { $0.verb == .compress }!
        store.remember(optionID: "strong", for: mixCompress, classification: .pdfImage)
        #expect(store.option(for: mixCompress, classification: .pdfImage).id == "medium")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter LastUsedStoreTests`
Expected: FAIL to compile, "cannot find 'LastUsedStore' in scope".

- [ ] **Step 3: Implement `SettingsSnapshot.swift`**

```swift
import Foundation

/// Immutable copy of the settings an action needs. Passed into every job.
public struct SettingsSnapshot: Sendable {
    public var stripLocation: Bool
    public var mistralKey: String?
    public var transcriptionLocale: Locale

    public init(stripLocation: Bool = true, mistralKey: String? = nil, transcriptionLocale: Locale = .current) {
        self.stripLocation = stripLocation
        self.mistralKey = mistralKey
        self.transcriptionLocale = transcriptionLocale
    }
}

/// A hotkey the user can pick. Values are Carbon virtual key codes and modifier masks.
public struct HotkeyCombo: Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let keyCode: UInt32
    public let modifiers: UInt32

    private static let space: UInt32 = 49       // kVK_Space
    private static let option: UInt32 = 0x0800  // optionKey
    private static let control: UInt32 = 0x1000 // controlKey

    public static let optionSpace = HotkeyCombo(id: "option-space", label: "⌥ Space", keyCode: space, modifiers: option)
    public static let controlSpace = HotkeyCombo(id: "control-space", label: "⌃ Space", keyCode: space, modifiers: control)
    public static let controlOptionSpace = HotkeyCombo(id: "control-option-space", label: "⌃⌥ Space", keyCode: space, modifiers: control | option)

    public static let all: [HotkeyCombo] = [.optionSpace, .controlSpace, .controlOptionSpace]
    public static func named(_ id: String?) -> HotkeyCombo { all.first { $0.id == id } ?? .optionSpace }
}
```

- [ ] **Step 4: Implement `LastUsedStore.swift`**

```swift
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
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter LastUsedStoreTests`
Expected: PASS, 4 tests.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add settings snapshot and last-used store"
```

---

### Task 5: Wheel geometry

The tracker turns the cursor offset from the wheel centre into a hit. Offsets use screen coordinates: `dx` positive is right, `dy` positive is **up**.

Rules:
- Inside the dead zone (radius < 44): no hit.
- In the ring (44 to 140): the 60° wedge under the cursor. A slot with no entry gives no hit.
- Beyond 140: the slot is locked to the wedge the cursor left through. If that entry has one option the hit stays on the entry. Otherwise the outer ring is hit: options are 30° each, fanned symmetrically around the wedge's direction, and the index is clamped to the first and last option.
- Coming back inside 140 unlocks the slot.

**Files:**
- Create: `Sources/FinderWheelCore/Wheel/WheelTracker.swift`
- Create: `Tests/FinderWheelCoreTests/WheelTrackerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import CoreGraphics
import Foundation
@testable import FinderWheelCore

@Suite struct WheelTrackerTests {
    /// Offset for an angle in degrees clockwise from up, at a radius.
    private func point(_ degrees: Double, _ radius: Double) -> (CGFloat, CGFloat) {
        let r = degrees * .pi / 180
        return (CGFloat(sin(r) * radius), CGFloat(cos(r) * radius))
    }
    private func tracker(_ counts: [Slot: Int]) -> WheelTracker { WheelTracker(optionCounts: counts) }
    private func hit(_ t: inout WheelTracker, _ degrees: Double, _ radius: Double) -> WheelHit {
        let (dx, dy) = point(degrees, radius)
        t.update(dx: dx, dy: dy)
        return t.hit
    }

    @Test func deadZoneIsNoHit() {
        var t = tracker([.up: 1])
        #expect(hit(&t, 0, 20) == .none)
    }

    @Test func eachDirectionMapsToItsSlot() {
        var t = tracker(Dictionary(uniqueKeysWithValues: Slot.allCases.map { ($0, 1) }))
        #expect(hit(&t, 0, 90) == .entry(.up))
        #expect(hit(&t, 60, 90) == .entry(.upperRight))
        #expect(hit(&t, 120, 90) == .entry(.lowerRight))
        #expect(hit(&t, 180, 90) == .entry(.down))
        #expect(hit(&t, 240, 90) == .entry(.lowerLeft))
        #expect(hit(&t, 300, 90) == .entry(.upperLeft))
    }

    @Test func wedgeBoundariesAreAtThirtyDegrees() {
        var t = tracker([.up: 1, .upperRight: 1, .upperLeft: 1])
        #expect(hit(&t, 29, 90) == .entry(.up))
        #expect(hit(&t, 31, 90) == .entry(.upperRight))
        #expect(hit(&t, 331, 90) == .entry(.up))
        #expect(hit(&t, 329, 90) == .entry(.upperLeft))
    }

    @Test func emptySlotIsNoHit() {
        var t = tracker([.up: 1])
        #expect(hit(&t, 180, 90) == .none)
        #expect(hit(&t, 180, 300) == .none)
    }

    @Test func singleOptionEntryStaysEntryBeyondTheRing() {
        var t = tracker([.up: 1])
        #expect(hit(&t, 0, 90) == .entry(.up))
        #expect(hit(&t, 0, 400) == .entry(.up))
    }

    @Test func outerRingPicksOptionByAngle() {
        // 4 options around 60°: centres at 15°, 45°, 75°, 105°.
        var t = tracker([.upperRight: 4])
        #expect(hit(&t, 60, 90) == .entry(.upperRight))
        #expect(hit(&t, 15, 180) == .option(.upperRight, 0))
        #expect(hit(&t, 45, 180) == .option(.upperRight, 1))
        #expect(hit(&t, 75, 180) == .option(.upperRight, 2))
        #expect(hit(&t, 105, 180) == .option(.upperRight, 3))
    }

    @Test func outerRingClampsAndStaysLocked() {
        var t = tracker([.upperRight: 3, .lowerRight: 3])
        _ = hit(&t, 60, 90)
        _ = hit(&t, 60, 180)
        // Far past the fan, still locked to upperRight and clamped to the last option.
        #expect(hit(&t, 150, 180) == .option(.upperRight, 2))
        #expect(hit(&t, 350, 180) == .option(.upperRight, 0))
    }

    @Test func returningInsideUnlocks() {
        var t = tracker([.upperRight: 3, .lowerRight: 3])
        _ = hit(&t, 60, 180)
        #expect(hit(&t, 120, 90) == .entry(.lowerRight))
        #expect(hit(&t, 120, 180) == .option(.lowerRight, 1))
    }

    @Test func threeOptionsCentreIsStraightAhead() {
        var t = tracker([.lowerRight: 3])
        #expect(hit(&t, 120, 180) == .option(.lowerRight, 1))
        #expect(hit(&t, 90, 180) == .option(.lowerRight, 0))
        #expect(hit(&t, 150, 180) == .option(.lowerRight, 2))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter WheelTrackerTests`
Expected: FAIL to compile, "cannot find 'WheelTracker' in scope".

- [ ] **Step 3: Implement `WheelTracker.swift`**

```swift
import CoreGraphics
import Foundation

public struct WheelMetrics: Sendable {
    /// Radius below which nothing is selected.
    public var deadZone: CGFloat = 44
    /// Outer edge of the main ring; beyond it the outer ring begins.
    public var ringOuter: CGFloat = 140
    /// Outer edge of the outer ring, for drawing only. Hit-testing has no outer limit.
    public var outerRingOuter: CGFloat = 206
    /// Angular size of one outer-ring option, in degrees.
    public var optionArc: Double = 30

    public init() {}

    /// Centre angle in degrees (clockwise from up) of option `index` out of `count` for a slot.
    public func optionAngle(slot: Slot, index: Int, count: Int) -> Double {
        Double(slot.rawValue) * 60 + (Double(index) - Double(count - 1) / 2) * optionArc
    }
}

public enum WheelHit: Equatable, Sendable {
    case none
    case entry(Slot)
    case option(Slot, Int)
}

/// Pure geometry: cursor offset in, hit out. Holds the one piece of state the wheel
/// needs, which slot the cursor left the ring through.
public struct WheelTracker: Sendable {
    public let metrics: WheelMetrics
    private let optionCounts: [Slot: Int]
    private var lockedSlot: Slot?
    public private(set) var hit: WheelHit = .none

    /// `optionCounts` has one key per slot that has an entry; the value is its number of options.
    public init(optionCounts: [Slot: Int], metrics: WheelMetrics = WheelMetrics()) {
        self.optionCounts = optionCounts
        self.metrics = metrics
    }

    /// `dx` positive is right, `dy` positive is up.
    public mutating func update(dx: CGFloat, dy: CGFloat) {
        let radius = hypot(dx, dy)
        guard radius >= metrics.deadZone else {
            lockedSlot = nil
            hit = .none
            return
        }
        var degrees = Double(atan2(dx, dy)) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        let angleSlot = Slot(rawValue: Int((degrees + 30) / 60) % 6)!

        if radius < metrics.ringOuter {
            lockedSlot = nil
            hit = optionCounts[angleSlot] == nil ? .none : .entry(angleSlot)
            return
        }

        let slot = lockedSlot ?? angleSlot
        lockedSlot = slot
        guard let count = optionCounts[slot] else {
            hit = .none
            return
        }
        guard count > 1 else {
            hit = .entry(slot)
            return
        }
        var delta = degrees - Double(slot.rawValue) * 60
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        let raw = Int((delta / metrics.optionArc + Double(count) / 2).rounded(.down))
        hit = .option(slot, min(max(raw, 0), count - 1))
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter WheelTrackerTests`
Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add wheel geometry tracker"
```

---

### Task 6: Output naming and atomic writes

Naming rules from the spec:
- `fileURL(for:suffix:ext:)`: next to the input, `<name>-<suffix>.<ext>`, or `<name>.<ext>` when the suffix is nil.
- `folderURL(for:suffix:)`: next to the input, `<name>-<suffix>`.
- If the path exists, append `-2`, `-3`, and so on before the extension. Never return an existing path.
- `pageFileName(base:index:count:ext:)`: `<base>-p01.<ext>`, zero-padded to at least two digits and wide enough for `count`.

**Files:**
- Create: `Sources/FinderWheelCore/Jobs/OutputNamer.swift`
- Create: `Sources/FinderWheelCore/Jobs/AtomicOutput.swift`
- Create: `Tests/FinderWheelCoreTests/Fixtures.swift`
- Create: `Tests/FinderWheelCoreTests/OutputNamerTests.swift`

- [ ] **Step 1: Write the fixtures helper**

`Tests/FinderWheelCoreTests/Fixtures.swift`:

```swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// A temp folder that is deleted when the value is released. Each test makes its own.
final class TempFolder {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("FinderWheelTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func file(_ name: String) -> URL { url.appendingPathComponent(name) }

    @discardableResult
    func touch(_ name: String) -> URL {
        let u = file(name)
        FileManager.default.createFile(atPath: u.path, contents: Data("x".utf8))
        return u
    }
}

enum Fixtures {
    /// A solid-colour bitmap with a diagonal gradient, so lossy formats have something to compress.
    static func cgImage(width: Int = 400, height: Int = 300, alpha: Bool = false) -> CGImage {
        let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
        for i in 0..<20 {
            ctx.setFillColor(red: CGFloat(i) / 20, green: 0.4, blue: 1 - CGFloat(i) / 20, alpha: 1)
            ctx.fill(CGRect(x: i * width / 20, y: 0, width: width / 20 + 1, height: height))
        }
        if alpha { ctx.clear(CGRect(x: 0, y: 0, width: width / 2, height: height / 2)) }
        return ctx.makeImage()!
    }

    /// Writes an image file. With `gps`, the file carries a location.
    @discardableResult
    static func writeImage(to url: URL, type: UTType, width: Int = 400, height: Int = 300, alpha: Bool = false, gps: Bool = false) -> URL {
        let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        var props: [CFString: Any] = [:]
        if gps {
            props[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 48.137, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 11.575, kCGImagePropertyGPSLongitudeRef: "E",
            ] as [CFString: Any]
        }
        CGImageDestinationAddImage(dest, cgImage(width: width, height: height, alpha: alpha), props as CFDictionary)
        precondition(CGImageDestinationFinalize(dest))
        return url
    }

    static func imageProperties(_ url: URL) -> [CFString: Any] {
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    static func imageType(_ url: URL) -> UTType? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let id = CGImageSourceGetType(source) else { return nil }
        return UTType(id as String)
    }

    static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
    }
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/FinderWheelCoreTests/OutputNamerTests.swift`:

```swift
import Testing
import Foundation
@testable import FinderWheelCore

@Suite struct OutputNamerTests {
    @Test func suffixAndExtension() {
        let tmp = TempFolder()
        let input = tmp.touch("report.pdf")
        #expect(OutputNamer.fileURL(for: input, suffix: "compressed", ext: "pdf").lastPathComponent == "report-compressed.pdf")
        #expect(OutputNamer.fileURL(for: input, suffix: nil, ext: "md").lastPathComponent == "report.md")
        #expect(OutputNamer.fileURL(for: input, suffix: nil, ext: "md").deletingLastPathComponent().path == tmp.url.path)
    }

    @Test func collisionsGetANumber() {
        let tmp = TempFolder()
        let input = tmp.touch("photo.heic")
        tmp.touch("photo.jpg")
        #expect(OutputNamer.fileURL(for: input, suffix: nil, ext: "jpg").lastPathComponent == "photo-2.jpg")
        tmp.touch("photo-2.jpg")
        #expect(OutputNamer.fileURL(for: input, suffix: nil, ext: "jpg").lastPathComponent == "photo-3.jpg")
    }

    @Test func namesWithDotsKeepTheirStem() {
        let tmp = TempFolder()
        let input = tmp.touch("scan.v2.final.pdf")
        #expect(OutputNamer.fileURL(for: input, suffix: "merged", ext: "pdf").lastPathComponent == "scan.v2.final-merged.pdf")
    }

    @Test func folders() throws {
        let tmp = TempFolder()
        let input = tmp.touch("report.pdf")
        #expect(OutputNamer.folderURL(for: input, suffix: "pages").lastPathComponent == "report-pages")
        try FileManager.default.createDirectory(at: tmp.file("report-pages"), withIntermediateDirectories: false)
        #expect(OutputNamer.folderURL(for: input, suffix: "pages").lastPathComponent == "report-pages-2")
    }

    @Test func pageFileNames() {
        #expect(OutputNamer.pageFileName(base: "report", index: 0, count: 5, ext: "pdf") == "report-p01.pdf")
        #expect(OutputNamer.pageFileName(base: "report", index: 11, count: 12, ext: "png") == "report-p12.png")
        #expect(OutputNamer.pageFileName(base: "report", index: 0, count: 250, ext: "png") == "report-p001.png")
    }

    @Test func atomicWriteMovesIntoPlace() throws {
        let tmp = TempFolder()
        let final = tmp.file("out.txt")
        try AtomicOutput.write(to: final) { temp in
            #expect(temp.lastPathComponent == "out.txt")
            #expect(temp.path != final.path)
            try Data("hello".utf8).write(to: temp)
        }
        #expect(try String(contentsOf: final, encoding: .utf8) == "hello")
    }

    @Test func atomicWriteLeavesNothingOnFailure() {
        let tmp = TempFolder()
        let final = tmp.file("out.txt")
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            try AtomicOutput.write(to: final) { temp in
                try Data("partial".utf8).write(to: temp)
                throw Boom()
            }
        }
        #expect(!FileManager.default.fileExists(atPath: final.path))
    }

    @Test func atomicWriteNeverOverwrites() throws {
        let tmp = TempFolder()
        let final = tmp.touch("out.txt")
        #expect(throws: (any Error).self) {
            try AtomicOutput.write(to: final) { temp in try Data("new".utf8).write(to: temp) }
        }
        #expect(try String(contentsOf: final, encoding: .utf8) == "x")
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter OutputNamerTests`
Expected: FAIL to compile, "cannot find 'OutputNamer' in scope".

- [ ] **Step 4: Implement `OutputNamer.swift`**

```swift
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
            let url = directory.appendingPathComponent(name)
            return ext.map { url.appendingPathExtension($0) } ?? url
        }
        var n = 1
        while FileManager.default.fileExists(atPath: candidate(n).path) { n += 1 }
        return candidate(n)
    }
}
```

- [ ] **Step 5: Implement `AtomicOutput.swift`**

```swift
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
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter OutputNamerTests`
Expected: PASS, 8 tests.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add output naming and atomic writes"
```

---

### Task 7: Action protocol and image Convert

Behaviour:
- Converts one image to the target format (JPG, PNG, HEIC, TIFF) next to the original, with no suffix.
- An image already in the target format is skipped with the message "Already JPG" (format name in capitals).
- Location metadata is removed when `settings.stripLocation` is true, kept otherwise. Other metadata, including orientation, is kept.
- Transparency is flattened onto white when the target is JPG.

**Files:**
- Create: `Sources/FinderWheelCore/Jobs/FileAction.swift`
- Create: `Sources/FinderWheelCore/Actions/ImageIOHelper.swift`
- Create: `Sources/FinderWheelCore/Actions/ImageConvertAction.swift`
- Create: `Tests/FinderWheelCoreTests/ImageConvertActionTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import FinderWheelCore

@Suite struct ImageConvertActionTests {
    private func context(strip: Bool = true) -> ActionContext {
        ActionContext(settings: SettingsSnapshot(stripLocation: strip), progress: { _ in })
    }

    @Test func convertsPNGToJPGNextToOriginal() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeImage(to: tmp.file("shot.png"), type: .png)
        let outcome = try await ImageConvertAction(target: .jpg).run(input: input, context: context())
        #expect(outcome == .produced([tmp.file("shot.jpg")]))
        #expect(Fixtures.imageType(tmp.file("shot.jpg")) == .jpeg)
        #expect(FileManager.default.fileExists(atPath: input.path))
    }

    @Test func convertsToEachTarget() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeImage(to: tmp.file("a.jpg"), type: .jpeg)
        for (target, type) in [(ConvertTarget.png, UTType.png), (.heic, .heic), (.tiff, .tiff)] {
            let outcome = try await ImageConvertAction(target: target).run(input: input, context: context())
            guard case .produced(let urls) = outcome else { Issue.record("expected output"); continue }
            #expect(urls.count == 1)
            #expect(Fixtures.imageType(urls[0]) == type)
            #expect(urls[0].pathExtension == target.rawValue)
        }
    }

    @Test func skipsWhenAlreadyInTargetFormat() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeImage(to: tmp.file("a.jpeg"), type: .jpeg)
        let outcome = try await ImageConvertAction(target: .jpg).run(input: input, context: context())
        #expect(outcome == .skipped("Already JPG"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.url.path).count == 1)
    }

    @Test func stripsLocationByDefault() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeImage(to: tmp.file("a.jpg"), type: .jpeg, gps: true)
        #expect(Fixtures.imageProperties(input)[kCGImagePropertyGPSDictionary] != nil)
        _ = try await ImageConvertAction(target: .heic).run(input: input, context: context(strip: true))
        #expect(Fixtures.imageProperties(tmp.file("a.heic"))[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test func keepsLocationWhenStrippingIsOff() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeImage(to: tmp.file("a.jpg"), type: .jpeg, gps: true)
        _ = try await ImageConvertAction(target: .heic).run(input: input, context: context(strip: false))
        #expect(Fixtures.imageProperties(tmp.file("a.heic"))[kCGImagePropertyGPSDictionary] != nil)
    }

    @Test func doesNotOverwriteExistingOutput() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeImage(to: tmp.file("a.png"), type: .png)
        tmp.touch("a.jpg")
        let outcome = try await ImageConvertAction(target: .jpg).run(input: input, context: context())
        #expect(outcome == .produced([tmp.file("a-2.jpg")]))
    }

    @Test func unreadableFileThrows() async {
        let tmp = TempFolder()
        let input = tmp.touch("broken.png")
        await #expect(throws: ActionError.self) {
            _ = try await ImageConvertAction(target: .jpg).run(input: input, context: context())
        }
    }

    @Test func rejectsNonImageTarget() async {
        let tmp = TempFolder()
        let input = Fixtures.writeImage(to: tmp.file("a.png"), type: .png)
        await #expect(throws: ActionError.self) {
            _ = try await ImageConvertAction(target: .mp4).run(input: input, context: context())
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ImageConvertActionTests`
Expected: FAIL to compile, "cannot find 'ActionContext' in scope".

- [ ] **Step 3: Implement `FileAction.swift`**

```swift
import Foundation

public struct ActionContext: Sendable {
    public let settings: SettingsSnapshot
    /// Report progress for the current file, 0 to 1. Safe to call from any thread.
    public let progress: @Sendable (Double) -> Void

    public init(settings: SettingsSnapshot, progress: @escaping @Sendable (Double) -> Void) {
        self.settings = settings
        self.progress = progress
    }
}

public enum ActionOutcome: Equatable, Sendable {
    /// Files or folders that now exist next to the original.
    case produced([URL])
    /// Nothing was written; the reason is shown in the menu.
    case skipped(String)
}

/// A failure with a message that is shown to the user as is.
public struct ActionError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }

    public static let missingMistralKey = ActionError("Mistral API key missing. Add it in Settings.")
}

/// One action on one input file. Implementations never modify or overwrite the input
/// and write outputs through `AtomicOutput`.
public protocol FileAction: Sendable {
    func run(input: URL, context: ActionContext) async throws -> ActionOutcome
}
```

- [ ] **Step 4: Implement `ImageIOHelper.swift`**

```swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ImageIOHelper {
    static func source(for url: URL) throws -> (source: CGImageSource, type: UTType) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let id = CGImageSourceGetType(source),
              let type = UTType(id as String) else {
            throw ActionError("Could not read image")
        }
        return (source, type)
    }

    /// Re-encodes the first image of `source`. Metadata is carried over, minus location if asked.
    static func write(source: CGImageSource, to url: URL, type: UTType, quality: Double,
                      maxPixel: Int? = nil, stripLocation: Bool, flattenAlpha: Bool) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ActionError("This Mac cannot write \(type.preferredFilenameExtension?.uppercased() ?? "that format")")
        }
        var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        if stripLocation { props[kCGImagePropertyGPSDictionary] = kCFNull! }
        if let maxPixel { props[kCGImageDestinationImageMaxPixelSize] = maxPixel }
        if flattenAlpha { props[kCGImageDestinationBackgroundColor] = CGColor(red: 1, green: 1, blue: 1, alpha: 1) }
        CGImageDestinationAddImageFromSource(dest, source, 0, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ActionError("Could not write image") }
    }
}

extension ConvertTarget {
    /// The image type for image targets, nil for media targets.
    var imageType: UTType? {
        switch self {
        case .jpg: return .jpeg
        case .png: return .png
        case .heic: return .heic
        case .tiff: return .tiff
        case .mp4, .gif, .m4a: return nil
        }
    }
}
```

- [ ] **Step 5: Implement `ImageConvertAction.swift`**

```swift
import Foundation
import UniformTypeIdentifiers

public struct ImageConvertAction: FileAction {
    public let target: ConvertTarget

    public init(target: ConvertTarget) { self.target = target }

    public func run(input: URL, context: ActionContext) async throws -> ActionOutcome {
        guard let type = target.imageType else { throw ActionError("Cannot convert an image to \(target.rawValue.uppercased())") }
        let (source, sourceType) = try ImageIOHelper.source(for: input)
        if sourceType.conforms(to: type) { return .skipped("Already \(target.rawValue.uppercased())") }
        let output = OutputNamer.fileURL(for: input, suffix: nil, ext: target.rawValue)
        try AtomicOutput.write(to: output) { temp in
            try ImageIOHelper.write(source: source, to: temp, type: type, quality: 0.9,
                                    stripLocation: context.settings.stripLocation, flattenAlpha: target == .jpg)
        }
        return .produced([output])
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter ImageConvertActionTests`
Expected: PASS, 8 tests.

If `stripsLocationByDefault` fails because the GPS dictionary survives, replace the `kCFNull` line in `ImageIOHelper.write` with a metadata-based removal: create the image with `CGImageSourceCreateImageAtIndex`, copy `CGImageSourceCopyPropertiesAtIndex` into a mutable dictionary, remove `kCGImagePropertyGPSDictionary`, and call `CGImageDestinationAddImage` with that dictionary merged into `props`. Keep the tests unchanged.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add action protocol and image convert action"
```

---

### Task 8: Action router and job centre

The job centre runs one job per wheel choice. A job processes its files one after another. Requirements from the spec:
- A failure or skip on one file is recorded as a note and the job continues.
- Progress is the fraction of files done plus the current file's own progress.
- Cancel stops the job; the in-flight action's temp output is discarded by `AtomicOutput`.
- When a job ends with outputs, `onFinished` is called with them so the app can select them in Finder.
- A failure note sets `hasWarning` until the user opens the menu.

**Files:**
- Create: `Sources/FinderWheelCore/Jobs/ActionRouter.swift`
- Create: `Sources/FinderWheelCore/Jobs/JobCenter.swift`
- Create: `Tests/FinderWheelCoreTests/JobCenterTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import FinderWheelCore

private struct StubAction: FileAction {
    var behaviour: @Sendable (URL, ActionContext) async throws -> ActionOutcome
    func run(input: URL, context: ActionContext) async throws -> ActionOutcome { try await behaviour(input, context) }
}

@MainActor
@Suite struct JobCenterTests {
    private let files = ["a.png", "b.png", "c.png"].map { URL(fileURLWithPath: "/tmp/\($0)") }

    private func center(_ behaviour: @escaping @Sendable (URL, ActionContext) async throws -> ActionOutcome) -> JobCenter {
        JobCenter(resolve: { _, _ in StubAction(behaviour: behaviour) }, kindOf: { _ in .image })
    }

    @Test func runsEveryFileAndCollectsOutputs() async {
        let jobs = center { url, _ in .produced([url.appendingPathExtension("out")]) }
        var finished: [URL] = []
        jobs.onFinished = { finished = $0 }
        let id = jobs.start(title: "Convert", inputs: files, kind: .convert(.jpg), settings: SettingsSnapshot())
        await jobs.wait(id)
        let job = jobs.jobs.first { $0.id == id }!
        #expect(job.state == .finished)
        #expect(job.done == 3)
        #expect(job.progress == 1)
        #expect(job.outputs.count == 3)
        #expect(finished.count == 3)
        #expect(!jobs.isRunning)
        #expect(!jobs.hasWarning)
    }

    @Test func oneFailureDoesNotStopTheBatch() async {
        let jobs = center { url, _ in
            if url.lastPathComponent == "b.png" { throw ActionError("Could not read image") }
            return .produced([url])
        }
        let id = jobs.start(title: "Convert", inputs: files, kind: .convert(.jpg), settings: SettingsSnapshot())
        await jobs.wait(id)
        let job = jobs.jobs.first { $0.id == id }!
        #expect(job.outputs.count == 2)
        #expect(job.notes.count == 1)
        #expect(job.notes[0].file == "b.png")
        #expect(job.notes[0].message == "Could not read image")
        #expect(job.notes[0].isFailure)
        #expect(jobs.hasWarning)
        jobs.clearWarning()
        #expect(!jobs.hasWarning)
    }

    @Test func skipsAreNotedButAreNotWarnings() async {
        let jobs = center { _, _ in .skipped("Already JPG") }
        var finishedCalled = false
        jobs.onFinished = { _ in finishedCalled = true }
        let id = jobs.start(title: "Convert", inputs: files, kind: .convert(.jpg), settings: SettingsSnapshot())
        await jobs.wait(id)
        let job = jobs.jobs.first { $0.id == id }!
        #expect(job.notes.count == 3)
        #expect(job.notes.allSatisfy { !$0.isFailure && $0.message == "Already JPG" })
        #expect(!jobs.hasWarning)
        #expect(!finishedCalled)
    }

    @Test func unresolvableActionIsAFailureNote() async {
        let jobs = JobCenter(resolve: { _, _ in nil }, kindOf: { _ in .image })
        let id = jobs.start(title: "Split", inputs: [files[0]], kind: .splitPDF, settings: SettingsSnapshot())
        await jobs.wait(id)
        let job = jobs.jobs.first { $0.id == id }!
        #expect(job.notes.first?.message == "This action is not available for this file")
        #expect(job.notes.first?.isFailure == true)
    }

    @Test func cancelStopsBeforeRemainingFiles() async {
        let jobs = center { url, _ in
            try await Task.sleep(for: .seconds(30))
            return .produced([url])
        }
        let id = jobs.start(title: "Convert", inputs: files, kind: .convert(.jpg), settings: SettingsSnapshot())
        #expect(jobs.isRunning)
        jobs.cancel(id)
        await jobs.wait(id)
        let job = jobs.jobs.first { $0.id == id }!
        #expect(job.state == .cancelled)
        #expect(job.outputs.isEmpty)
        #expect(job.notes.isEmpty)
    }

    @Test func batchJobReportsOutputs() async {
        let jobs = center { _, _ in .skipped("unused") }
        let out = URL(fileURLWithPath: "/tmp/merged.pdf")
        let id = jobs.startBatch(title: "Combine", settings: SettingsSnapshot()) { _ in [out] }
        await jobs.wait(id)
        let job = jobs.jobs.first { $0.id == id }!
        #expect(job.state == .finished)
        #expect(job.outputs == [out])
    }

    @Test func batchFailureIsANote() async {
        let jobs = center { _, _ in .skipped("unused") }
        let id = jobs.startBatch(title: "Combine", settings: SettingsSnapshot()) { _ in throw ActionError("PDF is password-protected") }
        await jobs.wait(id)
        let job = jobs.jobs.first { $0.id == id }!
        #expect(job.notes.first?.message == "PDF is password-protected")
        #expect(jobs.hasWarning)
    }

    @Test func routerKnowsImageConvert() {
        #expect(ActionRouter.action(for: .convert(.jpg), fileKind: .image) is ImageConvertAction)
        #expect(ActionRouter.action(for: .convert(.mp4), fileKind: .image) == nil)
        #expect(ActionRouter.action(for: .convert(.jpg), fileKind: .unsupported) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter JobCenterTests`
Expected: FAIL to compile, "cannot find 'JobCenter' in scope".

- [ ] **Step 3: Implement `ActionRouter.swift`**

```swift
import Foundation

/// Maps what the user chose plus the kind of one file to the action that handles it.
/// Returns nil when the combination has no implementation.
/// Plans 2 and 3 add the remaining cases to this switch.
public enum ActionRouter {
    public static func action(for kind: ActionKind, fileKind: FileKind) -> FileAction? {
        switch (kind, fileKind) {
        case (.convert(let target), .image) where target.imageType != nil:
            return ImageConvertAction(target: target)
        default:
            return nil
        }
    }
}
```

- [ ] **Step 4: Implement `JobCenter.swift`**

```swift
import Foundation
import Observation

@MainActor
@Observable
public final class JobCenter {
    public struct Note: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public let file: String
        public let message: String
        public let isFailure: Bool
    }

    public enum State: Equatable, Sendable { case running, finished, cancelled }

    public struct Job: Identifiable, Sendable {
        public let id: UUID
        public let title: String
        public let total: Int
        public var done = 0
        public var currentFraction = 0.0
        public var state: State = .running
        public var outputs: [URL] = []
        public var notes: [Note] = []

        public var progress: Double {
            if state != .running { return 1 }
            guard total > 0 else { return 0 }
            return min(1, (Double(done) + currentFraction) / Double(total))
        }
    }

    /// Newest first. At most 20 are kept.
    public private(set) var jobs: [Job] = []
    public private(set) var hasWarning = false
    /// Called on the main actor with the outputs of a job that produced at least one.
    @ObservationIgnored public var onFinished: (([URL]) -> Void)?

    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let resolve: (ActionKind, FileKind) -> FileAction?
    @ObservationIgnored private let kindOf: (URL) -> FileKind

    public init(resolve: @escaping (ActionKind, FileKind) -> FileAction? = ActionRouter.action(for:fileKind:),
                kindOf: @escaping (URL) -> FileKind = { Classifier.kind(of: $0) }) {
        self.resolve = resolve
        self.kindOf = kindOf
    }

    public var isRunning: Bool { jobs.contains { $0.state == .running } }

    /// Mean progress of the running jobs, 0 when idle.
    public var overallProgress: Double {
        let running = jobs.filter { $0.state == .running }
        guard !running.isEmpty else { return 0 }
        return running.map(\.progress).reduce(0, +) / Double(running.count)
    }

    public func clearWarning() { hasWarning = false }

    /// Runs `kind` on each input in turn.
    @discardableResult
    public func start(title: String, inputs: [URL], kind: ActionKind, settings: SettingsSnapshot) -> UUID {
        let id = addJob(title: title, total: inputs.count)
        tasks[id] = Task { [weak self] in
            for input in inputs {
                guard let self, !Task.isCancelled else { break }
                let name = input.lastPathComponent
                guard let action = self.resolve(kind, self.kindOf(input)) else {
                    self.addNote(id, file: name, message: "This action is not available for this file", isFailure: true)
                    self.update(id) { $0.done += 1 }
                    continue
                }
                do {
                    switch try await action.run(input: input, context: self.context(for: id, settings: settings)) {
                    case .produced(let urls): self.update(id) { $0.outputs += urls }
                    case .skipped(let reason): self.addNote(id, file: name, message: reason, isFailure: false)
                    }
                } catch is CancellationError {
                    break
                } catch {
                    if Task.isCancelled { break }
                    self.addNote(id, file: name, message: error.localizedDescription, isFailure: true)
                }
                self.update(id) { $0.done += 1; $0.currentFraction = 0 }
            }
            self?.finish(id, cancelled: Task.isCancelled)
        }
        return id
    }

    /// Runs one operation over the whole selection (used by Combine). It returns the outputs.
    @discardableResult
    public func startBatch(title: String, settings: SettingsSnapshot,
                           operation: @escaping @Sendable (ActionContext) async throws -> [URL]) -> UUID {
        let id = addJob(title: title, total: 1)
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            do {
                let urls = try await operation(self.context(for: id, settings: settings))
                self.update(id) { $0.outputs += urls }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled {
                    self.addNote(id, file: title, message: error.localizedDescription, isFailure: true)
                }
            }
            self.finish(id, cancelled: Task.isCancelled)
        }
        return id
    }

    public func cancel(_ id: UUID) {
        tasks[id]?.cancel()
    }

    /// Suspends until the job has ended. Used by tests.
    public func wait(_ id: UUID) async {
        await tasks[id]?.value
    }

    private func addJob(title: String, total: Int) -> UUID {
        let id = UUID()
        jobs.insert(Job(id: id, title: title, total: total), at: 0)
        if jobs.count > 20 { jobs.removeLast(jobs.count - 20) }
        return id
    }

    private func context(for id: UUID, settings: SettingsSnapshot) -> ActionContext {
        ActionContext(settings: settings) { [weak self] fraction in
            Task { @MainActor [weak self] in
                self?.update(id) { $0.currentFraction = max(0, min(1, fraction)) }
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].state == .running else { return }
        change(&jobs[index])
    }

    private func addNote(_ id: UUID, file: String, message: String, isFailure: Bool) {
        update(id) { $0.notes.append(Note(file: file, message: message, isFailure: isFailure)) }
        if isFailure { hasWarning = true }
    }

    private func finish(_ id: UUID, cancelled: Bool) {
        var outputs: [URL] = []
        update(id) {
            $0.state = cancelled ? .cancelled : .finished
            outputs = $0.outputs
        }
        tasks[id] = nil
        if !outputs.isEmpty { onFinished?(outputs) }
    }
}
```

Note on `wait`: `finish` removes the task from `tasks`, so `wait` called after the job ended returns immediately. That is intended.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter JobCenterTests`
Expected: PASS, 8 tests.

- [ ] **Step 6: Run the whole suite**

Run: `swift test`
Expected: PASS, all suites.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add action router and job centre"
```

---

### Task 9: Hotkey trigger

This task has no automated tests; it is verified by hand in Step 3. It also settles the spec's open permission question.

Behaviour:
- The hotkey is registered with the system only while Finder is the frontmost app, so other apps receive the keystroke normally.
- `onPress` fires once when the hotkey goes down, `onRelease` once when it comes up.
- While the hotkey is held the registration is kept even if the frontmost app changes.
- `setEscapeEnabled(true)` registers Esc as a second hotkey; pressing it fires `onEscape`. The wheel enables it only while visible.
- `pollRelease()` is a safety net: the wheel calls it from its cursor timer, and it fires `onRelease` if the key is physically up but no release event arrived.

**Files:**
- Create: `Sources/FinderWheel/Trigger/HotkeyTrigger.swift`
- Modify: `Sources/FinderWheel/FinderWheelApp.swift` (temporary logging, removed in Task 12)

- [ ] **Step 1: Implement `HotkeyTrigger.swift`**

```swift
import AppKit
import Carbon.HIToolbox
import FinderWheelCore

/// Global hold-to-show hotkey, active only while Finder is frontmost.
final class HotkeyTrigger {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onEscape: (() -> Void)?

    private var combo: HotkeyCombo
    private var mainRef: EventHotKeyRef?
    private var escapeRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var activationObserver: NSObjectProtocol?
    private(set) var isHeld = false

    private static let signature: OSType = 0x4657_484C // "FWHL"
    private static let mainID: UInt32 = 1
    private static let escapeID: UInt32 = 2

    init(combo: HotkeyCombo) {
        self.combo = combo
    }

    func start() {
        installHandler()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateRegistration() }
        updateRegistration()
    }

    func setCombo(_ newCombo: HotkeyCombo) {
        guard newCombo != combo else { return }
        unregister(&mainRef)
        combo = newCombo
        updateRegistration()
    }

    func setEscapeEnabled(_ enabled: Bool) {
        if enabled, escapeRef == nil {
            escapeRef = register(keyCode: UInt32(kVK_Escape), modifiers: 0, id: Self.escapeID)
        } else if !enabled {
            unregister(&escapeRef)
        }
    }

    /// Fires `onRelease` if the hotkey's key is no longer physically down.
    func pollRelease() {
        guard isHeld else { return }
        if !CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(combo.keyCode)) {
            handle(id: Self.mainID, pressed: false)
        }
    }

    private var finderIsFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
    }

    private func updateRegistration() {
        if isHeld { return }
        if finderIsFrontmost {
            if mainRef == nil { mainRef = register(keyCode: combo.keyCode, modifiers: combo.modifiers, id: Self.mainID) }
        } else {
            unregister(&mainRef)
        }
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        if status != noErr { NSLog("FinderWheel: RegisterEventHotKey failed with status \(status)") }
        return ref
    }

    private func unregister(_ ref: inout EventHotKeyRef?) {
        if let existing = ref { UnregisterEventHotKey(existing) }
        ref = nil
    }

    private func installHandler() {
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let trigger = Unmanaged<HotkeyTrigger>.fromOpaque(userData).takeUnretainedValue()
            trigger.handle(id: hotKeyID.id, pressed: GetEventKind(event) == UInt32(kEventHotKeyPressed))
            return noErr
        }
        InstallEventHandler(GetEventDispatcherTarget(), callback, specs.count, &specs,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    private func handle(id: UInt32, pressed: Bool) {
        switch (id, pressed) {
        case (Self.mainID, true):
            guard !isHeld else { return }
            isHeld = true
            onPress?()
        case (Self.mainID, false):
            guard isHeld else { return }
            isHeld = false
            onRelease?()
            updateRegistration()
        case (Self.escapeID, true):
            onEscape?()
        default:
            break
        }
    }
}
```

- [ ] **Step 2: Add temporary logging to the app** (replace `FinderWheelApp.swift`)

```swift
import SwiftUI
import FinderWheelCore

@main
struct FinderWheelApp: App {
    private static let trigger: HotkeyTrigger = {
        let t = HotkeyTrigger(combo: .optionSpace)
        t.onPress = { NSLog("FinderWheel: press"); t.setEscapeEnabled(true) }
        t.onRelease = { NSLog("FinderWheel: release"); t.setEscapeEnabled(false) }
        t.onEscape = { NSLog("FinderWheel: escape") }
        return t
    }()

    init() { Self.trigger.start() }

    var body: some Scene {
        MenuBarExtra("Finder Wheel", systemImage: "circle.dashed") {
            Button("Quit Finder Wheel") { NSApplication.shared.terminate(nil) }
        }
    }
}
```

- [ ] **Step 3: Verify by hand**

Run: `scripts/build-app.sh && open "build/Finder Wheel.app"`
In a second terminal run: `log stream --predicate 'eventMessage CONTAINS "FinderWheel:"' --style compact`

Check each item and write the result into the commit message body:

1. Click a Finder window, hold ⌥Space for a second, release. Expected: exactly one `press` and one `release`, even though the key repeats while held.
2. In Finder, hold ⌥Space, then release Option first and Space second. Expected: one `release`. Repeat releasing Space first.
3. In Finder, hold ⌥Space and press Esc. Expected: `escape` is logged. After releasing, Esc works normally in Finder again (for example it cancels a rename).
4. Click into TextEdit and press ⌥Space. Expected: nothing is logged and a non-breaking space is typed.
5. macOS showed no Accessibility permission prompt during items 1 to 4.

If item 5 fails, or item 1 or 2 logs no `release`: stop and report to the user before continuing. The spec's fallback is to request Accessibility permission with an explanation; that changes this task and needs their decision.

Quit the app from its menu.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Add hold-to-show hotkey trigger gated on Finder"
```

---

### Task 10: Finder selection reader

Verified by hand in Step 3.

**Files:**
- Create: `Sources/FinderWheel/Trigger/FinderSelectionReader.swift`
- Modify: `Sources/FinderWheel/FinderWheelApp.swift` (temporary logging)

- [ ] **Step 1: Implement `FinderSelectionReader.swift`**

```swift
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
```

- [ ] **Step 2: Log the selection on press**

In `FinderWheelApp.swift`, add a static reader and change `onPress`:

```swift
    private static let reader = FinderSelectionReader()
```

```swift
        t.onPress = {
            do {
                let urls = try reader.read()
                let kinds = urls.map { Classifier.kind(of: $0) }
                NSLog("FinderWheel: press, \(urls.count) items, classification \(Classifier.classify(kinds).rawValue)")
            } catch {
                NSLog("FinderWheel: selection error \(error)")
            }
            t.setEscapeEnabled(true)
        }
```

- [ ] **Step 3: Verify by hand**

Run: `scripts/build-app.sh && open "build/Finder Wheel.app"` with the `log stream` command from Task 9 running.

1. Select two PNG files in Finder and press ⌥Space. Expected on first use: macOS asks "Finder Wheel wants access to control Finder". Allow it. Press again: `2 items, classification image`.
2. Select one PDF and one JPG: `classification pdfImage`.
3. Select a folder: `classification unsupported`.
4. Click empty space in the window so nothing is selected: `0 items, classification unsupported`.
5. Select a file on the Desktop (no window): the count is 1.

If item 1 never shows the prompt and logs `selection error notAuthorized`, run `tccutil reset AppleEvents com.lorenz.finderwheel` and retry.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Add Finder selection reader"
```

---

### Task 11: Wheel view and panel

The wheel is a transparent, click-through floating panel. It never becomes key, so Finder stays frontmost and keeps its selection.

Drawing rules from the spec:
- The ring is always whole: six wedges. A slot without an entry is drawn dimmed, with no icon or label.
- The targeted wedge is tinted with the accent colour.
- Each wedge with an entry shows its SF Symbol and title. Entries with more than one option also show the option that a plain release would run, in small type.
- The outer ring for an entry is visible while that entry or one of its options is targeted, and only if it has more than one option.
- The centre shows the selection summary, or "No actions for this selection" when the selection is unsupported (then all six wedges are dimmed).

**Files:**
- Create: `Sources/FinderWheel/Wheel/WedgeShape.swift`
- Create: `Sources/FinderWheel/Wheel/WheelModel.swift`
- Create: `Sources/FinderWheel/Wheel/WheelView.swift`
- Create: `Sources/FinderWheel/Wheel/WheelPanel.swift`

- [ ] **Step 1: Implement `WedgeShape.swift`**

```swift
import SwiftUI

/// A section of a ring. Angles are in degrees, clockwise from the top.
/// `gap` is the constant-width space left to the neighbouring wedge, in points.
struct WedgeShape: Shape {
    var centerDegrees: Double
    var spanDegrees: Double
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    var gap: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // SwiftUI measures angles from the positive x axis; with y pointing down,
        // increasing angles run clockwise on screen. "Up" is therefore -90°.
        func edges(at radius: CGFloat) -> (start: Angle, end: Angle) {
            let inset = Double(gap / 2 / radius) * 180 / .pi
            return (.degrees(centerDegrees - spanDegrees / 2 + inset - 90),
                    .degrees(centerDegrees + spanDegrees / 2 - inset - 90))
        }
        let outer = edges(at: outerRadius)
        let inner = edges(at: innerRadius)
        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: outer.start, endAngle: outer.end, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: inner.end, endAngle: inner.start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

extension CGPoint {
    /// The point at `radius` from `center` in the direction `degrees` clockwise from the top (y down).
    static func polar(center: CGPoint, degrees: Double, radius: CGFloat) -> CGPoint {
        let r = degrees * .pi / 180
        return CGPoint(x: center.x + CGFloat(sin(r)) * radius, y: center.y - CGFloat(cos(r)) * radius)
    }
}
```

- [ ] **Step 2: Implement `WheelModel.swift`**

```swift
import SwiftUI
import FinderWheelCore

/// Everything the wheel view draws. Written by `WheelController`.
@MainActor
@Observable
final class WheelModel {
    var entries: [WheelEntry] = []
    /// Option a plain release would run, per slot. Only shown for entries with several options.
    var releaseOptionTitles: [Slot: String] = [:]
    var summary = ""
    var isUnsupported = false
    var hit: WheelHit = .none
    var metrics = WheelMetrics()
    /// Flipped to true right after the panel is shown, to drive the appear animation.
    var isVisible = false

    func entry(at slot: Slot) -> WheelEntry? { entries.first { $0.slot == slot } }

    /// The slot whose outer ring should be visible, if any.
    var expandedSlot: Slot? {
        let slot: Slot?
        switch hit {
        case .none: slot = nil
        case .entry(let s): slot = s
        case .option(let s, _): slot = s
        }
        guard let slot, let entry = entry(at: slot), entry.options.count > 1 else { return nil }
        return slot
    }
}
```

- [ ] **Step 3: Implement `WheelView.swift`**

```swift
import SwiftUI
import FinderWheelCore

struct WheelView: View {
    let model: WheelModel

    /// The panel is this size; the wheel is centred in it.
    static let side: CGFloat = 460

    var body: some View {
        let m = model.metrics
        let center = CGPoint(x: Self.side / 2, y: Self.side / 2)
        ZStack {
            GlassEffectContainer {
                ZStack {
                    ForEach(Slot.allCases, id: \.self) { slot in
                        wedge(slot, metrics: m)
                    }
                    if let slot = model.expandedSlot, let entry = model.entry(at: slot) {
                        ForEach(Array(entry.options.enumerated()), id: \.offset) { index, _ in
                            optionWedge(slot: slot, index: index, count: entry.options.count, metrics: m)
                        }
                    }
                    Circle()
                        .fill(.clear)
                        .frame(width: (m.deadZone - 6) * 2, height: (m.deadZone - 6) * 2)
                        .glassEffect(.regular, in: Circle())
                }
            }
            ForEach(model.entries, id: \.slot) { entry in
                wedgeLabel(entry)
                    .position(.polar(center: center, degrees: Double(entry.slot.rawValue) * 60, radius: (m.deadZone + m.ringOuter) / 2))
            }
            if let slot = model.expandedSlot, let entry = model.entry(at: slot) {
                ForEach(Array(entry.options.enumerated()), id: \.offset) { index, option in
                    Text(option.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isOptionHit(slot, index) ? Color.white : Color.primary)
                        .position(.polar(center: center,
                                         degrees: m.optionAngle(slot: slot, index: index, count: entry.options.count),
                                         radius: (m.ringOuter + m.outerRingOuter) / 2))
                }
            }
            Text(model.isUnsupported ? "No actions for\nthis selection" : model.summary)
                .font(.system(size: 11, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(width: m.deadZone * 2 - 20)
        }
        .frame(width: Self.side, height: Self.side)
        .scaleEffect(model.isVisible ? 1 : 0.9)
        .opacity(model.isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: model.isVisible)
        .animation(.easeOut(duration: 0.1), value: model.hit)
    }

    private func isEntryHit(_ slot: Slot) -> Bool {
        switch model.hit {
        case .entry(let s): return s == slot
        case .option(let s, _): return s == slot
        case .none: return false
        }
    }

    private func isOptionHit(_ slot: Slot, _ index: Int) -> Bool {
        model.hit == .option(slot, index)
    }

    private func wedge(_ slot: Slot, metrics m: WheelMetrics) -> some View {
        let hasEntry = model.entry(at: slot) != nil
        let active = isEntryHit(slot)
        return Color.clear
            .frame(width: Self.side, height: Self.side)
            .glassEffect(active ? .regular.tint(.accentColor) : .regular,
                         in: WedgeShape(centerDegrees: Double(slot.rawValue) * 60, spanDegrees: 60,
                                        innerRadius: m.deadZone, outerRadius: m.ringOuter))
            .opacity(hasEntry ? 1 : 0.35)
    }

    private func optionWedge(slot: Slot, index: Int, count: Int, metrics m: WheelMetrics) -> some View {
        Color.clear
            .frame(width: Self.side, height: Self.side)
            .glassEffect(isOptionHit(slot, index) ? .regular.tint(.accentColor) : .regular,
                         in: WedgeShape(centerDegrees: m.optionAngle(slot: slot, index: index, count: count),
                                        spanDegrees: m.optionArc, innerRadius: m.ringOuter + 4, outerRadius: m.outerRingOuter))
            .transition(.opacity)
    }

    private func wedgeLabel(_ entry: WheelEntry) -> some View {
        let active = isEntryHit(entry.slot)
        return VStack(spacing: 3) {
            Image(systemName: entry.symbol)
                .font(.system(size: 19, weight: .medium))
            Text(entry.title)
                .font(.system(size: 12, weight: .semibold))
            if let hint = model.releaseOptionTitles[entry.slot] {
                Text(hint)
                    .font(.system(size: 9.5, weight: .medium))
                    .opacity(0.7)
            }
        }
        .foregroundStyle(active ? Color.white : Color.primary)
    }
}
```

- [ ] **Step 4: Implement `WheelPanel.swift`**

```swift
import AppKit
import SwiftUI

/// Transparent, click-through, never-key panel that hosts the wheel.
final class WheelPanel: NSPanel {
    init(model: WheelModel) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: WheelView.side, height: WheelView.side),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: WheelView(model: model))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows the panel with its centre at `point` (screen coordinates).
    func show(centeredAt point: NSPoint) {
        setFrameOrigin(NSPoint(x: point.x - WheelView.side / 2, y: point.y - WheelView.side / 2))
        orderFrontRegardless()
    }
}
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: builds without errors. (The wheel is shown for the first time in Task 12.)

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add glass wheel view and floating panel"
```

---

### Task 12: Wheel controller, menu bar and app wiring

**Files:**
- Create: `Sources/FinderWheel/Wheel/WheelController.swift`
- Create: `Sources/FinderWheel/MenuBar/StatusIcon.swift`
- Create: `Sources/FinderWheel/MenuBar/MenuBarView.swift`
- Create: `Sources/FinderWheel/AppController.swift`
- Modify: `Sources/FinderWheel/FinderWheelApp.swift` (final form, temporary logging removed)

- [ ] **Step 1: Implement `WheelController.swift`**

```swift
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
```

- [ ] **Step 2: Implement `StatusIcon.swift`**

```swift
import AppKit

/// Draws the menu bar icon: a ring of six dots when idle, a progress arc while jobs run,
/// and a dot in the corner when a job reported a failure.
enum StatusIcon {
    static func image(progress: Double?, warning: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            NSColor.black.set()
            if let progress {
                let track = NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3))
                track.lineWidth = 2
                NSColor.black.withAlphaComponent(0.3).setStroke()
                track.stroke()
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: 6, startAngle: 90,
                              endAngle: 90 - CGFloat(max(0.03, min(1, progress))) * 360, clockwise: true)
                arc.lineWidth = 2
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            } else {
                for i in 0..<6 {
                    let angle = CGFloat(i) * .pi / 3
                    let dot = NSRect(x: center.x + sin(angle) * 5.5 - 1.6, y: center.y + cos(angle) * 5.5 - 1.6, width: 3.2, height: 3.2)
                    NSBezierPath(ovalIn: dot).fill()
                }
            }
            if warning {
                NSBezierPath(ovalIn: NSRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 6, height: 6)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
```

- [ ] **Step 3: Implement `MenuBarView.swift`**

```swift
import SwiftUI
import FinderWheelCore

struct MenuBarView: View {
    let controller: AppController

    var body: some View {
        let jobs = controller.jobCenter
        VStack(alignment: .leading, spacing: 10) {
            if let problem = controller.permissionProblem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                Button("Open Automation Settings") { controller.openAutomationSettings() }
                Divider()
            }
            if jobs.jobs.isEmpty {
                Text("No recent jobs")
                    .foregroundStyle(.secondary)
                Text("Select files in Finder and hold \(controller.hotkeyLabel).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(jobs.jobs) { job in
                            JobRow(job: job) { jobs.cancel(job.id) }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
            Divider()
            Button("Quit Finder Wheel") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { jobs.clearWarning() }
    }
}

private struct JobRow: View {
    let job: JobCenter.Job
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(job.title).font(.callout.weight(.medium))
                Spacer()
                switch job.state {
                case .running:
                    Button("Cancel", action: cancel).controlSize(.small)
                case .cancelled:
                    Text("Cancelled").font(.caption).foregroundStyle(.secondary)
                case .finished:
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
            }
            if job.state == .running {
                ProgressView(value: job.progress)
            }
            ForEach(job.notes) { note in
                Label("\(note.file): \(note.message)", systemImage: note.isFailure ? "exclamationmark.triangle" : "arrow.uturn.right")
                    .font(.caption)
                    .foregroundStyle(note.isFailure ? Color.primary : Color.secondary)
            }
        }
    }

    private var summary: String {
        let made = job.outputs.count
        return made == 1 ? "1 item created" : "\(made) items created"
    }
}
```

- [ ] **Step 4: Implement `AppController.swift`**

```swift
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
        wheel.onChoice = { [weak self] choice in self?.run(choice) }
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
        let title = choice.entry.options.count > 1 ? "\(choice.entry.title) to \(choice.option.title)" : choice.entry.title
        jobCenter.start(title: title, inputs: choice.inputs, kind: choice.option.action, settings: settingsSnapshot())
    }
}
```

- [ ] **Step 5: Final `FinderWheelApp.swift`** (replace the file)

```swift
import SwiftUI
import FinderWheelCore

@main
struct FinderWheelApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(controller: controller)
        } label: {
            let jobs = controller.jobCenter
            Image(nsImage: StatusIcon.image(progress: jobs.isRunning ? jobs.overallProgress : nil,
                                            warning: jobs.hasWarning || controller.permissionProblem != nil))
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 6: Build and run the unit tests**

Run: `swift test`
Expected: PASS, all suites; the app target compiles.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Wire wheel controller, menu bar and app controller"
```

---

### Task 13: End-to-end verification

**Files:**
- Create: `docs/manual-checks.md`

- [ ] **Step 1: Write `docs/manual-checks.md`**

```markdown
# Manual checks

Run after every plan. Build and start with `scripts/build-app.sh && open "build/Finder Wheel.app"`.
After a rebuild macOS may ask again for permission to control Finder; allow it.

## Plan 1: foundation

Prepare a folder with: two PNG screenshots, one HEIC or JPG photo taken with location on, one PDF, one folder.

1. Select the two PNGs, hold ⌥Space. The glass wheel appears centred on the cursor; the centre reads "2 images".
2. Convert is upper right, Compress lower right, Cut out lower left, Combine upper left, Markdown up. The bottom wedge is dimmed and empty.
3. Slide to Convert: the wedge tints, and an outer ring with JPG, PNG, HEIC, TIFF appears.
4. Release on Convert: the wheel disappears at once; two JPG files appear next to the originals and are selected in Finder. The originals are unchanged.
5. Repeat and release on Convert again: two more files named `...-2.jpg` appear.
6. Hold, slide through Convert outward to HEIC, release: HEIC files appear. Hold again: the Convert wedge now shows "HEIC" as its small hint, and a plain release converts to HEIC.
7. Select a JPG and convert to JPG: no file appears; the menu bar menu lists the file as "Already JPG".
8. Convert the location-tagged photo to PNG or JPG. In Preview's inspector (⌘I) the result has no GPS tab.
9. Hold ⌥Space and press Esc: the wheel disappears and nothing runs. Release in the centre: nothing runs.
10. Select the folder, hold ⌥Space: all wedges are dimmed and the centre reads "No actions for this selection" for as long as the key is held.
11. Select nothing, press ⌥Space: nothing appears.
12. In another app (TextEdit), ⌥Space types a non-breaking space and no wheel appears.
13. With the trackpad only: hold ⌥Space with one hand, slide on the trackpad, release the key. Same results as with a mouse.
14. During a conversion of 20 or more images, the menu bar icon shows a progress ring; the menu lists the job with a Cancel button.
15. Appearance: check the wheel over a light window, a dark window and the desktop picture, in light and dark mode. Labels stay readable.
16. Flick quickly from the centre past the ring edge in the Convert direction. Note whether an outer-ring option is chosen by accident; if it happens often, raise `ringOuter` in `WheelMetrics` and re-run `swift test`.
17. Slots that are not implemented yet (everything except image Convert) report "This action is not available for this file" in the menu. This is expected until Plans 2 and 3.
```

- [ ] **Step 2: Run the checks**

Run: `scripts/build-app.sh && open "build/Finder Wheel.app"`
Work through items 1 to 17. For each item that fails, fix the cause, re-run `swift test`, rebuild and re-check. Do not change behaviour that the spec defines; if a check contradicts the spec, stop and ask the user.

Likely fixes:
- Glass looks flat or grey in the non-key panel: wrap the `ZStack` in `WheelView` with `.environment(\.controlActiveState, .key)`; if still flat, set `panel.appearance` from `NSApp.effectiveAppearance` before showing.
- Wedge labels unreadable on bright backgrounds: use `.regular.tint(.black.opacity(0.15))` for inactive wedges.

- [ ] **Step 3: Record the permission result in the spec**

In `docs/superpowers/specs/2026-11-12-finder-wheel-design.md`, section "Permissions", replace the paragraph that begins "The hold-hotkey is expected to work without Accessibility permission" with the verified result, for example: "Verified in Plan 1: the hold-hotkey, Esc and Finder-only registration work without Accessibility permission." If Accessibility turned out to be needed, describe what was implemented instead.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Add manual checks and record permission verification"
```

**Plan 1 is complete when:** `swift test` passes, checks 1 to 17 pass, and the spec's permission paragraph states the verified result. Continue with Plan 2.
