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
