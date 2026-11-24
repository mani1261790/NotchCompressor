import XCTest
@testable import NotchCompressorCore

final class FeedbackTests: XCTestCase {
    func testCapacityIncreaseAndMixedResults() {
        var notice = CompletionNotice()
        let url = URL(fileURLWithPath: "/tmp/unused.mov")
        notice.include(.init(output: url, originalBytes: 1000, outputBytes: 1500, note: nil))
        XCTAssertEqual(notice.savedBytes, -500)
        XCTAssertTrue(notice.text.contains("増加"))
        notice.include(.init(output: url, originalBytes: 2000, outputBytes: 1000, note: nil))
        XCTAssertEqual(notice.count, 2)
        XCTAssertEqual(notice.savedBytes, 500)
        XCTAssertTrue(notice.text.contains("削減"))
    }

    @MainActor
    func testRetainedResultNotifiesAndRestoresWithoutQueueCard() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = folder.appendingPathComponent("queue.json")
        let result = CompressionResult(
            output: folder.appendingPathComponent("source.mov"), originalBytes: 1000,
            outputBytes: 1000, note: nil, outcome: .originalKept, candidateBytes: 1500)
        let queue = JobQueue(storage: storage, operation: { _, _, _, _ in result })
        queue.enqueue([result.output], mode: .both)
        await queue.waitUntilIdle()
        XCTAssertTrue(queue.displayedJobs.isEmpty)
        XCTAssertEqual(queue.jobs.first?.phase, .completed)
        XCTAssertEqual(queue.completionNotice?.savedBytes, 0)
        XCTAssertTrue(queue.completionNotice?.text.contains("元動画を保持") == true)
        let restored = JobQueue(storage: storage)
        XCTAssertEqual(restored.jobs.first?.result?.effectiveOutcome, .originalKept)
        XCTAssertEqual(restored.jobs.first?.result?.candidateBytes, 1500)
        XCTAssertNil(restored.completionNotice)
        var notice = CompletionNotice()
        notice.include(result)
        notice.include(.init(output: result.output, originalBytes: 2000, outputBytes: 500, note: nil))
        XCTAssertEqual(notice.savedBytes, 1500)
        XCTAssertEqual(notice.originalKeptCount, 1)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
        old.removeValue(forKey: "outcome")
        old.removeValue(forKey: "candidateBytes")
        let legacy = try JSONDecoder().decode(CompressionResult.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(legacy.effectiveOutcome, .replaced)
        XCTAssertNil(legacy.candidateBytes)
    }

    func testMixedQueueDoesNotHidePausedOrFailedJobs() {
        var running = CompressionJob(input: URL(fileURLWithPath: "/tmp/a.mov"), mode: .both, settings: .init())
        running.phase = .encoding
        var paused = CompressionJob(input: URL(fileURLWithPath: "/tmp/b.mov"), mode: .both, settings: .init())
        paused.phase = .paused
        var failed = CompressionJob(input: URL(fileURLWithPath: "/tmp/c.mov"), mode: .both, settings: .init())
        failed.phase = .failed
        let status = QueueStatus(
            jobs: [running, paused, failed], running: [running.id, paused.id], paused: [paused.id])
        XCTAssertEqual(status.count, 3)
        XCTAssertEqual(status.title, "実行中 1件 · 一時停止 1件 · 要確認 1件")
        XCTAssertEqual(QueueStatus(jobs: [paused], running: [paused.id], paused: [paused.id]).symbol, "pause.circle")
        XCTAssertEqual(QueueStatus(jobs: [failed], running: [], paused: []).symbol, "exclamationmark.circle")
    }

    @MainActor
    func testSuccessFeedbackAggregatesWithoutRestoringOrShowingCards() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = folder.appendingPathComponent("queue.json")
        let queue = JobQueue(
            storage: storage, feedbackDuration: .milliseconds(200),
            operation: { url, _, _, _ in
                if url.lastPathComponent == "bad.mov" { throw CompressionError.message("failed") }
                return .init(output: url, originalBytes: 1000, outputBytes: 600, note: nil)
            })
        queue.enqueue(["a.mov", "b.mov", "bad.mov"].map { folder.appendingPathComponent($0) }, mode: .both)
        await queue.waitUntilIdle()
        XCTAssertEqual(queue.completionNotice?.count, 2)
        XCTAssertEqual(queue.completionNotice?.savedBytes, 800)
        XCTAssertEqual(queue.displayedJobs.map(\.phase), [.failed])
        XCTAssertNil(JobQueue(storage: storage).completionNotice)
        for _ in 0..<100 where queue.completionNotice != nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(queue.completionNotice)
        XCTAssertEqual(queue.displayedJobs.map(\.phase), [.failed])
    }
}
