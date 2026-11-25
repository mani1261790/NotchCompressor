import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Runs only in the helper executable (or unit tests), never on the UI thread.
public enum ImageCompressionWorker {
    public static func compress(input: URL, output: URL, quality: Double) throws {
        let size = try InputFile.validate(input, extensions: ["jpg", "jpeg", "png"])
        guard size <= 128 * 1024 * 1024 else { throw CompressionError.localized(.init("error.imageTooLarge")) }
        let original = try load(input)
        let type = CGImageSourceGetType(original)! as String
        let expected = UTType(filenameExtension: input.pathExtension.lowercased())?.identifier
        guard type == expected, [UTType.jpeg.identifier, UTType.png.identifier].contains(type) else {
            throw CompressionError.localized(.init("error.mediaMismatch"))
        }
        let sourceImage = try decode(original)
        if type == UTType.png.identifier {
            let data = try PNGOptimizer.optimize(Data(contentsOf: input))
            try data.write(to: output, options: .withoutOverwriting)
        } else {
            // Auxiliary images, MPF and gain maps require a separate preservation
            // contract. Reject before generating any candidate.
            let data = try Data(contentsOf: input)
            try rejectCompoundJPEG(data)
            guard sourceImage.bitsPerComponent == 8,
                sourceImage.colorSpace?.model == .rgb
                    || sourceImage.colorSpace?.model == .monochrome
            else { throw CompressionError.localized(.init("error.imageStructure")) }
            guard !FileManager.default.fileExists(atPath: output.path),
                let destination = CGImageDestinationCreateWithURL(output as CFURL, type as CFString, 1, nil)
            else { throw CompressionError.localized(.init("error.imageWrite")) }
            CGImageDestinationAddImageFromSource(
                destination, original, 0,
                [kCGImageDestinationLossyCompressionQuality: min(1, max(0.1, quality))] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                throw CompressionError.localized(.init("error.imageWrite"))
            }
            let preserved = try JPEGMetadata.preserving(from: data, in: Data(contentsOf: output))
            try preserved.write(to: output)
            try JPEGMetadata.validate(data, preserved)
        }
        let candidate = try load(output)
        let resultImage = try decode(candidate)
        guard CGImageSourceGetType(candidate) == CGImageSourceGetType(original),
            sourceImage.width == resultImage.width, sourceImage.height == resultImage.height,
            sourceImage.bitsPerComponent == resultImage.bitsPerComponent,
            sourceImage.colorSpace?.model == resultImage.colorSpace?.model,
            sourceImage.colorSpace?.copyICCData() == resultImage.colorSpace?.copyICCData()
        else { throw CompressionError.localized(.init("error.imagePreservation")) }
        try validateMetadata(original, candidate)
    }

    private static func load(_ url: URL) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) == 1,
            CGImageSourceGetStatus(source) == .statusComplete
        else { throw CompressionError.localized(.init("error.imageStructure")) }
        return source
    }

    private static func decode(_ source: CGImageSource) throws -> CGImage {
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        guard let width = props?[kCGImagePropertyPixelWidth as String] as? Int,
            let height = props?[kCGImagePropertyPixelHeight as String] as? Int,
            width > 0, height > 0, width <= 32_768, height <= 32_768, width * height <= 32_000_000
        else { throw CompressionError.localized(.init("error.imageTooLarge")) }
        guard
            let image = CGImageSourceCreateImageAtIndex(
                source, 0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
            let provider = image.dataProvider, let data = provider.data, CFDataGetLength(data) > 0,
            CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete
        else { throw CompressionError.localized(.init("error.imageStructure")) }
        return image
    }

    private static func validateMetadata(_ original: CGImageSource, _ output: CGImageSource) throws {
        let before = CGImageSourceCopyPropertiesAtIndex(original, 0, nil) as? [String: Any] ?? [:]
        let after = CGImageSourceCopyPropertiesAtIndex(output, 0, nil) as? [String: Any] ?? [:]
        let keys = [
            kCGImagePropertyOrientation, kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary,
            kCGImagePropertyIPTCDictionary, kCGImagePropertyTIFFDictionary, kCGImagePropertyProfileName,
        ]
        for key in keys {
            let name = key as String
            guard
                NSDictionary(dictionary: [name: before[name] ?? NSNull()]).isEqual(to: [name: after[name] ?? NSNull()])
            else {
                throw CompressionError.localized(.init("error.imagePreservation"))
            }
        }
    }

    private static func rejectCompoundJPEG(_ data: Data) throws {
        // MPF or gain-map XMP can refer to additional images outside the primary
        // codestream; a normal JPEG re-encode must not silently discard them.
        for marker in [Data("MPF\0".utf8), Data("hdrgm:".utf8), Data("HDRGainMap".utf8), Data("GContainer:".utf8)] {
            if data.range(of: marker) != nil { throw CompressionError.localized(.init("error.imageStructure")) }
        }
    }
}

public struct ImageWorkerResponse: Codable {
    public let error: LocalizedMessage?
    public init(error: LocalizedMessage?) { self.error = error }
}
