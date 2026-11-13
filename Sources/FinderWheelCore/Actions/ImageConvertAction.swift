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
