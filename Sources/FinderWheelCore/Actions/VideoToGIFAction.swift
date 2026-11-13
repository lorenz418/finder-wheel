import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

public struct VideoToGIFAction: FileAction {
    static let width: CGFloat = 480
    static let framesPerSecond = 12

    public init() {}

    public func run(input: URL, context: ActionContext) async throws -> ActionOutcome {
        let asset = try await MediaExport.videoAsset(input)
        let duration = try await asset.load(.duration).seconds
        let frameCount = max(1, Int((duration * Double(Self.framesPerSecond)).rounded()))

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // Aspect-fit into a box that is 480 wide and tall enough never to be the limit.
        generator.maximumSize = CGSize(width: Self.width, height: Self.width * 8)
        let tolerance = CMTime(value: 1, timescale: CMTimeScale(Self.framesPerSecond * 2))
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let output = OutputNamer.fileURL(for: input, suffix: nil, ext: "gif")
        try await AtomicOutput.write(to: output) { temp in
            guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
                throw ActionError("Could not write GIF")
            }
            CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0, kCGImagePropertyGIFHasGlobalColorMap: false]] as CFDictionary)
            // GIF delays are whole centiseconds, so spread the rounding error across frames to keep the total exact.
            let fps = Double(Self.framesPerSecond)
            func centiseconds(_ i: Int) -> Int { Int((Double(i) * 100 / fps).rounded()) }
            for frame in 0..<frameCount {
                try Task.checkCancellation()
                let delay = Double(centiseconds(frame + 1) - centiseconds(frame)) / 100
                let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
                let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(Self.framesPerSecond))
                let image = try await generator.image(at: time).image
                CGImageDestinationAddImage(dest, image, frameProps)
                context.progress(Double(frame + 1) / Double(frameCount))
            }
            guard CGImageDestinationFinalize(dest) else { throw ActionError("Could not write GIF") }
        }
        return .produced([output])
    }
}
