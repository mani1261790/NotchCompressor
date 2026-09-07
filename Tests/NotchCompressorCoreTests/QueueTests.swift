import XCTest
@testable import NotchCompressorCore

private actor ExecutionLog {
    var names: [String] = []
    var qualities: [CompressionQuality] = []
    var running = 0
    var maximum = 0
    func start(_ url: URL, quality: CompressionQuality) {
        names.append(url.lastPathComponent); qualities.append(quality); running += 1; maximum = max(maximum, running)
    }
    func finish() { running -= 1 }
}

final class QueueTests: XCTestCase {
    @MainActor
    func testSerialQueueContinuesAfterFailureAndSnapshotsSettings() async throws {
        let log = ExecutionLog()
        let queue = JobQueue { url, _, settings, update in
            await log.start(url, quality: settings.quality)
            update(.encoding, 0.5, nil)
            try await Task.sleep(for: .milliseconds(40))
            await log.finish()
            if url.lastPathComponent == "bad.mov" { throw CompressionError.message("fixture failure") }
            return CompressionResult(output: url, originalBytes: 100, outputBytes: 50, note: nil)
        }
        let inputs = ["bad.mov", "good.mov", "last.mov"].map { URL(fileURLWithPath: "/tmp/" + $0) }
        XCTAssertEqual(queue.enqueue(inputs, mode: .both), 3)
        queue.settings.quality = .compact
        await queue.waitUntilIdle()
        let names = await log.names, maximum = await log.maximum, qualities = await log.qualities
        XCTAssertEqual(names, inputs.map(\.lastPathComponent))
        XCTAssertEqual(maximum, 1)
        XCTAssertEqual(qualities, [.balanced, .balanced, .balanced])
        XCTAssertEqual(queue.jobs.map(\.phase), [.failed, .completed, .completed])
    }

    @MainActor
    func testCancellationAndPendingDuplicate() async throws {
        let queue = JobQueue { url, _, _, _ in
            try await Task.sleep(for: .seconds(30))
            return CompressionResult(output: url, originalBytes: 100, outputBytes: 50, note: nil)
        }
        let input = URL(fileURLWithPath: "/tmp/first.mov")
        XCTAssertEqual(queue.enqueue([input, input, URL(fileURLWithPath: "/tmp/second.mov")], mode: .audio), 2)
        await queue.stopForTermination()
        XCTAssertFalse(queue.isBusy)
        XCTAssertEqual(queue.jobs.map(\.phase), [.cancelled, .cancelled])
        XCTAssertEqual(queue.enqueue([input], mode: .audio), 0)
    }

    @MainActor
    func testRestoresInterruptedWithoutRunningAndPreservesFinished() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("queue.json")
        let pending = CompressionJob(input: URL(fileURLWithPath: "/tmp/video.mov"), mode: .video, settings: .init())
        var done = pending
        done.phase = .completed
        try JSONEncoder().encode(QueueSnapshot(settings: .init(quality: .compact), jobs: [pending, done])).write(to: url)
        let queue = JobQueue(storage: url)
        XCTAssertEqual(queue.jobs.map(\.phase), [.interrupted, .completed])
        XCTAssertFalse(queue.isBusy)
        XCTAssertEqual(queue.settings.quality, .compact)
        let saved = try JSONDecoder().decode(QueueSnapshot.self, from: Data(contentsOf: url))
        XCTAssertEqual(saved.jobs.first?.phase, .interrupted)
    }

    @MainActor
    func testCorruptHistoryIsNotOverwritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let contents = Data("broken history".utf8)
        try contents.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let queue = JobQueue(storage: url)
        queue.settings.quality = .compact
        XCTAssertNotNil(queue.persistenceError)
        XCTAssertEqual(try Data(contentsOf: url), contents)
    }
}
