import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import NotchCompressorCore

final class AudioCompressionTests: XCTestCase {
    private func tools() throws -> Toolchain {
        guard ProcessInfo.processInfo.environment["NOTCH_MEDIA_TESTS"] == "1" else {
            throw XCTSkip("Enable real media tests")
        }
        return try Toolchain.discover()
    }
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func makeAudio(
        _ url: URL, tools: Toolchain, channels: Int, rate: Int, cover: URL? = nil, codec: String = "aac"
    ) async throws {
        var args = [
            "-nostdin", "-v", "error", "-f", "lavfi", "-i",
            "aevalsrc=0.3*sin(440*2*PI*t)\(channels == 2 ? "|0.2*sin(880*2*PI*t)" : ""):s=\(rate):d=2",
        ]
        if let cover {
            args += ["-i", cover.path, "-map", "0:a", "-map", "1:v", "-c:v", "copy", "-disposition:v", "attached_pic"]
        }
        args += [
            "-c:a", codec, "-b:a", "256k", "-metadata", "title=音声テスト", "-metadata", "artist=NotchCompressor",
            "-metadata", "comment=Preserve this tag", "-n", url.path,
        ]
        do { _ = try await ProcessRunner().run(executable: tools.ffmpeg, arguments: args, timeout: 30) } catch {
            XCTFail("Fixture: \((error as? CompressionError)?.technicalDetails ?? String(describing: error))");
            throw error
        }
    }
    func testAudioOnlyAndCoveredAudioRoundTrip() async throws {
        let tools = try tools(), directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cover = directory.appendingPathComponent("cover.png")
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let dest = try XCTUnwrap(
            CGImageDestinationCreateWithURL(cover as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        for (index, pair) in [(1, 44100), (2, 48000)].enumerated() {
            let source = directory.appendingPathComponent("source\(index).m4a")
            try await makeAudio(source, tools: tools, channels: pair.0, rate: pair.1, cover: index == 1 ? cover : nil)
            let media = try await AudioCompressionEngine().probe(source, tools: tools)
            let input = try await MediaInputInspector.inspect(source)
            XCTAssertEqual(input.kind, .audio)
            let result: CompressionResult
            do { result = try await CompressionEngine().compress(input: source, mode: .both, settings: .init()) } catch
            {
                XCTFail("Compression: \((error as? CompressionError)?.technicalDetails ?? String(describing: error))");
                throw error
            }
            let output = try await AudioCompressionEngine().probe(source, tools: tools)
            XCTAssertEqual(result.effectiveOutcome, .replaced)
            XCTAssertLessThan(result.outputBytes, result.originalBytes)
            try media.validate(output)
            XCTAssertEqual(output.sampleRate, pair.1)
            XCTAssertEqual(output.audio.channels, pair.0)
            XCTAssertEqual(output.tags["title"], "音声テスト")
            XCTAssertEqual(output.covers.count, index)
        }
    }
    func testLosslessM4AAndWrongZoneLeaveOriginalUntouched() async throws {
        let tools = try tools(), directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("lossless.m4a")
        try await makeAudio(source, tools: tools, channels: 2, rate: 48000, codec: "alac")
        let original = try Data(contentsOf: source)
        for mode in [CompressionMode.both, .video] {
            do {
                _ = try await CompressionEngine().compress(input: source, mode: mode, settings: .init())
                XCTFail("Must reject lossless input or incorrect mode")
            } catch { XCTAssertEqual(try Data(contentsOf: source), original) }
        }
    }
}
