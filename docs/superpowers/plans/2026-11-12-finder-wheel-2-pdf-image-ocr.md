# Finder Wheel, Plan 2 of 3: PDF, Image and OCR Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every PDF and image wedge works: Compress, Cut out, PDF to images, Split, Combine with the reorder strip, and Markdown through Mistral OCR, plus the settings window.

**Architecture:** Each action is one `FileAction` in `FinderWheelCore/Actions`, registered in `ActionRouter`. Combine is a batch operation started through `JobCenter.startBatch` after the reorder strip returns the final order. Settings live in an observable `AppSettings` object backed by UserDefaults and the Keychain; jobs receive an immutable `SettingsSnapshot`.

**Tech Stack:** PDFKit, Quartz (`QuartzFilter`), ImageIO, Vision, QuickLookThumbnailing, Security (Keychain), URLSession, Mistral OCR HTTP API.

**Spec:** `docs/superpowers/specs/2026-11-12-finder-wheel-design.md`
**Prerequisite:** Plan 1 (`2026-11-12-finder-wheel-1-foundation.md`) is complete. Its "Conventions for all three plans" section applies here.

---

## Facts verified before writing this plan

- `PDFDocument.write(to:withOptions:)` with the option key `PDFDocumentWriteOption(rawValue: "QuartzFilter")` and a `QuartzFilter` loaded from a generated `.qfilter` file downsamples and recompresses images. Measured on this Mac with a 4.7 MB image PDF: 200 dpi gave 2.0 MB, 150 dpi 0.96 MB, 100 dpi 0.35 MB.
- Vision: `VNGenerateForegroundInstanceMaskRequest` results expose `allInstances` and `generateMaskedImage(ofInstances:from:croppedToInstancesExtent:)`.
- Mistral OCR: `POST https://api.mistral.ai/v1/ocr`, header `Authorization: Bearer <key>`, JSON body `{"model": "mistral-ocr-latest", "document": {...}, "include_image_base64": false}`. For a PDF the document is `{"type": "document_url", "document_url": "data:application/pdf;base64,<data>"}`. For an image it is `{"type": "image_url", "image_url": "data:image/jpeg;base64,<data>"}`. The response is `{"pages": [{"index": 0, "markdown": "..."}]}`. Before implementing Task 9, open https://docs.mistral.ai/capabilities/document_ai/basic_ocr and confirm these field names; if they changed, follow the documentation and adjust the tests to match.

## File structure (added by this plan)

```
Sources/FinderWheelCore/
  Actions/SizeCheck.swift            "output must be smaller than input" helper
  Actions/ImageCompressAction.swift
  Actions/CutOutAction.swift
  Actions/PDFToImagesAction.swift
  Actions/PDFSplitAction.swift
  Actions/PDFCompressAction.swift
  Actions/CombineAction.swift        batch: PDFs and images into one PDF
  Actions/MistralClient.swift        request building, response parsing, transport
  Actions/MarkdownOCRAction.swift
  Jobs/Reorder.swift                 natural filename order, move helper
  Settings/SecretStore.swift         SecretStore protocol, Keychain and in-memory stores
  Settings/AppSettings.swift         observable settings, makes SettingsSnapshot
Sources/FinderWheel/
  Reorder/ReorderModel.swift
  Reorder/ReorderView.swift
  Reorder/ReorderPanel.swift
  Settings/SettingsView.swift
  Settings/SettingsWindowController.swift
Tests/FinderWheelCoreTests/
  ImageCompressActionTests.swift, CutOutActionTests.swift, PDFToImagesActionTests.swift,
  PDFSplitActionTests.swift, PDFCompressActionTests.swift, CombineActionTests.swift,
  ReorderTests.swift, AppSettingsTests.swift, MistralClientTests.swift, MarkdownOCRActionTests.swift
```

Modified: `Jobs/ActionRouter.swift`, `Actions/ImageIOHelper.swift`, `Tests/.../Fixtures.swift`, `Tests/.../JobCenterTests.swift`, `AppController.swift`, `MenuBar/MenuBarView.swift`, `docs/manual-checks.md`.

---

### Task 1: Test fixtures for noisy images and PDFs

**Files:**
- Modify: `Tests/FinderWheelCoreTests/Fixtures.swift`

- [ ] **Step 1: Add these members inside `enum Fixtures`**

Add `import CoreText` and `import PDFKit` at the top of the file, then:

```swift
    /// Pseudo-random pixels. Compresses badly, so size comparisons are meaningful.
    static func noiseImage(width: Int, height: Int) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        var seed: UInt32 = 12345
        for i in 0..<(width * height) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            bytes[i * 4] = UInt8(truncatingIfNeeded: seed >> 16)
            bytes[i * 4 + 1] = UInt8(truncatingIfNeeded: seed >> 8)
            bytes[i * 4 + 2] = UInt8((i % width) * 255 / width)
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// Writes a noisy image at the given lossy quality.
    @discardableResult
    static func writeNoiseImage(to url: URL, type: UTType, width: Int = 1200, height: Int = 800, quality: Double = 1.0) -> URL {
        let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, noiseImage(width: width, height: height),
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        precondition(CGImageDestinationFinalize(dest))
        return url
    }

    static func pixelSize(_ url: URL) -> (width: Int, height: Int) {
        let props = imageProperties(url)
        return (props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    /// Writes an A4 PDF. Page n contains the text "<label> <n>". With `imageHeavy`,
    /// every page also carries a large noisy image.
    @discardableResult
    static func writePDF(to url: URL, pages: Int, label: String = "Page", imageHeavy: Bool = false) -> URL {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
        let font = CTFontCreateWithName("Helvetica" as CFString, 48, nil)
        let image = imageHeavy ? noiseImage(width: 1400, height: 1400) : nil
        for i in 0..<pages {
            ctx.beginPDFPage(nil)
            if let image { ctx.draw(image, in: CGRect(x: 0, y: 0, width: 595, height: 595)) }
            let text = NSAttributedString(string: "\(label) \(i + 1)",
                                          attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            ctx.textPosition = CGPoint(x: 72, y: 720)
            CTLineDraw(CTLineCreateWithAttributedString(text), ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    /// The text of every page of a PDF, trimmed.
    static func pdfPageTexts(_ url: URL) -> [String] {
        guard let doc = PDFDocument(url: url) else { return [] }
        return (0..<doc.pageCount).map { (doc.page(at: $0)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    }
```

- [ ] **Step 2: Verify the suite still builds and passes**

Run: `swift test`
Expected: PASS, same tests as before.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "Add noisy image and PDF test fixtures"
```

---

### Task 2: Image Compress

Behaviour (spec, presets table):
- Light, medium, strong use lossy quality 0.8, 0.6, 0.4.
- JPG and HEIC inputs keep their format and extension.
- PNG, TIFF and WebP inputs are written as JPG, with transparency flattened onto white.
- Resize limits the longest side to 2000 px at quality 0.6, with the same format rule.
- Output is `<name>-compressed.<ext>`.
- If the result is not smaller than the input, nothing is written and the file is skipped with "Already as small as it gets".
- Location metadata follows `settings.stripLocation`.

**Files:**
- Create: `Sources/FinderWheelCore/Actions/SizeCheck.swift`
- Create: `Sources/FinderWheelCore/Actions/ImageCompressAction.swift`
- Create: `Tests/FinderWheelCoreTests/ImageCompressActionTests.swift`
- Modify: `Sources/FinderWheelCore/Jobs/ActionRouter.swift`
- Modify: `Tests/FinderWheelCoreTests/JobCenterTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
import UniformTypeIdentifiers
@testable import FinderWheelCore

@Suite struct ImageCompressActionTests {
    private let context = ActionContext(settings: SettingsSnapshot(), progress: { _ in })

    private func output(_ outcome: ActionOutcome) throws -> URL {
        guard case .produced(let urls) = outcome, urls.count == 1 else {
            throw ActionError("expected one output, got \(outcome)")
        }
        return urls[0]
    }

    @Test func jpegStaysJPEGAndGetsSmaller() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeNoiseImage(to: tmp.file("photo.jpg"), type: .jpeg)
        let out = try output(try await ImageCompressAction(preset: .medium).run(input: input, context: context))
        #expect(out.lastPathComponent == "photo-compressed.jpg")
        #expect(Fixtures.imageType(out) == .jpeg)
        #expect(Fixtures.fileSize(out) < Fixtures.fileSize(input))
        #expect(Fixtures.pixelSize(out).width == 1200)
    }

    @Test func strongerPresetsAreSmaller() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeNoiseImage(to: tmp.file("photo.jpg"), type: .jpeg)
        let light = try output(try await ImageCompressAction(preset: .light).run(input: input, context: context))
        let strong = try output(try await ImageCompressAction(preset: .strong).run(input: input, context: context))
        #expect(Fixtures.fileSize(strong) < Fixtures.fileSize(light))
    }

    @Test func heicStaysHEIC() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeNoiseImage(to: tmp.file("photo.heic"), type: .heic)
        let out = try output(try await ImageCompressAction(preset: .strong).run(input: input, context: context))
        #expect(out.lastPathComponent == "photo-compressed.heic")
        #expect(Fixtures.imageType(out) == .heic)
    }

    @Test func pngBecomesJPG() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeNoiseImage(to: tmp.file("shot.png"), type: .png)
        let out = try output(try await ImageCompressAction(preset: .medium).run(input: input, context: context))
        #expect(out.lastPathComponent == "shot-compressed.jpg")
        #expect(Fixtures.imageType(out) == .jpeg)
    }

    @Test func tiffBecomesJPG() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeNoiseImage(to: tmp.file("scan.tiff"), type: .tiff)
        let out = try output(try await ImageCompressAction(preset: .medium).run(input: input, context: context))
        #expect(out.lastPathComponent == "scan-compressed.jpg")
    }

    @Test func resizeLimitsLongestSide() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeNoiseImage(to: tmp.file("big.jpg"), type: .jpeg, width: 3000, height: 1500)
        let out = try output(try await ImageCompressAction(preset: .resize).run(input: input, context: context))
        let size = Fixtures.pixelSize(out)
        #expect(size.width == 2000)
        #expect(size.height == 1000)
    }

    @Test func skipsWhenNotSmaller() async throws {
        let tmp = TempFolder()
        // Already saved at very low quality: recompressing at 0.8 cannot shrink it.
        let input = Fixtures.writeNoiseImage(to: tmp.file("tiny.jpg"), type: .jpeg, width: 200, height: 200, quality: 0.05)
        let outcome = try await ImageCompressAction(preset: .light).run(input: input, context: context)
        #expect(outcome == .skipped("Already as small as it gets"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.url.path) == ["tiny.jpg"])
    }
}
```

Also add to `JobCenterTests.routerKnowsImageConvert` (rename the test to `routerKnowsImageActions`):

```swift
        #expect(ActionRouter.action(for: .compress(.medium), fileKind: .image) is ImageCompressAction)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ImageCompressActionTests`
Expected: FAIL to compile, "cannot find 'ImageCompressAction' in scope".

- [ ] **Step 3: Implement `SizeCheck.swift`**

```swift
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
```

- [ ] **Step 4: Implement `ImageCompressAction.swift`**

```swift
import Foundation
import UniformTypeIdentifiers

public struct ImageCompressAction: FileAction {
    public let preset: CompressPreset

    public init(preset: CompressPreset) { self.preset = preset }

    private var quality: Double {
        switch preset {
        case .light: return 0.8
        case .medium, .resize: return 0.6
        case .strong: return 0.4
        }
    }

    public func run(input: URL, context: ActionContext) async throws -> ActionOutcome {
        let (source, sourceType) = try ImageIOHelper.source(for: input)
        // JPG and HEIC keep their format; everything else becomes JPG.
        let keepsFormat = sourceType.conforms(to: .jpeg) || sourceType.conforms(to: .heic)
        let type: UTType = keepsFormat ? sourceType : .jpeg
        let ext = keepsFormat ? input.pathExtension : "jpg"
        let output = OutputNamer.fileURL(for: input, suffix: "compressed", ext: ext)
        do {
            try AtomicOutput.write(to: output) { temp in
                try ImageIOHelper.write(source: source, to: temp, type: type, quality: quality,
                                        maxPixel: preset == .resize ? 2000 : nil,
                                        stripLocation: context.settings.stripLocation,
                                        flattenAlpha: type.conforms(to: .jpeg))
                try SizeCheck.requireSmaller(temp, than: input)
            }
        } catch is SizeCheck.NotSmaller {
            return .skipped(SizeCheck.skipMessage)
        }
        return .produced([output])
    }
}
```

- [ ] **Step 5: Register in `ActionRouter`**

Add this case above `default:` in `ActionRouter.action(for:fileKind:)`:

```swift
        case (.compress(let preset), .image):
            return ImageCompressAction(preset: preset)
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter "ImageCompressActionTests|JobCenterTests"`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add image compress action"
```

---

### Task 3: Cut out (remove background)

Behaviour: writes `<name>-cutout.png` with the subject on a transparent background, using Vision on device. If Vision finds no subject, the action fails with "No subject found in this image".

Vision's result on synthetic test images is not predictable, so the automated test accepts either a valid transparent PNG or that specific error. The real check is manual (Task 10).

**Files:**
- Create: `Sources/FinderWheelCore/Actions/CutOutAction.swift`
- Create: `Tests/FinderWheelCoreTests/CutOutActionTests.swift`
- Modify: `Sources/FinderWheelCore/Jobs/ActionRouter.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import FinderWheelCore

@Suite struct CutOutActionTests {
    private let context = ActionContext(settings: SettingsSnapshot(), progress: { _ in })

    @Test func producesTransparentPNGOrReportsNoSubject() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeImage(to: tmp.file("photo.jpg"), type: .jpeg, width: 800, height: 600)
        do {
            let outcome = try await CutOutAction().run(input: input, context: context)
            #expect(outcome == .produced([tmp.file("photo-cutout.png")]))
            #expect(Fixtures.imageType(tmp.file("photo-cutout.png")) == .png)
            #expect(Fixtures.imageProperties(tmp.file("photo-cutout.png"))[kCGImagePropertyHasAlpha] as? Bool == true)
        } catch let error as ActionError {
            #expect(error.message == "No subject found in this image")
            #expect(!FileManager.default.fileExists(atPath: tmp.file("photo-cutout.png").path))
        }
    }

    @Test func unreadableFileThrows() async {
        let tmp = TempFolder()
        let input = tmp.touch("broken.jpg")
        await #expect(throws: (any Error).self) {
            _ = try await CutOutAction().run(input: input, context: context)
        }
    }

    @Test func routerKnowsCutOut() {
        #expect(ActionRouter.action(for: .cutOut, fileKind: .image) is CutOutAction)
        #expect(ActionRouter.action(for: .cutOut, fileKind: .pdf) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter CutOutActionTests`
Expected: FAIL to compile, "cannot find 'CutOutAction' in scope".

- [ ] **Step 3: Implement `CutOutAction.swift`**

```swift
import Foundation
import CoreImage
import Vision

public struct CutOutAction: FileAction {
    public init() {}

    public func run(input: URL, context: ActionContext) async throws -> ActionOutcome {
        let handler = VNImageRequestHandler(url: input)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw ActionError("No subject found in this image")
        }
        let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances,
                                                         from: handler, croppedToInstancesExtent: false)
        let image = CIImage(cvPixelBuffer: buffer)
        let output = OutputNamer.fileURL(for: input, suffix: "cutout", ext: "png")
        try AtomicOutput.write(to: output) { temp in
            try CIContext().writePNGRepresentation(of: image, to: temp, format: .RGBA8,
                                                   colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        }
        return .produced([output])
    }
}
```

- [ ] **Step 4: Register in `ActionRouter`**

```swift
        case (.cutOut, .image):
            return CutOutAction()
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter CutOutActionTests`
Expected: PASS, 3 tests.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add cut out action"
```

---

### Task 4: PDF to images and PDF Split

Shared behaviour:
- Output goes into a new folder next to the original named `<name>-pages`; files inside are `<name>-p01.<ext>` (see `OutputNamer.pageFileName`).
- The folder URL is the single output, so Finder selects the folder.
- A locked PDF fails with "PDF is password-protected". An unreadable file fails with "Could not read PDF".
- Progress is reported after every page.

PDF to images renders each page at 200 dpi on a white background, as PNG or JPG (quality 0.9). A page with a 90° or 270° rotation produces a rotated image.

Split writes each page as its own one-page PDF.

**Files:**
- Create: `Sources/FinderWheelCore/Actions/PDFToImagesAction.swift`
- Create: `Sources/FinderWheelCore/Actions/PDFSplitAction.swift`
- Create: `Tests/FinderWheelCoreTests/PDFToImagesActionTests.swift`
- Create: `Tests/FinderWheelCoreTests/PDFSplitActionTests.swift`
- Modify: `Sources/FinderWheelCore/Jobs/ActionRouter.swift`

- [ ] **Step 1: Write the failing tests**

`PDFToImagesActionTests.swift`:

```swift
import Testing
import Foundation
import PDFKit
import UniformTypeIdentifiers
@testable import FinderWheelCore

@Suite struct PDFToImagesActionTests {
    private let context = ActionContext(settings: SettingsSnapshot(), progress: { _ in })

    private func names(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    @Test func rendersEveryPageIntoAFolder() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("report.pdf"), pages: 3)
        let outcome = try await PDFToImagesAction(target: .png).run(input: input, context: context)
        let folder = tmp.file("report-pages")
        #expect(outcome == .produced([folder]))
        #expect(try names(in: folder) == ["report-p01.png", "report-p02.png", "report-p03.png"])
        #expect(Fixtures.imageType(folder.appendingPathComponent("report-p01.png")) == .png)
    }

    @Test func rendersAt200DPI() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("a.pdf"), pages: 1)
        _ = try await PDFToImagesAction(target: .jpg).run(input: input, context: context)
        let size = Fixtures.pixelSize(tmp.file("a-pages/a-p01.jpg"))
        // A4 is 595 x 842 pt; at 200 dpi that is 1653 x 2339 px.
        #expect(size.width == 1653)
        #expect(size.height == 2339)
        #expect(Fixtures.imageType(tmp.file("a-pages/a-p01.jpg")) == .jpeg)
    }

    @Test func rotatedPagesAreRenderedRotated() async throws {
        let tmp = TempFolder()
        let plain = Fixtures.writePDF(to: tmp.file("plain.pdf"), pages: 1)
        let doc = PDFDocument(url: plain)!
        doc.page(at: 0)!.rotation = 90
        let input = tmp.file("rotated.pdf")
        #expect(doc.write(to: input))
        _ = try await PDFToImagesAction(target: .png).run(input: input, context: context)
        let size = Fixtures.pixelSize(tmp.file("rotated-pages/rotated-p01.png"))
        #expect(size.width == 2339)
        #expect(size.height == 1653)
    }

    @Test func secondRunUsesANewFolder() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("a.pdf"), pages: 1)
        _ = try await PDFToImagesAction(target: .png).run(input: input, context: context)
        let outcome = try await PDFToImagesAction(target: .png).run(input: input, context: context)
        #expect(outcome == .produced([tmp.file("a-pages-2")]))
    }

    @Test func unreadablePDFThrows() async {
        let tmp = TempFolder()
        let input = tmp.touch("broken.pdf")
        await #expect(throws: ActionError("Could not read PDF")) {
            _ = try await PDFToImagesAction(target: .png).run(input: input, context: context)
        }
    }

    @Test func lockedPDFThrows() async throws {
        let tmp = TempFolder()
        let plain = Fixtures.writePDF(to: tmp.file("plain.pdf"), pages: 1)
        let input = tmp.file("locked.pdf")
        #expect(PDFDocument(url: plain)!.write(to: input, withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "owner"]))
        await #expect(throws: ActionError("PDF is password-protected")) {
            _ = try await PDFToImagesAction(target: .png).run(input: input, context: context)
        }
    }
}
```

`PDFSplitActionTests.swift`:

```swift
import Testing
import Foundation
import PDFKit
@testable import FinderWheelCore

@Suite struct PDFSplitActionTests {
    private let context = ActionContext(settings: SettingsSnapshot(), progress: { _ in })

    @Test func writesOnePDFPerPage() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("report.pdf"), pages: 3)
        let outcome = try await PDFSplitAction().run(input: input, context: context)
        let folder = tmp.file("report-pages")
        #expect(outcome == .produced([folder]))
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names == ["report-p01.pdf", "report-p02.pdf", "report-p03.pdf"])
        #expect(Fixtures.pdfPageTexts(folder.appendingPathComponent("report-p02.pdf")) == ["Page 2"])
        #expect(Fixtures.pdfPageTexts(input).count == 3)
    }

    @Test func lockedPDFThrows() async throws {
        let tmp = TempFolder()
        let plain = Fixtures.writePDF(to: tmp.file("plain.pdf"), pages: 2)
        let input = tmp.file("locked.pdf")
        #expect(PDFDocument(url: plain)!.write(to: input, withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "owner"]))
        await #expect(throws: ActionError("PDF is password-protected")) {
            _ = try await PDFSplitAction().run(input: input, context: context)
        }
    }

    @Test func routerKnowsPDFPageActions() {
        #expect(ActionRouter.action(for: .splitPDF, fileKind: .pdf) is PDFSplitAction)
        #expect(ActionRouter.action(for: .convert(.png), fileKind: .pdf) is PDFToImagesAction)
        #expect(ActionRouter.action(for: .convert(.jpg), fileKind: .pdf) is PDFToImagesAction)
        #expect(ActionRouter.action(for: .convert(.heic), fileKind: .pdf) == nil)
        #expect(ActionRouter.action(for: .splitPDF, fileKind: .image) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "PDFToImagesActionTests|PDFSplitActionTests"`
Expected: FAIL to compile, "cannot find 'PDFToImagesAction' in scope".

- [ ] **Step 3: Implement `PDFToImagesAction.swift`**

```swift
import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum PDFLoader {
    /// Opens a PDF for reading, with the user-facing errors the spec asks for.
    static func open(_ url: URL) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else { throw ActionError("Could not read PDF") }
        if doc.isLocked { throw ActionError("PDF is password-protected") }
        return doc
    }
}

public struct PDFToImagesAction: FileAction {
    /// `.png` or `.jpg`.
    public let target: ConvertTarget
    static let dpi: CGFloat = 200

    public init(target: ConvertTarget) { self.target = target }

    public func run(input: URL, context: ActionContext) async throws -> ActionOutcome {
        guard target == .png || target == .jpg, let type = target.imageType else {
            throw ActionError("Cannot convert a PDF to \(target.rawValue.uppercased())")
        }
        let doc = try PDFLoader.open(input)
        let base = input.deletingPathExtension().lastPathComponent
        let folder = OutputNamer.folderURL(for: input, suffix: "pages")
        try AtomicOutput.write(to: folder) { temp in
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            for index in 0..<doc.pageCount {
                try Task.checkCancellation()
                guard let page = doc.page(at: index) else { continue }
                let name = OutputNamer.pageFileName(base: base, index: index, count: doc.pageCount, ext: target.rawValue)
                try Self.render(page, to: temp.appendingPathComponent(name), type: type)
                context.progress(Double(index + 1) / Double(doc.pageCount))
            }
        }
        return .produced([folder])
    }

    private static func render(_ page: PDFPage, to url: URL, type: UTType) throws {
        let box = page.bounds(for: .mediaBox)
        let sideways = page.rotation % 180 != 0
        let pointSize = sideways ? CGSize(width: box.height, height: box.width) : box.size
        let scale = dpi / 72
        let width = Int((pointSize.width * scale).rounded())
        let height = Int((pointSize.height * scale).rounded())
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ActionError("Could not render PDF page")
        }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        // PDFPage.draw applies the page's rotation and box origin itself.
        page.draw(with: .mediaBox, to: ctx)
        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ActionError("Could not render PDF page")
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ActionError("Could not write image") }
    }
}
```

- [ ] **Step 4: Implement `PDFSplitAction.swift`**

```swift
import Foundation
import PDFKit

public struct PDFSplitAction: FileAction {
    public init() {}

    public func run(input: URL, context: ActionContext) async throws -> ActionOutcome {
        let doc = try PDFLoader.open(input)
        let base = input.deletingPathExtension().lastPathComponent
        let folder = OutputNamer.folderURL(for: input, suffix: "pages")
        try AtomicOutput.write(to: folder) { temp in
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            for index in 0..<doc.pageCount {
                try Task.checkCancellation()
                guard let page = doc.page(at: index)?.copy() as? PDFPage else { continue }
                let single = PDFDocument()
                single.insert(page, at: 0)
                let name = OutputNamer.pageFileName(base: base, index: index, count: doc.pageCount, ext: "pdf")
                guard single.write(to: temp.appendingPathComponent(name)) else {
                    throw ActionError("Could not write page \(index + 1)")
                }
                context.progress(Double(index + 1) / Double(doc.pageCount))
            }
        }
        return .produced([folder])
    }
}
```

- [ ] **Step 5: Register in `ActionRouter`**

```swift
        case (.convert(let target), .pdf) where target == .png || target == .jpg:
            return PDFToImagesAction(target: target)
        case (.splitPDF, .pdf):
            return PDFSplitAction()
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter "PDFToImagesActionTests|PDFSplitActionTests"`
Expected: PASS, 9 tests.

If `rotatedPagesAreRenderedRotated` passes but a manual look at the output shows the content drawn unrotated or clipped, `page.draw` did not apply the rotation on this SDK. In that case, before `page.draw`, apply the rotation yourself: translate and rotate the context by `page.rotation` so the page's top edge ends up at the top of the bitmap, and re-check by eye.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add PDF to images and PDF split actions"
```

---

### Task 5: PDF Compress

Behaviour (spec, presets table):
- Light, medium, strong downsample embedded images to 200, 150, 100 dpi and store them as JPEG at quality 0.7, 0.5, 0.35.
- Output is `<name>-compressed.pdf`.
- Not smaller than the input: skipped with "Already as small as it gets". This is the expected result for text-only PDFs.
- Locked PDF: "PDF is password-protected".
- `.resize` is never offered for PDFs; treat it as medium.

**Files:**
- Create: `Sources/FinderWheelCore/Actions/PDFCompressAction.swift`
- Create: `Tests/FinderWheelCoreTests/PDFCompressActionTests.swift`
- Modify: `Sources/FinderWheelCore/Jobs/ActionRouter.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
import PDFKit
@testable import FinderWheelCore

@Suite struct PDFCompressActionTests {
    private let context = ActionContext(settings: SettingsSnapshot(), progress: { _ in })

    @Test func imageHeavyPDFGetsSmallerAndKeepsItsPages() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("scan.pdf"), pages: 2, imageHeavy: true)
        let outcome = try await PDFCompressAction(preset: .strong).run(input: input, context: context)
        let out = tmp.file("scan-compressed.pdf")
        #expect(outcome == .produced([out]))
        #expect(Fixtures.fileSize(out) < Fixtures.fileSize(input) / 2)
        #expect(Fixtures.pdfPageTexts(out) == ["Page 1", "Page 2"])
    }

    @Test func strongIsSmallerThanLight() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("scan.pdf"), pages: 1, imageHeavy: true)
        guard case .produced(let light) = try await PDFCompressAction(preset: .light).run(input: input, context: context),
              case .produced(let strong) = try await PDFCompressAction(preset: .strong).run(input: input, context: context) else {
            Issue.record("expected both presets to produce output")
            return
        }
        #expect(Fixtures.fileSize(strong[0]) < Fixtures.fileSize(light[0]))
    }

    @Test func textOnlyPDFIsSkippedOrSmaller() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("text.pdf"), pages: 3)
        switch try await PDFCompressAction(preset: .medium).run(input: input, context: context) {
        case .skipped(let reason):
            #expect(reason == "Already as small as it gets")
            #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.url.path) == ["text.pdf"])
        case .produced(let urls):
            #expect(Fixtures.fileSize(urls[0]) < Fixtures.fileSize(input))
        }
    }

    @Test func lockedPDFThrows() async throws {
        let tmp = TempFolder()
        let plain = Fixtures.writePDF(to: tmp.file("plain.pdf"), pages: 1)
        let input = tmp.file("locked.pdf")
        #expect(PDFDocument(url: plain)!.write(to: input, withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "owner"]))
        await #expect(throws: ActionError("PDF is password-protected")) {
            _ = try await PDFCompressAction(preset: .medium).run(input: input, context: context)
        }
    }

    @Test func routerKnowsPDFCompress() {
        #expect(ActionRouter.action(for: .compress(.light), fileKind: .pdf) is PDFCompressAction)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter PDFCompressActionTests`
Expected: FAIL to compile, "cannot find 'PDFCompressAction' in scope".

- [ ] **Step 3: Implement `PDFCompressAction.swift`**

```swift
import Foundation
import PDFKit
import Quartz

public struct PDFCompressAction: FileAction {
    public let preset: CompressPreset

    public init(preset: CompressPreset) { self.preset = preset }

    private var imageSettings: (dpi: Int, quality: Double) {
        switch preset {
        case .light: return (200, 0.7)
        case .medium, .resize: return (150, 0.5)
        case .strong: return (100, 0.35)
        }
    }

    public func run(input: URL, context: ActionContext) async throws -> ActionOutcome {
        let doc = try PDFLoader.open(input)
        let output = OutputNamer.fileURL(for: input, suffix: "compressed", ext: "pdf")
        do {
            try AtomicOutput.write(to: output) { temp in
                // The filter file lives in the same private temp folder and is removed with it.
                let filterURL = temp.deletingLastPathComponent().appendingPathComponent("compress.qfilter")
                try Self.filterPlist(dpi: imageSettings.dpi, quality: imageSettings.quality).write(to: filterURL)
                guard let filter = QuartzFilter(url: filterURL) else { throw ActionError("Could not set up PDF compression") }
                let options: [PDFDocumentWriteOption: Any] = [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter]
                guard doc.write(to: temp, withOptions: options) else { throw ActionError("Could not write PDF") }
                try SizeCheck.requireSmaller(temp, than: input)
            }
        } catch is SizeCheck.NotSmaller {
            return .skipped(SizeCheck.skipMessage)
        }
        return .produced([output])
    }

    /// A Quartz filter that downsamples images to `dpi` and stores them as JPEG.
    private static func filterPlist(dpi: Int, quality: Double) throws -> Data {
        let plist: [String: Any] = [
            "Domains": ["Applications": true, "Printing": true],
            "FilterType": 1,
            "Name": "Finder Wheel \(dpi) dpi",
            "FilterData": [
                "ColorSettings": [
                    "ImageSettings": [
                        "Compression Quality": quality,
                        "ImageCompression": "ImageJPEGCompress",
                        "ImageScaleSettings": [
                            "ImageResolution": dpi,
                            "ImageScaleFactor": 0,
                            "ImageScaleInterpolate": true,
                            "ImageSizeMax": 0,
                            "ImageSizeMin": 0,
                        ],
                    ],
                ],
            ],
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
}
```

- [ ] **Step 4: Register in `ActionRouter`**

```swift
        case (.compress(let preset), .pdf):
            return PDFCompressAction(preset: preset)
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter PDFCompressActionTests`
Expected: PASS, 5 tests.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add PDF compress action"
```

---

### Task 6: Combine and ordering helpers

`CombineAction` is a batch operation, not a `FileAction`: it takes the files in their final order and writes one PDF.

Behaviour:
- PDFs contribute all their pages unchanged. Images contribute one page each, scaled to fit an A4 page (595 x 842 pt) in the image's orientation, so phone photos do not become poster-sized pages. The image keeps its full resolution.
- Output is `<first file's name>-merged.pdf` next to the first file in the given order.
- A locked or unreadable PDF, or an unreadable image, fails the whole operation and names the file: "report.pdf: PDF is password-protected".
- Fewer than one input fails with "Nothing to combine".

`Reorder` holds the two pure helpers the reorder strip needs: natural filename order (1, 2, 10) and moving an element onto another's position.

**Files:**
- Create: `Sources/FinderWheelCore/Actions/CombineAction.swift`
- Create: `Sources/FinderWheelCore/Jobs/Reorder.swift`
- Create: `Tests/FinderWheelCoreTests/CombineActionTests.swift`
- Create: `Tests/FinderWheelCoreTests/ReorderTests.swift`

- [ ] **Step 1: Write the failing tests**

`ReorderTests.swift`:

```swift
import Testing
import Foundation
@testable import FinderWheelCore

@Suite struct ReorderTests {
    private func urls(_ names: [String]) -> [URL] { names.map { URL(fileURLWithPath: "/tmp/\($0)") } }

    @Test func naturalOrderSortsNumbersNumerically() {
        let sorted = Reorder.naturalOrder(urls(["10 Appendix.pdf", "2 Intro.pdf", "1 Cover.pdf", "b.pdf", "A.pdf"]))
        #expect(sorted.map(\.lastPathComponent) == ["1 Cover.pdf", "2 Intro.pdf", "10 Appendix.pdf", "A.pdf", "b.pdf"])
    }

    @Test func moveForwardPlacesAfterTarget() {
        #expect(Reorder.move("a", onto: "c", in: ["a", "b", "c", "d"]) == ["b", "c", "a", "d"])
    }

    @Test func moveBackwardPlacesBeforeTarget() {
        #expect(Reorder.move("d", onto: "b", in: ["a", "b", "c", "d"]) == ["a", "d", "b", "c"])
    }

    @Test func moveOntoItselfOrUnknownIsANoOp() {
        #expect(Reorder.move("b", onto: "b", in: ["a", "b", "c"]) == ["a", "b", "c"])
        #expect(Reorder.move("x", onto: "b", in: ["a", "b", "c"]) == ["a", "b", "c"])
        #expect(Reorder.move("a", onto: "x", in: ["a", "b", "c"]) == ["a", "b", "c"])
    }
}
```

`CombineActionTests.swift`:

```swift
import Testing
import Foundation
import PDFKit
import UniformTypeIdentifiers
@testable import FinderWheelCore

@Suite struct CombineActionTests {
    private let context = ActionContext(settings: SettingsSnapshot(), progress: { _ in })

    @Test func mergesPDFsInTheGivenOrder() async throws {
        let tmp = TempFolder()
        let a = Fixtures.writePDF(to: tmp.file("a.pdf"), pages: 2, label: "A")
        let b = Fixtures.writePDF(to: tmp.file("b.pdf"), pages: 1, label: "B")
        let out = try await CombineAction().run(inputs: [b, a], context: context)
        #expect(out == tmp.file("b-merged.pdf"))
        #expect(Fixtures.pdfPageTexts(out) == ["B 1", "A 1", "A 2"])
        #expect(Fixtures.pdfPageTexts(a).count == 2)
    }

    @Test func imagesBecomePages() async throws {
        let tmp = TempFolder()
        let one = Fixtures.writeImage(to: tmp.file("1.png"), type: .png, width: 400, height: 300)
        let two = Fixtures.writeImage(to: tmp.file("2.jpg"), type: .jpeg, width: 300, height: 400)
        let out = try await CombineAction().run(inputs: [one, two], context: context)
        #expect(out == tmp.file("1-merged.pdf"))
        let doc = PDFDocument(url: out)!
        #expect(doc.pageCount == 2)
        let first = doc.page(at: 0)!.bounds(for: .mediaBox)
        let second = doc.page(at: 1)!.bounds(for: .mediaBox)
        // 400 x 300 fits a landscape A4 page at 793 x 595; 300 x 400 fits portrait at 595 x 793.
        #expect(abs(first.width - 793.3) < 1)
        #expect(abs(first.height - 595) < 1)
        #expect(abs(second.width - 595) < 1)
        #expect(abs(second.height - 793.3) < 1)
    }

    @Test func mixesPDFsAndImages() async throws {
        let tmp = TempFolder()
        let pdf = Fixtures.writePDF(to: tmp.file("doc.pdf"), pages: 2)
        let image = Fixtures.writeImage(to: tmp.file("photo.jpg"), type: .jpeg)
        let out = try await CombineAction().run(inputs: [image, pdf], context: context)
        #expect(out == tmp.file("photo-merged.pdf"))
        #expect(PDFDocument(url: out)!.pageCount == 3)
    }

    @Test func singleImageBecomesAOnePagePDF() async throws {
        let tmp = TempFolder()
        let image = Fixtures.writeImage(to: tmp.file("photo.jpg"), type: .jpeg)
        let out = try await CombineAction().run(inputs: [image], context: context)
        #expect(PDFDocument(url: out)!.pageCount == 1)
    }

    @Test func lockedPDFFailsAndNamesTheFile() async throws {
        let tmp = TempFolder()
        let plain = Fixtures.writePDF(to: tmp.file("plain.pdf"), pages: 1)
        let locked = tmp.file("locked.pdf")
        #expect(PDFDocument(url: plain)!.write(to: locked, withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "owner"]))
        await #expect(throws: ActionError("locked.pdf: PDF is password-protected")) {
            _ = try await CombineAction().run(inputs: [plain, locked], context: context)
        }
        #expect(!FileManager.default.fileExists(atPath: tmp.file("plain-merged.pdf").path))
    }

    @Test func emptyInputFails() async {
        await #expect(throws: ActionError("Nothing to combine")) {
            _ = try await CombineAction().run(inputs: [], context: context)
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "ReorderTests|CombineActionTests"`
Expected: FAIL to compile, "cannot find 'Reorder' in scope".

- [ ] **Step 3: Implement `Reorder.swift`**

```swift
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
```

- [ ] **Step 4: Implement `CombineAction.swift`**

```swift
import Foundation
import AppKit
import PDFKit

/// Combines PDFs and images, in the given order, into one PDF.
public struct CombineAction: Sendable {
    public init() {}

    public func run(inputs: [URL], context: ActionContext) async throws -> URL {
        guard let first = inputs.first else { throw ActionError("Nothing to combine") }
        let merged = PDFDocument()
        for (index, input) in inputs.enumerated() {
            try Task.checkCancellation()
            do {
                try Self.append(input, to: merged)
            } catch let error as ActionError {
                throw ActionError("\(input.lastPathComponent): \(error.message)")
            }
            context.progress(Double(index + 1) / Double(inputs.count + 1))
        }
        let output = OutputNamer.fileURL(for: first, suffix: "merged", ext: "pdf")
        try AtomicOutput.write(to: output) { temp in
            guard merged.write(to: temp) else { throw ActionError("Could not write PDF") }
        }
        context.progress(1)
        return output
    }

    private static func append(_ input: URL, to merged: PDFDocument) throws {
        switch Classifier.kind(of: input) {
        case .pdf:
            let doc = try PDFLoader.open(input)
            for index in 0..<doc.pageCount {
                guard let page = doc.page(at: index)?.copy() as? PDFPage else { continue }
                merged.insert(page, at: merged.pageCount)
            }
        case .image:
            guard let image = NSImage(contentsOf: input), image.size.width > 0, image.size.height > 0 else {
                throw ActionError("Could not read image")
            }
            // Fit the page to A4 in the image's orientation. Only the page size changes;
            // the pixels are embedded as they are.
            let landscape = image.size.width > image.size.height
            let box = landscape ? CGSize(width: 842, height: 595) : CGSize(width: 595, height: 842)
            let scale = min(box.width / image.size.width, box.height / image.size.height)
            image.size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            guard let page = PDFPage(image: image) else { throw ActionError("Could not read image") }
            merged.insert(page, at: merged.pageCount)
        case .video, .audio, .unsupported:
            throw ActionError("Cannot be combined into a PDF")
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter "ReorderTests|CombineActionTests"`
Expected: PASS, 10 tests.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add combine action and ordering helpers"
```

---

### Task 7: Reorder strip and Combine wiring

Spec: after Combine is chosen, a slim panel appears at the cursor with one thumbnail per file, pre-sorted by filename in natural order. Return merges immediately; thumbnails can be dragged to reorder first; Esc cancels.

The panel can become key (it needs Return, Esc and drags) but does not activate the app, so Finder stays frontmost.

**Files:**
- Create: `Sources/FinderWheel/Reorder/ReorderModel.swift`
- Create: `Sources/FinderWheel/Reorder/ReorderView.swift`
- Create: `Sources/FinderWheel/Reorder/ReorderPanel.swift`
- Modify: `Sources/FinderWheel/AppController.swift`

- [ ] **Step 1: Implement `ReorderModel.swift`**

```swift
import AppKit
import QuickLookThumbnailing
import FinderWheelCore

struct ReorderItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

@MainActor
@Observable
final class ReorderModel {
    var items: [ReorderItem]
    var thumbnails: [UUID: NSImage] = [:]

    init(urls: [URL]) {
        items = Reorder.naturalOrder(urls).map { ReorderItem(url: $0) }
    }

    func move(id: UUID, onto targetID: UUID) {
        guard let item = items.first(where: { $0.id == id }),
              let target = items.first(where: { $0.id == targetID }) else { return }
        items = Reorder.move(item, onto: target, in: items)
    }

    func loadThumbnails() async {
        for item in items {
            let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 72, height: 92),
                                                       scale: 2, representationTypes: .thumbnail)
            if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                thumbnails[item.id] = representation.nsImage
            }
        }
    }
}
```

- [ ] **Step 2: Implement `ReorderView.swift`**

```swift
import SwiftUI

struct ReorderView: View {
    let model: ReorderModel
    let confirm: () -> Void
    let cancel: () -> Void

    static let itemWidth: CGFloat = 88
    static let height: CGFloat = 176

    /// Panel width for a number of items, capped so long selections scroll.
    static func width(for count: Int) -> CGFloat {
        min(CGFloat(max(count, 3)) * (itemWidth + 8) + 32, 760)
    }

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        thumbnail(item, number: index + 1)
                    }
                }
                .padding(.horizontal, 16)
            }
            HStack {
                Text("Drag to reorder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Combine", action: confirm)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .frame(width: Self.width(for: model.items.count), height: Self.height)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        .animation(.easeOut(duration: 0.15), value: model.items)
        .task { await model.loadThumbnails() }
    }

    private func thumbnail(_ item: ReorderItem, number: Int) -> some View {
        VStack(spacing: 4) {
            Group {
                if let image = model.thumbnails[item.id] {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                }
            }
            .frame(width: 72, height: 92)
            .overlay(alignment: .topLeading) {
                Text("\(number)")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
                    .padding(3)
            }
            Text(item.url.deletingPathExtension().lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: Self.itemWidth)
        .draggable(item.id.uuidString)
        .dropDestination(for: String.self) { dropped, _ in
            guard let first = dropped.first, let id = UUID(uuidString: first) else { return false }
            model.move(id: id, onto: item.id)
            return true
        }
    }
}
```

- [ ] **Step 3: Implement `ReorderPanel.swift`**

```swift
import AppKit
import SwiftUI

/// Floating strip for ordering files before Combine. Key-capable, non-activating.
@MainActor
final class ReorderPanelController {
    private var panel: KeyPanel?
    private var completion: (([URL]?) -> Void)?
    private var model: ReorderModel?

    var isShowing: Bool { panel != nil }

    /// Shows the strip near `point`. `completion` receives the ordered URLs, or nil if cancelled.
    func show(urls: [URL], near point: NSPoint, completion: @escaping ([URL]?) -> Void) {
        close(result: nil)
        let model = ReorderModel(urls: urls)
        self.model = model
        self.completion = completion

        let size = NSSize(width: ReorderView.width(for: urls.count), height: ReorderView.height)
        let panel = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.contentView = NSHostingView(rootView: ReorderView(
            model: model,
            confirm: { [weak self] in self?.close(result: model.items.map(\.url)) },
            cancel: { [weak self] in self?.close(result: nil) }))

        var origin = NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        if let visible = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame ?? NSScreen.main?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    private func close(result: [URL]?) {
        guard let panel else { return }
        panel.orderOut(nil)
        self.panel = nil
        self.model = nil
        let completion = self.completion
        self.completion = nil
        completion?(result)
    }
}

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
```

Return and Esc are handled by the two buttons' `.keyboardShortcut(.defaultAction)` and `.keyboardShortcut(.cancelAction)`.

- [ ] **Step 4: Wire Combine in `AppController.swift`**

Add a property next to `wheel`:

```swift
    @ObservationIgnored private let reorder = ReorderPanelController()
```

In `hotkeyPressed()`, ignore the hotkey while the strip is open by adding as the first line:

```swift
        guard !reorder.isShowing else { return }
```

Replace `run(_:)` with:

```swift
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
        let title = choice.entry.options.count > 1 ? "\(choice.entry.title): \(choice.option.title)" : choice.entry.title
        jobCenter.start(title: title, inputs: choice.inputs, kind: choice.option.action, settings: settings)
    }
```

- [ ] **Step 5: Build, test, and verify by hand**

Run: `swift test && scripts/build-app.sh && open "build/Finder Wheel.app"`

1. Select three PDFs named `1 Cover.pdf`, `2 Intro.pdf`, `10 Appendix.pdf`, hold ⌥Space, release on Combine. The strip appears at the cursor with thumbnails in the order 1, 2, 10.
2. Press Return: `1 Cover-merged.pdf` appears, selected in Finder, with pages in that order.
3. Repeat, drag the third thumbnail onto the first, click Combine: the merged file starts with the appendix.
4. Repeat and press Esc: the strip closes and no file is written.
5. While the strip is open Finder's window still looks active (the app did not steal focus), and ⌥Space does nothing.

If Return or Esc do nothing in item 2 or 4, the panel did not become key: confirm `KeyPanel.canBecomeKey` returns true and that `makeKeyAndOrderFront` is called. If dragging does not start, replace `.draggable`/`.dropDestination` with `.onDrag { NSItemProvider(object: item.id.uuidString as NSString) }` and `.onDrop(of: [.text], isTargeted: nil)` that loads the string and calls `model.move`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add reorder strip and wire Combine"
```

---

### Task 8: Settings storage and window

Settings in this plan: hotkey (three presets), Mistral API key (Keychain), strip-location toggle. The transcription language picker is added in Plan 3 together with transcription; `AppSettings` already stores its value.

**Files:**
- Create: `Sources/FinderWheelCore/Settings/SecretStore.swift`
- Create: `Sources/FinderWheelCore/Settings/AppSettings.swift`
- Create: `Tests/FinderWheelCoreTests/AppSettingsTests.swift`
- Create: `Sources/FinderWheel/Settings/SettingsView.swift`
- Create: `Sources/FinderWheel/Settings/SettingsWindowController.swift`
- Modify: `Sources/FinderWheel/AppController.swift`
- Modify: `Sources/FinderWheel/MenuBar/MenuBarView.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import FinderWheelCore

@MainActor
@Suite(.serialized) struct AppSettingsTests {
    /// One fixed test domain, cleared before each use, so test runs never leave
    /// new files in ~/Library/Preferences. Same pattern as LastUsedStoreTests.
    private func defaults() -> UserDefaults {
        let name = "com.lorenz.finderwheel.tests.settings"
        UserDefaults().removePersistentDomain(forName: name)
        return UserDefaults(suiteName: name)!
    }

    @Test func defaultsMatchTheSpec() {
        let settings = AppSettings(defaults: defaults(), secrets: InMemorySecretStore())
        #expect(settings.hotkey == .optionSpace)
        #expect(settings.stripLocation)
        #expect(settings.mistralKey.isEmpty)
        #expect(settings.snapshot().mistralKey == nil)
        #expect(settings.snapshot().stripLocation)
        // The system locale without overrides such as "@rg=dezzzz".
        #expect(settings.snapshot().transcriptionLocale.identifier == Locale.current.identifier.components(separatedBy: "@")[0])
    }

    @Test func valuesPersist() {
        let store = defaults()
        let secrets = InMemorySecretStore()
        let first = AppSettings(defaults: store, secrets: secrets)
        first.hotkeyID = HotkeyCombo.controlSpace.id
        first.stripLocation = false
        first.mistralKey = "key-123"
        first.transcriptionLocaleID = "de_DE"

        let second = AppSettings(defaults: store, secrets: secrets)
        #expect(second.hotkey == .controlSpace)
        #expect(!second.stripLocation)
        #expect(second.mistralKey == "key-123")
        #expect(second.snapshot().mistralKey == "key-123")
        #expect(second.snapshot().transcriptionLocale.identifier == "de_DE")
    }

    @Test func keyIsStoredOnlyInTheSecretStore() {
        let store = defaults()
        let secrets = InMemorySecretStore()
        let settings = AppSettings(defaults: store, secrets: secrets)
        settings.mistralKey = "  key-123 \n"
        #expect(secrets.get() == "key-123")
        #expect(!store.dictionaryRepresentation().values.contains { ($0 as? String)?.contains("key-123") == true })
        settings.mistralKey = ""
        #expect(secrets.get() == nil)
    }

    @Test func unknownHotkeyFallsBackToDefault() {
        let store = defaults()
        store.set("nonsense", forKey: "hotkeyID")
        #expect(AppSettings(defaults: store, secrets: InMemorySecretStore()).hotkey == .optionSpace)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AppSettingsTests`
Expected: FAIL to compile, "cannot find 'AppSettings' in scope".

- [ ] **Step 3: Implement `SecretStore.swift`**

```swift
import Foundation
import Security

/// Holds one secret string.
public protocol SecretStore: AnyObject {
    func get() -> String?
    /// Stores the value; nil removes it.
    func set(_ value: String?)
}

public final class InMemorySecretStore: SecretStore {
    private var value: String?
    public init(_ value: String? = nil) { self.value = value }
    public func get() -> String? { value }
    public func set(_ value: String?) { self.value = value }
}

/// Generic-password item in the login Keychain.
public final class KeychainSecretStore: SecretStore {
    private let service: String
    private let account: String

    public init(service: String = "com.lorenz.finderwheel", account: String = "mistral-api-key") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    public func get() -> String? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ value: String?) {
        SecItemDelete(baseQuery as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var query = baseQuery
        query[kSecValueData] = Data(value.utf8)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess { NSLog("FinderWheel: could not store key in Keychain, status \(status)") }
    }
}
```

- [ ] **Step 4: Implement `AppSettings.swift`**

```swift
import Foundation
import Observation

/// User settings. UserDefaults for plain values, a `SecretStore` for the API key.
@MainActor
@Observable
public final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let secrets: SecretStore

    public var hotkeyID: String {
        didSet { defaults.set(hotkeyID, forKey: "hotkeyID") }
    }
    public var stripLocation: Bool {
        didSet { defaults.set(stripLocation, forKey: "stripLocation") }
    }
    /// Locale identifier for transcription, for example "de_DE".
    public var transcriptionLocaleID: String {
        didSet { defaults.set(transcriptionLocaleID, forKey: "transcriptionLocaleID") }
    }
    /// Empty when no key is stored. Surrounding whitespace is ignored when storing.
    public var mistralKey: String {
        didSet {
            let trimmed = mistralKey.trimmingCharacters(in: .whitespacesAndNewlines)
            secrets.set(trimmed.isEmpty ? nil : trimmed)
        }
    }

    public init(defaults: UserDefaults = .standard, secrets: SecretStore = KeychainSecretStore()) {
        self.defaults = defaults
        self.secrets = secrets
        hotkeyID = HotkeyCombo.named(defaults.string(forKey: "hotkeyID")).id
        stripLocation = defaults.object(forKey: "stripLocation") as? Bool ?? true
        // Drop locale overrides ("en_US@rg=dezzzz") so the default is a plain language and region.
        transcriptionLocaleID = defaults.string(forKey: "transcriptionLocaleID")
            ?? Locale.current.identifier.components(separatedBy: "@")[0]
        mistralKey = secrets.get() ?? ""
    }

    public var hotkey: HotkeyCombo { HotkeyCombo.named(hotkeyID) }

    public func snapshot() -> SettingsSnapshot {
        let key = mistralKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return SettingsSnapshot(stripLocation: stripLocation, mistralKey: key.isEmpty ? nil : key,
                                transcriptionLocale: Locale(identifier: transcriptionLocaleID))
    }
}
```

Note: property observers do not run for assignments inside `init`, so reading the stored key does not write it back.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter AppSettingsTests`
Expected: PASS, 4 tests.

- [ ] **Step 6: Implement `SettingsView.swift`**

```swift
import SwiftUI
import FinderWheelCore

struct SettingsView: View {
    @Bindable var settings: AppSettings
    /// Edited locally and stored on Save or Return, so the Keychain is not written on every keystroke.
    @State private var keyDraft = ""

    private func saveKey() {
        settings.mistralKey = keyDraft
    }

    var body: some View {
        Form {
            Section {
                Picker("Hotkey", selection: $settings.hotkeyID) {
                    ForEach(HotkeyCombo.all) { combo in
                        Text(combo.label).tag(combo.id)
                    }
                }
                Text("Hold the hotkey in Finder to show the wheel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Mistral OCR") {
                HStack {
                    SecureField("API key", text: $keyDraft)
                        .onSubmit(saveKey)
                    Button("Save", action: saveKey)
                        .disabled(keyDraft == settings.mistralKey)
                }
                .onAppear { keyDraft = settings.mistralKey }
                Text("Used only for the Markdown action on PDFs and images, which sends those files to Mistral. The key is stored in your Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Images") {
                Toggle("Remove location data when converting or compressing", isOn: $settings.stripLocation)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
```

- [ ] **Step 7: Implement `SettingsWindowController.swift`**

```swift
import AppKit
import SwiftUI
import FinderWheelCore

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(settings: AppSettings) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: settings)))
            window.title = "Finder Wheel Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 8: Use the settings in `AppController.swift`**

Add properties:

```swift
    let settings = AppSettings()
    @ObservationIgnored private let settingsWindow = SettingsWindowController()
```

Change the `trigger` property so it starts with the stored hotkey. Because property initialisers cannot read `settings`, replace the `trigger` declaration with:

```swift
    @ObservationIgnored private let trigger: HotkeyTrigger
```

and make these the first lines of `init()`:

```swift
        trigger = HotkeyTrigger(combo: settings.hotkey)
        hotkeyLabel = settings.hotkey.label
```

Replace `settingsSnapshot()` with:

```swift
    private func settingsSnapshot() -> SettingsSnapshot {
        settings.snapshot()
    }
```

Add:

```swift
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
```

Call `observeHotkey()` as the last line of `init()`.

- [ ] **Step 9: Add a Settings button to `MenuBarView.swift`**

Replace the final `Button("Quit Finder Wheel")` line with:

```swift
            HStack {
                Button("Settings…") { controller.openSettings() }
                Spacer()
                Button("Quit Finder Wheel") { NSApplication.shared.terminate(nil) }
            }
```

- [ ] **Step 10: Build, test, and verify by hand**

Run: `swift test && scripts/build-app.sh && open "build/Finder Wheel.app"`

1. Menu bar icon, then "Settings…": the window opens in front.
2. Change the hotkey to ⌃ Space: ⌥Space no longer shows the wheel in Finder, ⌃Space does. The hint in the menu shows the new hotkey. Change it back.
3. Type a test value into the API key field and click Save (the button then turns grey). Quit and relaunch the app, reopen settings: the field is filled. (After a rebuild macOS may ask for the login password at launch to read the Keychain item; this is a consequence of ad-hoc signing.)
4. Turn off "Remove location data", convert a location-tagged photo: the result still has its GPS data. Turn it back on.

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "Add settings storage, Keychain store and settings window"
```

---

### Task 9: Mistral OCR and the Markdown action

Behaviour:
- Markdown on a PDF or image uploads the file to Mistral OCR and writes `<name>.md` next to it: the pages' Markdown joined by a blank line, ending with one newline.
- JPG and PNG images are sent as they are; other image formats are re-encoded to JPEG in memory first.
- No key: the action throws `ActionError.missingMistralKey`.
- Files over 50 MB fail with "Larger than Mistral's 50 MB limit".
- HTTP errors show the server's message: "Mistral: <message> (HTTP <status>)". A response with no pages fails with "Mistral returned no text".
- Images referenced inside the Markdown are not downloaded; their links stay as plain references. This is a known limitation of the first version.

The network is injected as a `transport` closure so tests never touch the real API.

**Files:**
- Create: `Sources/FinderWheelCore/Actions/MistralClient.swift`
- Create: `Sources/FinderWheelCore/Actions/MarkdownOCRAction.swift`
- Create: `Tests/FinderWheelCoreTests/MistralClientTests.swift`
- Create: `Tests/FinderWheelCoreTests/MarkdownOCRActionTests.swift`
- Modify: `Sources/FinderWheelCore/Actions/ImageIOHelper.swift`
- Modify: `Sources/FinderWheelCore/Jobs/ActionRouter.swift`
- Modify: `Sources/FinderWheel/AppController.swift`

- [ ] **Step 1: Write the failing tests**

`MistralClientTests.swift`:

```swift
import Testing
import Foundation
@testable import FinderWheelCore

@Suite struct MistralClientTests {
    private func json(_ request: URLRequest) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any] ?? [:]
    }

    @Test func buildsPDFRequest() throws {
        let request = try MistralClient.makeRequest(apiKey: "key-1", data: Data("pdf".utf8), mimeType: "application/pdf")
        #expect(request.url?.absoluteString == "https://api.mistral.ai/v1/ocr")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key-1")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try json(request)
        #expect(body["model"] as? String == "mistral-ocr-latest")
        #expect(body["include_image_base64"] as? Bool == false)
        let document = body["document"] as? [String: String]
        #expect(document?["type"] == "document_url")
        #expect(document?["document_url"] == "data:application/pdf;base64,\(Data("pdf".utf8).base64EncodedString())")
    }

    @Test func buildsImageRequest() throws {
        let request = try MistralClient.makeRequest(apiKey: "k", data: Data("img".utf8), mimeType: "image/png")
        let document = try json(request)["document"] as? [String: String]
        #expect(document?["type"] == "image_url")
        #expect(document?["image_url"] == "data:image/png;base64,\(Data("img".utf8).base64EncodedString())")
    }

    @Test func rejectsOversizedFiles() {
        let big = Data(count: 50 * 1024 * 1024 + 1)
        #expect(throws: ActionError("Larger than Mistral's 50 MB limit")) {
            _ = try MistralClient.makeRequest(apiKey: "k", data: big, mimeType: "application/pdf")
        }
    }

    @Test func parsesPagesInIndexOrder() throws {
        // Two pound signs: the JSON contains `"#`, which would end a single-pound raw string.
        let body = ##"{"pages":[{"index":1,"markdown":"second"},{"index":0,"markdown":"# first"}]}"##
        #expect(try MistralClient.parse(data: Data(body.utf8), status: 200) == "# first\n\nsecond\n")
    }

    @Test func emptyResultIsAnError() {
        #expect(throws: ActionError("Mistral returned no text")) {
            _ = try MistralClient.parse(data: Data(#"{"pages":[]}"#.utf8), status: 200)
        }
        #expect(throws: ActionError("Mistral returned no text")) {
            _ = try MistralClient.parse(data: Data(#"{"pages":[{"index":0,"markdown":"  "}]}"#.utf8), status: 200)
        }
    }

    @Test func errorsCarryTheServerMessage() {
        #expect(throws: ActionError("Mistral: Unauthorized (HTTP 401)")) {
            _ = try MistralClient.parse(data: Data(#"{"message":"Unauthorized"}"#.utf8), status: 401)
        }
        #expect(throws: ActionError("Mistral: Rate limit exceeded (HTTP 429)")) {
            _ = try MistralClient.parse(data: Data(#"{"detail":"Rate limit exceeded"}"#.utf8), status: 429)
        }
        #expect(throws: ActionError("Mistral: request failed (HTTP 500)")) {
            _ = try MistralClient.parse(data: Data("<html>".utf8), status: 500)
        }
    }
}
```

`MarkdownOCRActionTests.swift`:

```swift
import Testing
import Foundation
import UniformTypeIdentifiers
@testable import FinderWheelCore

/// Records the requests it receives and answers with a fixed response.
private final class TransportSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    let status: Int
    let body: String

    init(status: Int = 200, body: String = ##"{"pages":[{"index":0,"markdown":"# Hello"}]}"##) {
        self.status = status
        self.body = body
    }

    var requests: [URLRequest] { lock.withLock { recorded } }

    var transport: MistralClient.Transport {
        { [self] request in
            lock.withLock { recorded.append(request) }
            return (Data(body.utf8), status)
        }
    }

    func documentField(_ name: String) -> String? {
        guard let data = requests.first?.httpBody,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let document = json["document"] as? [String: String] else { return nil }
        return document[name]
    }
}

@Suite struct MarkdownOCRActionTests {
    private func context(key: String? = "key-1") -> ActionContext {
        ActionContext(settings: SettingsSnapshot(mistralKey: key), progress: { _ in })
    }

    @Test func writesMarkdownNextToAPDF() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("scan.pdf"), pages: 1)
        let spy = TransportSpy()
        let outcome = try await MarkdownOCRAction(transport: spy.transport).run(input: input, context: context())
        #expect(outcome == .produced([tmp.file("scan.md")]))
        #expect(try String(contentsOf: tmp.file("scan.md"), encoding: .utf8) == "# Hello\n")
        #expect(spy.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer key-1")
        #expect(spy.documentField("document_url")?.hasPrefix("data:application/pdf;base64,") == true)
    }

    @Test func sendsPNGAsIs() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeImage(to: tmp.file("shot.png"), type: .png)
        let spy = TransportSpy()
        _ = try await MarkdownOCRAction(transport: spy.transport).run(input: input, context: context())
        let expected = "data:image/png;base64,\(try Data(contentsOf: input).base64EncodedString())"
        #expect(spy.documentField("image_url") == expected)
    }

    @Test func reencodesOtherImageFormatsAsJPEG() async throws {
        let tmp = TempFolder()
        let input = Fixtures.writeImage(to: tmp.file("photo.heic"), type: .heic)
        let spy = TransportSpy()
        _ = try await MarkdownOCRAction(transport: spy.transport).run(input: input, context: context())
        let url = try #require(spy.documentField("image_url"))
        #expect(url.hasPrefix("data:image/jpeg;base64,"))
        let data = try #require(Data(base64Encoded: String(url.dropFirst("data:image/jpeg;base64,".count))))
        #expect(data.prefix(2) == Data([0xFF, 0xD8]))
    }

    @Test func missingKeyThrowsBeforeAnyRequest() async {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("scan.pdf"), pages: 1)
        let spy = TransportSpy()
        await #expect(throws: ActionError.missingMistralKey) {
            _ = try await MarkdownOCRAction(transport: spy.transport).run(input: input, context: context(key: nil))
        }
        #expect(spy.requests.isEmpty)
    }

    @Test func serverErrorWritesNothing() async {
        let tmp = TempFolder()
        let input = Fixtures.writePDF(to: tmp.file("scan.pdf"), pages: 1)
        let spy = TransportSpy(status: 401, body: #"{"message":"Unauthorized"}"#)
        await #expect(throws: ActionError("Mistral: Unauthorized (HTTP 401)")) {
            _ = try await MarkdownOCRAction(transport: spy.transport).run(input: input, context: context())
        }
        #expect(!FileManager.default.fileExists(atPath: tmp.file("scan.md").path))
    }

    @Test func routerKnowsMarkdownForPDFsAndImages() {
        #expect(ActionRouter.action(for: .markdown, fileKind: .pdf) is MarkdownOCRAction)
        #expect(ActionRouter.action(for: .markdown, fileKind: .image) is MarkdownOCRAction)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "MistralClientTests|MarkdownOCRActionTests"`
Expected: FAIL to compile, "cannot find 'MistralClient' in scope".

- [ ] **Step 3: Add JPEG-in-memory encoding to `ImageIOHelper.swift`**

Add inside `enum ImageIOHelper`:

```swift
    /// The first image of `source` as JPEG data, transparency flattened onto white.
    static func jpegData(source: CGImageSource, quality: Double = 0.9) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ActionError("Could not encode image")
        }
        let props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImageDestinationBackgroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        ]
        CGImageDestinationAddImageFromSource(dest, source, 0, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ActionError("Could not encode image") }
        return data as Data
    }
```

- [ ] **Step 4: Implement `MistralClient.swift`**

```swift
import Foundation

/// Builds and interprets Mistral OCR calls. Stateless; the network is a closure.
public enum MistralClient {
    /// Sends a request and returns the body and HTTP status.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)

    public static let endpoint = URL(string: "https://api.mistral.ai/v1/ocr")!
    static let maxBytes = 50 * 1024 * 1024

    public static let urlSessionTransport: Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// `mimeType` is "application/pdf" or an image type such as "image/jpeg".
    static func makeRequest(apiKey: String, data: Data, mimeType: String) throws -> URLRequest {
        guard data.count <= maxBytes else { throw ActionError("Larger than Mistral's 50 MB limit") }
        let dataURL = "data:\(mimeType);base64,\(data.base64EncodedString())"
        let document: [String: String] = mimeType == "application/pdf"
            ? ["type": "document_url", "document_url": dataURL]
            : ["type": "image_url", "image_url": dataURL]
        let body: [String: Any] = ["model": "mistral-ocr-latest", "document": document, "include_image_base64": false]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private struct OCRResponse: Decodable {
        struct Page: Decodable {
            let index: Int
            let markdown: String
        }
        let pages: [Page]
    }

    /// Returns the Markdown of all pages, in page order, ending with one newline.
    static func parse(data: Data, status: Int) throws -> String {
        guard (200..<300).contains(status) else {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = (json?["message"] as? String) ?? (json?["detail"] as? String) ?? "request failed"
            throw ActionError("Mistral: \(message) (HTTP \(status))")
        }
        guard let response = try? JSONDecoder().decode(OCRResponse.self, from: data) else {
            throw ActionError("Mistral returned an unexpected response")
        }
        let text = response.pages.sorted { $0.index < $1.index }
            .map { $0.markdown.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard !text.isEmpty else { throw ActionError("Mistral returned no text") }
        return text + "\n"
    }
}
```

- [ ] **Step 5: Implement `MarkdownOCRAction.swift`**

```swift
import Foundation
import UniformTypeIdentifiers

/// Markdown for PDFs and images, through Mistral OCR. The only action that uploads a file.
public struct MarkdownOCRAction: FileAction {
    private let transport: MistralClient.Transport

    public init(transport: @escaping MistralClient.Transport = MistralClient.urlSessionTransport) {
        self.transport = transport
    }

    public func run(input: URL, context: ActionContext) async throws -> ActionOutcome {
        guard let key = context.settings.mistralKey, !key.isEmpty else { throw ActionError.missingMistralKey }
        let (data, mimeType) = try Self.payload(for: input)
        let request = try MistralClient.makeRequest(apiKey: key, data: data, mimeType: mimeType)
        context.progress(0.1)
        let (body, status): (Data, Int)
        do {
            (body, status) = try await transport(request)
        } catch let error as URLError {
            throw ActionError("Could not reach Mistral: \(error.localizedDescription)")
        }
        let markdown = try MistralClient.parse(data: body, status: status)
        context.progress(0.9)
        let output = OutputNamer.fileURL(for: input, suffix: nil, ext: "md")
        try AtomicOutput.write(to: output) { temp in
            try Data(markdown.utf8).write(to: temp)
        }
        return .produced([output])
    }

    private static func payload(for input: URL) throws -> (Data, String) {
        if Classifier.kind(of: input) == .pdf {
            guard let data = try? Data(contentsOf: input) else { throw ActionError("Could not read PDF") }
            return (data, "application/pdf")
        }
        let (source, type) = try ImageIOHelper.source(for: input)
        if type.conforms(to: .jpeg) || type.conforms(to: .png) {
            guard let data = try? Data(contentsOf: input) else { throw ActionError("Could not read image") }
            return (data, type.conforms(to: .png) ? "image/png" : "image/jpeg")
        }
        return (try ImageIOHelper.jpegData(source: source), "image/jpeg")
    }
}
```

- [ ] **Step 6: Register in `ActionRouter`**

```swift
        case (.markdown, .pdf), (.markdown, .image):
            return MarkdownOCRAction()
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `swift test --filter "MistralClientTests|MarkdownOCRActionTests"`
Expected: PASS, 12 tests.

- [ ] **Step 8: Missing-key and first-upload handling in `AppController.swift`**

Spec: a missing key opens settings; before the first upload a one-time notice confirms that this action sends files to Mistral.

Add this method:

```swift
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
```

In `run(_:)`, directly after the `if choice.option.action == .combine { ... }` block, add:

```swift
        let usesMistral = choice.option.action == .markdown
            && [Classification.pdf, .image, .pdfImage].contains(choice.classification)
        if usesMistral && !confirmMistralUpload() { return }
```

- [ ] **Step 9: Build and run all tests**

Run: `swift test && scripts/build-app.sh`
Expected: PASS; app builds.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "Add Mistral OCR Markdown action with upload notice"
```

---

### Task 10: Manual verification for Plan 2

**Files:**
- Modify: `docs/manual-checks.md`

- [ ] **Step 1: Append to `docs/manual-checks.md`**

```markdown
## Plan 2: PDF, image and OCR actions

Prepare: a scanned or image-heavy PDF of several pages, a text-only PDF, a password-protected PDF, a PDF with a sideways page, a photo of a person or object, a PNG screenshot with text, and a valid Mistral API key.

1. Image Compress, medium on a JPG photo: `photo-compressed.jpg` appears and is smaller. On a PNG screenshot: `shot-compressed.jpg`.
2. Image Compress, outer ring "2000 px" on a large photo: the result's longest side is 2000 px.
3. Cut out on the photo of a person: `photo-cutout.png` has a transparent background (check in Preview). On a blank screenshot: the menu lists "No subject found in this image".
4. PDF Convert (PNG): a folder `name-pages` appears and is selected; it holds one sharp PNG per page. The sideways page is rendered sideways, not clipped.
5. PDF Convert, outer ring JPG: same with JPG files, in `name-pages-2`.
6. PDF Split: a folder with one-page PDFs named `name-p01.pdf` and so on.
7. PDF Compress, strong on the scanned PDF: clearly smaller, still readable. On the text-only PDF: the menu lists "Already as small as it gets" and no file appears.
8. Any PDF action on the password-protected PDF: the menu lists "PDF is password-protected" and the menu bar icon shows the warning dot until the menu is opened.
9. One PDF selected: the Combine wedge is dimmed. One image selected: Combine produces a one-page PDF.
10. Combine three phone photos: strip appears sorted by name; Return writes `first-merged.pdf`. In Preview the pages are A4-sized (portrait or landscape to match each photo) and sharp when zoomed in.
11. One PDF plus two images selected: the wheel shows only Markdown, Compress and Combine; Convert and the lower-left wedge are dimmed. Combine merges all three into one PDF. Compress writes a `-compressed` file for each.
12. Remove the API key in settings. Markdown on a PDF: the settings window opens and nothing is uploaded.
13. Enter the key. Markdown on the scanned PDF: the one-time "Send files to Mistral?" notice appears; Cancel uploads nothing. Run again, Continue: `name.md` appears with the recognised text. Run once more: no notice.
14. Markdown on the PNG screenshot and on a HEIC photo of a document: an `.md` file with the text for each.
15. Enter a wrong key, run Markdown: the menu lists a Mistral error with the HTTP status; no file appears.
16. Turn Wi-Fi off, run Markdown: the menu lists "Could not reach Mistral: ...".
17. Start PDF Convert on a PDF with 100 or more pages and press Cancel in the menu: the job shows "Cancelled" and no `-pages` folder is left behind.
```

- [ ] **Step 2: Run the checks**

Run: `scripts/build-app.sh && open "build/Finder Wheel.app"`
Work through items 1 to 17 and re-run the Plan 1 list. Fix failures at their cause, re-run `swift test`, rebuild and re-check. If a check contradicts the spec, stop and ask the user.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "Add Plan 2 manual checks"
```

**Plan 2 is complete when:** `swift test` passes and both manual check lists pass. Continue with Plan 3.
