import Foundation
import XCTest
@testable import NotchCompressorCore

final class ActivityTests: XCTestCase {
    @MainActor
    func testActivityTracksParallelWorkersPausesAndCancellation() async {
        var starts = 0
        var ends = 0
        let queue = JobQueue(operation: { _, _, _, _ in
            while true {
                try await CompressionControl.current?.checkpoint()
                try await Task.sleep(for: .milliseconds(20))
            }
        })
        queue.execution = .parallel
        let activity = QueueActivity(
            queue: queue,
            begin: {
                starts += 1; return NSObject()
            }, finish: { _ in ends += 1 })
        XCTAssertFalse(activity.isActive)
        queue.enqueue(["a.mov", "b.mov"].map { URL(fileURLWithPath: "/tmp/" + $0) }, mode: .both)
        let ids = queue.jobs.map(\.id)
        XCTAssertTrue(activity.isActive)
        XCTAssertEqual(starts, 1, "Parallel tasks share one process activity")
        queue.pause(ids[0])
        XCTAssertTrue(activity.isActive)
        queue.pause(ids[1])
        XCTAssertFalse(activity.isActive, "All paused workers release idle sleep prevention")
        XCTAssertEqual(ends, 1)
        queue.resume(ids[0])
        XCTAssertTrue(activity.isActive)
        XCTAssertEqual(starts, 2)
        await queue.stopForTermination()
        XCTAssertFalse(activity.isActive)
        XCTAssertEqual(starts, ends)
        XCTAssertTrue(QueueActivity.options.contains(.idleSystemSleepDisabled))
        XCTAssertFalse(QueueActivity.options.contains(.idleDisplaySleepDisabled))
    }

    @MainActor
    func testCompletionAndFailureReleaseActivity() async {
        var balance = 0
        let queue = JobQueue(operation: { url, _, _, _ in
            if url.lastPathComponent == "bad.mov" { throw CompressionError.message("fixture") }
            return .init(output: url, originalBytes: 1000, outputBytes: 500, note: nil)
        })
        let activity = QueueActivity(
            queue: queue,
            begin: {
                balance += 1; return NSObject()
            }, finish: { _ in balance -= 1 })
        queue.enqueue(["ok.mov", "bad.mov"].map { URL(fileURLWithPath: "/tmp/" + $0) }, mode: .both)
        await queue.waitUntilIdle()
        XCTAssertFalse(activity.isActive)
        XCTAssertEqual(balance, 0)
    }
}
