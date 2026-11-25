import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import NotchCompressorCore

final class MediaInputTests: XCTestCase {
    func testVideoAndCoveredAudioAreDistinguishedByTracks() throws {
        XCTAssertEqual(try MediaInputInspector.classifyProbe(fixture(), extension: "mov"), .video)
        XCTAssertThrowsError(try MediaInputInspector.classifyProbe(fixture(), extension: "m4a"))
        let audio = Data(
            """
            {"streams":[{"index":0,"codec_type":"audio","codec_name":"aac","channels":2},
            {"index":1,"codec_type":"video","codec_name":"mjpeg","disposition":{"attached_pic":1}}],
            "format":{"format_name":"mov,mp4,m4a,3gp,3g2,mj2","duration":"2.0"}}
            """.utf8)
        XCTAssertEqual(try MediaInputInspector.classifyProbe(audio, extension: "m4a"), .audio)
        XCTAssertThrowsError(try MediaInputInspector.classifyProbe(audio, extension: "mov"))
        XCTAssertThrowsError(try MediaInputInspector.classifyProbe(Data("{}".utf8), extension: "mov"))
    }

    func testMixedBatchRetainsValidInputsAndRejectsRenamedImages() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let png = folder.appendingPathComponent("image.png")
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let disguised = folder.appendingPathComponent("not-jpeg.jpg")
        try FileManager.default.copyItem(at: png, to: disguised)
        let missing = folder.appendingPathComponent("missing.png")
        let batch = try await InputBatch.inspect([png, disguised, missing, png], mode: .both, enabledKinds: [.image])
        XCTAssertEqual(batch.accepted.map(\.url), [png.standardizedFileURL.resolvingSymlinksInPath()])
        XCTAssertEqual(batch.accepted.first?.kind, .image)
        XCTAssertEqual(batch.rejected.count, 2)
        XCTAssertEqual(batch.rejected.first?.reason.key, "error.mediaMismatch")
        let wrongZone = try await InputBatch.inspect([png], mode: .audio, enabledKinds: [.image])
        XCTAssertEqual(wrongZone.rejected.first?.reason.key, "error.mediaMode")
        let notYetEnabled = try await InputBatch.inspect([png], mode: .both)
        XCTAssertEqual(notYetEnabled.rejected.first?.reason.key, "error.mediaUnavailable")
    }

    @MainActor
    func testLegacyHistoryDefaultsToVideoAndInspectedSettingsArePinned() throws {
        let url = URL(fileURLWithPath: "/tmp/input.m4a")
        let old = CompressionJob(input: url, mode: .both, settings: .init())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        object.removeValue(forKey: "mediaKind")
        let restored = try JSONDecoder().decode(
            CompressionJob.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored.effectiveMediaKind, .video)
        let queue = JobQueue(storage: nil)
        queue.togglePause()
        let snapshot = CompressionSettings(quality: .gentle)
        queue.enqueue([url], mode: .both, mediaKind: .audio, settings: snapshot)
        queue.settings.quality = .compact
        XCTAssertEqual(queue.jobs[0].settings.quality, .gentle)
        XCTAssertEqual(queue.jobs[0].effectiveMediaKind, .audio)
        let encoded = try JSONEncoder().encode(queue.jobs[0])
        XCTAssertEqual(try JSONDecoder().decode(CompressionJob.self, from: encoded).effectiveMediaKind, .audio)
    }
}
