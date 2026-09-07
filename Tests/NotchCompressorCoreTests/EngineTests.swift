import XCTest
import CryptoKit
@testable import NotchCompressorCore

final class EngineTests: XCTestCase {
    private func tools() throws -> Toolchain {
        guard ProcessInfo.processInfo.environment["NOTCH_MEDIA_TESTS"] == "1" else {
            throw XCTSkip("NOTCH_MEDIA_TESTS=1 enables real FFmpeg/VideoToolbox integration tests.")
        }
        return try Toolchain.discover()
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notch-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func makeVideo(_ url: URL, tools: Toolchain, audio: Bool = true) async throws {
        var args = ["-v", "error", "-nostdin", "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=60:duration=2"]
        if audio { args += ["-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=2"] }
        args += ["-c:v", "h264_videotoolbox", "-b:v", "3000000", "-pix_fmt", "yuv420p"]
        if audio { args += ["-c:a", "aac", "-b:a", "192k"] }
        args += ["-n", url.path]
        _ = try await ProcessRunner().run(executable: tools.ffmpeg, arguments: args, timeout: 30)
    }

    private func packetHashes(_ url: URL, stream: String, tools: Toolchain) async throws -> [String] {
        let data = try await ProcessRunner().run(executable: tools.ffprobe,
            arguments: ["-v", "error", "-select_streams", stream, "-show_packets", "-show_data_hash", "sha256", "-show_entries", "packet=data_hash", "-of", "json", url.path])
        struct Hashes: Decodable { struct Packet: Decodable { let data_hash: String }; let packets: [Packet] }
        return try JSONDecoder().decode(Hashes.self, from: data).packets.map(\.data_hash)
    }

    func testRealThreeModesAndCopyPacketHashes() async throws {
        let tools = try tools(), folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("収録 ; $dollar.mov")
        try await makeVideo(source, tools: tools)
        let before = SHA256.hash(data: try Data(contentsOf: source))
        let audioHashes = try await packetHashes(source, stream: "a:0", tools: tools)
        let videoHashes = try await packetHashes(source, stream: "v:0", tools: tools)
        XCTAssertFalse(audioHashes.isEmpty)
        XCTAssertFalse(videoHashes.isEmpty)
        for mode in CompressionMode.allCases {
            let result = try await CompressionEngine().compress(input: source, mode: mode, settings: .init())
            let output = try await CompressionEngine().probe(result.output, tools: tools)
            XCTAssertEqual(output.video.codecName, mode == .audio ? "h264" : "hevc")
            XCTAssertNotNil(output.audio)
            XCTAssertLessThan(abs(output.duration - 2), 0.1)
            if mode == .video { let hashes = try await packetHashes(result.output, stream: "a:0", tools: tools); XCTAssertEqual(hashes, audioHashes) }
            if mode == .audio { let hashes = try await packetHashes(result.output, stream: "v:0", tools: tools); XCTAssertEqual(hashes, videoHashes) }
        }
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: source)), before)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasPrefix(".notchcompressor-") })
    }

    func testSilentAndBrokenMediaKeepOriginal() async throws {
        let tools = try tools(), folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("silent.mov")
        try await makeVideo(source, tools: tools, audio: false)
        do { _ = try await CompressionEngine().compress(input: source, mode: .audio, settings: .init()); XCTFail("Silent audio-only must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("音声のない")) }
        let result = try await CompressionEngine().compress(input: source, mode: .both, settings: .init())
        XCTAssertNotNil(result.note)
        let broken = folder.appendingPathComponent("broken.mov")
        let contents = Data("not a video".utf8)
        try contents.write(to: broken)
        do { _ = try await CompressionEngine().compress(input: broken, mode: .both, settings: .init()); XCTFail("Broken must fail") }
        catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        XCTAssertEqual(try Data(contentsOf: broken), contents)
    }

    func testPublishDoesNotReplaceExistingFilesOrSymlinks() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("screen.mov"), staged = folder.appendingPathComponent("staged.mov")
        try Data("source".utf8).write(to: source)
        try Data("output".utf8).write(to: staged)
        let occupied = folder.appendingPathComponent("screen-compressed-video.mov")
        try FileManager.default.createSymbolicLink(at: occupied, withDestinationURL: source)
        let first = try CompressionEngine.publish(staged, beside: source, mode: .video)
        let second = try CompressionEngine.publish(staged, beside: source, mode: .video)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: source), "source")
        XCTAssertEqual(try String(contentsOf: first), "output")
    }

    func testRealFFmpegCancellationStopsPromptly() async throws {
        let tools = try tools()
        let task = Task {
            try await ProcessRunner().run(executable: tools.ffmpeg,
                arguments: ["-nostdin", "-v", "error", "-re", "-f", "lavfi", "-i", "color=size=64x64:duration=30", "-f", "null", "-"])
        }
        try await Task.sleep(for: .milliseconds(400))
        let start = Date()
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
    }

    func testCancelledEngineRemovesStaging() async throws {
        let tools = try tools(), folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.mov")
        try await makeVideo(source, tools: tools)
        let encoding = expectation(description: "Encoding phase")
        let task = Task {
            try await CompressionEngine().compress(input: source, mode: .both, settings: .init()) { phase, _, _ in
                if phase == .encoding { encoding.fulfill() }
            }
        }
        await fulfillment(of: [encoding], timeout: 10)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["source.mov"])
    }

    func testRejectsOutputWithMissingAudio() throws {
        let original = try MediaInfo.decode(fixture(), fileSize: 1000)
        let silent = try MediaInfo.decode(fixture(audio: false), fileSize: 500)
        XCTAssertThrowsError(try CompressionEngine.validateOutput(original: original, output: silent, mode: .both))
    }
}
