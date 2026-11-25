import XCTest
import ImageIO
import UniformTypeIdentifiers
import zlib
@testable import NotchCompressorCore

final class ImageCompressionTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func image(_ url: URL, type: UTType, orientation: Int = 1, profile: CFString = CGColorSpace.sRGB) throws {
        let space = try XCTUnwrap(CGColorSpace(name: profile))
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 320, height: 192, bitsPerComponent: 8, bytesPerRow: 1280,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for y in 0..<192 {
            context.setFillColor(CGColor(red: CGFloat(y) / 192, green: 0.5, blue: 0.3, alpha: type == .png ? 0.5 : 1))
            context.fill(CGRect(x: 0, y: y, width: 320, height: 1))
        }
        let output = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        let metadata: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:11:25 12:00:00"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 35.0, kCGImagePropertyGPSLatitudeRef: "N"],
            kCGImageDestinationLossyCompressionQuality: 1.0,
        ]
        CGImageDestinationAddImage(output, try XCTUnwrap(context.makeImage()), metadata as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(output))
    }

    func testJPEGPreservesOrientationColorAndCaptureMetadata() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        for orientation in 1...8 {
            let source = directory.appendingPathComponent("source\(orientation).jpg")
            let output = directory.appendingPathComponent("out\(orientation).jpg")
            try image(
                source, type: .jpeg, orientation: orientation,
                profile: orientation == 8 ? CGColorSpace.displayP3 : CGColorSpace.sRGB)
            let before = try Data(contentsOf: source)
            try ImageCompressionWorker.compress(input: source, output: output, quality: 0.85)
            XCTAssertEqual(try Data(contentsOf: source), before)
            let result = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(result, 0, nil) as? [String: Any])
            XCTAssertEqual(properties[kCGImagePropertyOrientation as String] as? Int, orientation)
            XCTAssertNotNil(properties[kCGImagePropertyGPSDictionary as String])
        }
    }

    func testPNGPreservesPixelsAndMetadataAndRejectsCRCError() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.png"),
            output = directory.appendingPathComponent("out.png")
        try image(source, type: .png)
        let before = try Data(contentsOf: source)
        try ImageCompressionWorker.compress(input: source, output: output, quality: 0.1)
        let original = try XCTUnwrap(CGImageSourceCreateWithURL(source as CFURL, nil))
        let result = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let originalImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(original, 0, nil))
        let outputImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(result, 0, nil))
        XCTAssertEqual(originalImage.dataProvider?.data, outputImage.dataProvider?.data)
        XCTAssertEqual(try Data(contentsOf: source), before)
        var corrupt = before
        corrupt[29] ^= 1
        XCTAssertThrowsError(try PNGOptimizer.optimize(corrupt))
    }

    func testSixteenBitPNGIsNotReducedToEightBits() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("sixteen.png"),
            output = directory.appendingPathComponent("out.png")
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.linearSRGB))
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 16, height: 16, bitsPerComponent: 16, bytesPerRow: 128,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 0.3))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        try ImageCompressionWorker.compress(input: source, output: output, quality: 0.5)
        let result = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        XCTAssertEqual(CGImageSourceCreateImageAtIndex(result, 0, nil)?.bitsPerComponent, 16)
    }

    func testAnimatedPNGAndCompoundJPEGAreRejected() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("image.png")
        try image(source, type: .png)
        var data = try Data(contentsOf: source)
        let payload = Data("acTL".utf8) + Data([0, 0, 0, 1, 0, 0, 0, 0])
        let crc = payload.withUnsafeBytes {
            UInt32(crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(payload.count)))
        }
        let trailer = Data([
            UInt8((crc >> 24) & 255), UInt8((crc >> 16) & 255), UInt8((crc >> 8) & 255), UInt8(crc & 255),
        ])
        data.insert(contentsOf: Data([0, 0, 0, 8]) + payload + trailer, at: 33)
        XCTAssertThrowsError(try PNGOptimizer.optimize(data)) { error in
            XCTAssertEqual((error as? CompressionError)?.localizedMessage.key, "error.imageAnimation")
        }
        let jpeg = directory.appendingPathComponent("image.jpg")
        try image(jpeg, type: .jpeg)
        let before = try Data(contentsOf: jpeg)
        var compound = before
        compound.insert(contentsOf: [0xff, 0xe2, 0, 6, 77, 80, 70, 0], at: 2)
        XCTAssertThrowsError(try JPEGMetadata.preserving(from: compound, in: before))
        XCTAssertThrowsError(try JPEGMetadata.preserving(from: before + Data([1]), in: before))
    }

    func testPauseBeforeImageHelperLaunchAndCancellationKeepOriginal() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("image.jpg")
        try image(source, type: .jpeg)
        let before = try Data(contentsOf: source)
        let control = CompressionControl()
        XCTAssertTrue(control.pause())
        let task = Task {
            try await CompressionControl.$current.withValue(control) {
                try await CompressionEngine().compress(input: source, mode: .both, settings: .init())
            }
        }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(try Data(contentsOf: source), before)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled job must not replace original") } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(try Data(contentsOf: source), before)
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: directory.path).contains {
                $0.hasPrefix(".notchcompressor-")
            })
    }

    func testImageHelperPausesAndResumesWithinTheSameTransaction() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("image.png")
        try image(source, type: .png)
        let before = try Data(contentsOf: source)
        let control = CompressionControl()
        let encoding = expectation(description: "Image worker reached encoding")
        let task = Task {
            try await CompressionControl.$current.withValue(control) {
                try await CompressionEngine().compress(input: source, mode: .both, settings: .init()) { phase, _, _ in
                    if phase == .encoding { XCTAssertTrue(control.pause()); encoding.fulfill() }
                }
            }
        }
        await fulfillment(of: [encoding], timeout: 5)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(control.isPaused)
        XCTAssertEqual(try Data(contentsOf: source), before)
        XCTAssertTrue(control.resume())
        let result = try await task.value
        XCTAssertLessThanOrEqual(result.outputBytes, result.originalBytes)
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: directory.path).contains {
                $0.hasPrefix(".notchcompressor-")
            })
    }

    func testImageEngineUsesHelperAndKeepsOriginalOnFailure() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.png")
        try image(source, type: .png)
        let before = try Data(contentsOf: source)
        let result = try await CompressionEngine().compress(input: source, mode: .both, settings: .init())
        XCTAssertLessThanOrEqual(result.outputBytes, result.originalBytes)
        let kept = try Data(contentsOf: source)
        do {
            _ = try await CompressionEngine().compress(input: source, mode: .audio, settings: .init())
            XCTFail("Wrong zone must be rejected")
        } catch { XCTAssertEqual(try Data(contentsOf: source), kept) }
        XCTAssertEqual(result.originalBytes, Int64(before.count))
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: directory.path).contains {
                $0.hasPrefix(".notchcompressor-")
            })
    }
}
