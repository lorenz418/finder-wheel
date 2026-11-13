import Foundation
import CoreImage
import Vision

public struct CutOutAction: FileAction {
    public init() {}

    public func run(input: URL, context: ActionContext) async throws -> ActionOutcome {
        let handler = VNImageRequestHandler(url: input)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        try Task.checkCancellation()
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
