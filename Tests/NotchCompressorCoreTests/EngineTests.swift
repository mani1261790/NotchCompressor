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
        let data = try await ProcessRunner().run(
            executable: tools.ffprobe,
            arguments: [
                "-v", "error", "-select_streams", stream, "-show_packets", "-show_data_hash", "sha256", "-show_entries",
                "packet=data_hash", "-of", "json", url.path,
            ])
        struct Hashes: Decodable { struct Packet: Decodable { let data_hash: String }; let packets: [Packet] }
        return try JSONDecoder().decode(Hashes.self, from: data).packets.map(\.data_hash)
    }

    private func videoTimes(_ url: URL, tools: Toolchain) async throws -> [Double] {
        let data = try await ProcessRunner().run(
            executable: tools.ffprobe,
            arguments: [
                "-v", "error", "-select_streams", "v:0", "-show_frames", "-show_entries",
                "frame=best_effort_timestamp_time", "-of", "json", url.path,
            ])
        struct Report: Decodable {
            struct Frame: Decodable { let best_effort_timestamp_time: String }
            let frames: [Frame]
        }
        return try JSONDecoder().decode(Report.self, from: data).frames.compactMap {
            Double($0.best_effort_timestamp_time)
        }
    }

    func testFrameRateAndVariableTimingWithCopiedAudio() async throws {
        let tools = try tools(), folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        for rate in [24, 30, 60, 0] {
            let source = folder.appendingPathComponent("timing\(rate).mov")
            var args = [
                "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=\(rate == 0 ? 60 : rate):duration=2",
                "-f", "lavfi", "-i", "sine=sample_rate=48000:duration=2",
            ]
            if rate == 0 { args += ["-vf", "select=if(lt(n\\,60)\\,1\\,not(mod(n\\,2)))"] }
            args += [
                "-fps_mode:v", "passthrough", "-c:v", "h264_videotoolbox", "-b:v", "6000000", "-c:a", "aac", "-n",
                source.path,
            ]
            _ = try await ProcessRunner().run(executable: tools.ffmpeg, arguments: args)
            let original = try Data(contentsOf: source)
            let before = try await videoTimes(source, tools: tools)
            XCTAssertEqual(before.count, rate == 0 ? 90 : rate * 2)
            let audio = try await packetHashes(source, stream: "a:0", tools: tools)
            for choice in VideoFrameRate.allCases {
                try original.write(to: source, options: .atomic)
                let result = try await CompressionEngine().compress(
                    input: source, mode: .video, settings: .init(videoFrameRate: choice))
                XCTAssertEqual(result.effectiveOutcome, .replaced, "Fixture must actually exercise encoding")
                let after = try await videoTimes(source, tools: tools)
                if choice == .source {
                    XCTAssertEqual(after.count, before.count)
                    for (expected, actual) in zip(before, after) { XCTAssertEqual(actual, expected, accuracy: 0.002) }
                } else {
                    XCTAssertLessThanOrEqual(after.count, 61)
                    for (a, b) in zip(after, after.dropFirst()) { XCTAssertGreaterThanOrEqual(b - a, 1.0 / 30 - 0.002) }
                }
                let afterAudio = try await packetHashes(source, stream: "a:0", tools: tools)
                XCTAssertEqual(afterAudio, audio)
                let probe = try await CompressionEngine().probe(source, tools: tools)
                XCTAssertEqual(probe.duration, 2, accuracy: 0.1)
            }
        }
    }

    func testRealThreeModesAndCopyPacketHashes() async throws {
        let tools = try tools(), folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("収録 ; $dollar.mov")
        try await makeVideo(source, tools: tools)
        let originalData = try Data(contentsOf: source)
        let before = SHA256.hash(data: originalData)
        let audioHashes = try await packetHashes(source, stream: "a:0", tools: tools)
        let videoHashes = try await packetHashes(source, stream: "v:0", tools: tools)
        XCTAssertFalse(audioHashes.isEmpty)
        XCTAssertFalse(videoHashes.isEmpty)
        for mode in CompressionMode.allCases {
            try originalData.write(to: source, options: .atomic)
            let result = try await CompressionEngine().compress(input: source, mode: mode, settings: .init())
            XCTAssertEqual(result.output, source)
            XCTAssertNotEqual(SHA256.hash(data: try Data(contentsOf: source)), before)
            let output = try await CompressionEngine().probe(result.output, tools: tools)
            XCTAssertEqual(output.video.codecName, mode == .audio ? "h264" : "hevc")
            XCTAssertNotNil(output.audio)
            XCTAssertLessThan(abs(output.duration - 2), 0.1)
            if mode == .video {
                let hashes = try await packetHashes(result.output, stream: "a:0", tools: tools);
                XCTAssertEqual(hashes, audioHashes)
            }
            if mode == .audio {
                let hashes = try await packetHashes(result.output, stream: "v:0", tools: tools);
                XCTAssertEqual(hashes, videoHashes)
            }
        }
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: folder.path).contains {
                $0.hasPrefix(".notchcompressor-")
            })
    }

    func testSpeedPriorityCompletesFullValidationAndPreservesCopiedAudio() async throws {
        let tools = try tools(), folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("speed.mov")
        try await makeVideo(source, tools: tools)
        let audioHashes = try await packetHashes(source, stream: "a:0", tools: tools)
        let result = try await CompressionEngine().compress(
            input: source, mode: .video, settings: .init(videoEncodingSpeed: .fast))
        XCTAssertEqual(result.output, source)
        let output = try await CompressionEngine().probe(result.output, tools: tools)
        XCTAssertEqual(output.video.codecName, "hevc")
        let afterHashes = try await packetHashes(source, stream: "a:0", tools: tools)
        XCTAssertEqual(audioHashes, afterHashes)
    }

    func testRealCustomCompressionKeepsContainerAndUsesSelectedAudioRate() async throws {
        let tools = try tools(), folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("custom.mov")
        try await makeVideo(source, tools: tools)
        let result = try await CompressionEngine().compress(
            input: source, mode: .both,
            settings: .init(quality: .custom, videoPercent: 50, audioKbps: 80))
        let output = try await CompressionEngine().probe(result.output, tools: tools)
        XCTAssertEqual(result.output, source)
        XCTAssertEqual(output.video.codecName, "hevc")
        XCTAssertEqual(output.audio?.codecName, "aac")
        XCTAssertLessThan(try XCTUnwrap(output.audio?.bitRate), 128_000)
        XCTAssertLessThan(abs(output.duration - 2), 0.1)
    }

    func testSilentAndBrokenMediaKeepOriginal() async throws {
        let tools = try tools(), folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("silent.mov")
        try await makeVideo(source, tools: tools, audio: false)
        do {
            _ = try await CompressionEngine().compress(input: source, mode: .audio, settings: .init());
            XCTFail("Silent audio-only must fail")
        } catch { XCTAssertEqual(error.localizedDescription, L10n.text("error.noAudio")) }
        let result = try await CompressionEngine().compress(input: source, mode: .both, settings: .init())
        XCTAssertNotNil(result.noteMessage)
        let broken = folder.appendingPathComponent("broken.mov")
        let contents = Data("not a video".utf8)
        try contents.write(to: broken)
        do {
            _ = try await CompressionEngine().compress(input: broken, mode: .both, settings: .init());
            XCTFail("Broken must fail")
        } catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        XCTAssertEqual(try Data(contentsOf: broken), contents)
    }

    func testVerifiedOutputRetainsOriginalUnlessStrictlySmaller() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.mov")
        let staged = folder.appendingPathComponent("staged.mov")
        for size in [8, 12, 4] {
            try Data(repeating: 1, count: 8).write(to: source)
            let before = try Fingerprint(source)
            try Data(repeating: 2, count: size).write(to: staged)
            let result = try CompressionEngine.finalizeVerifiedOutput(
                staged, original: source, expected: before, note: nil)
            XCTAssertEqual(result.candidateBytes, Int64(size))
            XCTAssertEqual(result.outputBytes, Int64(min(size, 8)))
            XCTAssertEqual(result.effectiveOutcome, size < 8 ? .replaced : .originalKept)
            XCTAssertEqual(try Data(contentsOf: source), Data(repeating: size < 8 ? 2 : 1, count: min(size, 8)))
            if size >= 8 { XCTAssertEqual(try Fingerprint(source), before) }
        }
        let before = try Fingerprint(source)
        try Data(repeating: 3, count: 20).write(to: staged)
        try Data(repeating: 4, count: 5).write(to: source)
        XCTAssertThrowsError(
            try CompressionEngine.finalizeVerifiedOutput(staged, original: source, expected: before, note: nil))
        XCTAssertEqual(try Data(contentsOf: source), Data(repeating: 4, count: 5))
    }

    func testRealLargerOutputKeepsOriginalAndRemovesStaging() async throws {
        let tools = try tools(), folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("small.mp4")
        _ = try await ProcessRunner().run(
            executable: tools.ffmpeg,
            arguments: [
                "-v", "error", "-f", "lavfi", "-i", "color=size=64x64:rate=1:duration=1",
                "-c:v", "h264_videotoolbox", "-b:v", "32000", "-n", source.path,
            ])
        let original = try Data(contentsOf: source)
        let result = try await CompressionEngine().compress(input: source, mode: .video, settings: .init())
        XCTAssertEqual(result.effectiveOutcome, .originalKept)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(result.candidateBytes), result.originalBytes)
        XCTAssertEqual(result.outputBytes, result.originalBytes)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["small.mp4"])
    }

    func testReplacementPreservesNameAndPermissions() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent(String(repeating: "🎬", count: 60) + ".mov")
        let staged = folder.appendingPathComponent("staged.mov")
        try Data("original".utf8).write(to: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: source.path)
        let expected = try Fingerprint(source)
        try Data("verified output".utf8).write(to: staged)
        let result = try CompressionEngine.replaceOriginal(staged, original: source, expected: expected)
        XCTAssertEqual(result, source)
        XCTAssertEqual(try Data(contentsOf: source), Data("verified output".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: source.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o640)
    }

    func testChangedSourceAndFailedReplacementLeaveOriginalIntact() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.mov")
        let staged = folder.appendingPathComponent("staged.mov")
        try Data("original".utf8).write(to: source)
        let expected = try Fingerprint(source)
        try Data("externally edited original".utf8).write(to: source)
        try Data("output".utf8).write(to: staged)
        XCTAssertThrowsError(try CompressionEngine.replaceOriginal(staged, original: source, expected: expected))
        XCTAssertEqual(try Data(contentsOf: source), Data("externally edited original".utf8))
        try FileManager.default.removeItem(at: staged)
        XCTAssertThrowsError(
            try CompressionEngine.replaceOriginal(staged, original: source, expected: Fingerprint(source)))
        XCTAssertEqual(try Data(contentsOf: source), Data("externally edited original".utf8))
    }

    func testMP4AndM4VKeepContainerAndReplaceInPlace() async throws {
        let tools = try tools(), folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        for ext in ["mp4", "m4v"] {
            let source = folder.appendingPathComponent("source." + ext)
            try await makeVideo(source, tools: tools)
            let result = try await CompressionEngine().compress(input: source, mode: .both, settings: .init())
            XCTAssertEqual(result.output, source)
            let header = try Data(contentsOf: source).prefix(12)
            XCTAssertEqual(String(data: header[4..<8], encoding: .ascii), "ftyp")
            XCTAssertNotEqual(String(data: header[8..<12], encoding: .ascii), "qt  ")
            XCTAssertEqual(
                try FileManager.default.contentsOfDirectory(atPath: folder.path).filter {
                    $0.hasPrefix(".notchcompressor-")
                }, [])
        }
    }

    func testRealFFmpegCancellationStopsPromptly() async throws {
        let tools = try tools()
        let task = Task {
            try await ProcessRunner().run(
                executable: tools.ffmpeg,
                arguments: [
                    "-nostdin", "-v", "error", "-re", "-f", "lavfi", "-i", "color=size=64x64:duration=30", "-f", "null",
                    "-",
                ])
        }
        try await Task.sleep(for: .milliseconds(400))
        let start = Date()
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
    }

    func testCancelledEngineRemovesStaging() async throws {
        let tools = try tools(), folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.mov")
        try await makeVideo(source, tools: tools)
        let before = try Data(contentsOf: source)
        let encoding = expectation(description: "Encoding phase")
        let task = Task {
            try await CompressionEngine().compress(input: source, mode: .both, settings: .init()) { phase, _, _ in
                if phase == .encoding { encoding.fulfill() }
            }
        }
        await fulfillment(of: [encoding], timeout: 10)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(try Data(contentsOf: source), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["source.mov"])
    }

    func testRejectsOutputWithMissingAudio() throws {
        let original = try MediaInfo.decode(fixture(), fileSize: 1000)
        let silent = try MediaInfo.decode(fixture(audio: false), fileSize: 500)
        XCTAssertThrowsError(try CompressionEngine.validateOutput(original: original, output: silent, mode: .both))
    }
    @MainActor
    func testRealParallelQueueBatchAndSubsequentSubmission() async throws {
        let tools = try tools()
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inputs = ["batch-a.mov", "batch-b.mov", "later.mov"].map { folder.appendingPathComponent($0) }
        for input in inputs { try await makeVideo(input, tools: tools) }
        let queue = JobQueue()
        queue.execution = .parallel
        queue.settings.toolsDirectory = tools.ffmpeg.deletingLastPathComponent().path
        XCTAssertEqual(queue.enqueue(Array(inputs.prefix(2)), mode: .both), 2)
        XCTAssertEqual(queue.enqueue([inputs[2]], mode: .audio), 1)
        XCTAssertEqual(queue.runningCount, 2)
        await queue.waitUntilIdle()
        XCTAssertEqual(
            queue.jobs.map(\.phase), [.completed, .completed, .completed], "\(queue.jobs.compactMap(\.message))")
        XCTAssertEqual(queue.jobs.compactMap { $0.result?.output }, inputs)
        for input in inputs {
            let media = try await CompressionEngine().probe(input, tools: tools)
            XCTAssertGreaterThan(media.duration, 0)
        }
    }

}
