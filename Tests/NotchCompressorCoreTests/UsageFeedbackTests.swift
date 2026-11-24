import Combine
import Foundation
import XCTest
@testable import NotchCompressorCore

final class UsageFeedbackTests: XCTestCase {
    func testCapacityAdviceIncludesDeficitAndPracticalActions() {
        let issue = DiskSpaceIssue(availableBytes: 1_000_000_000, requiredBytes: 3_000_000_000)
        XCTAssertEqual(issue.additionalBytes, 2_000_000_000)
        let text = issue.localizedDescription
        for expected in ["空き", "目安", "ゴミ箱", "外付け", "再試行", "同じディスク"] { XCTAssertTrue(text.contains(expected)) }
        XCTAssertTrue(FailureNotice(diskSpaceIssue: issue).body.contains("あと約"))
        XCTAssertNil(DiskSpaceIssue.classify(CompressionError.message("permission denied")))
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        XCTAssertNotNil(
            DiskSpaceIssue.classify(NSError(domain: "Wrapper", code: 1, userInfo: [NSUnderlyingErrorKey: underlying])))
    }

    func testCompletionReportsBeforeAndAfterEvenWhenItGrows() {
        var notice = CompletionNotice()
        notice.include(
            .init(
                output: URL(fileURLWithPath: "/tmp/private.mov"), originalBytes: 1_000_000_000,
                outputBytes: 2_000_000_000, note: nil))
        XCTAssertTrue(notice.text.contains("1 GB → 2 GB"))
        XCTAssertTrue(notice.text.contains("増加"))
        XCTAssertFalse(notice.text.contains("private"))
    }

    func testRuntimeDiskFullIsClassifiedWithoutFillingDisk() async throws {
        do {
            _ = try await ProcessRunner().run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf 'write failed: No space left on device' >&2; exit 1"])
            XCTFail("Expected disk capacity error")
        } catch {
            XCTAssertTrue(error is DiskSpaceIssue)
            XCTAssertNil((error as? DiskSpaceIssue)?.requiredBytes)
        }
    }

    @MainActor
    func testOnlyNewSuccessAndFailureEmitEventsAndCapacityErrorSurvivesRestore() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = folder.appendingPathComponent("queue.json")
        let queue = JobQueue(
            storage: storage,
            operation: { url, _, _, _ in
                if url.lastPathComponent == "full.mov" { throw DiskSpaceIssue(availableBytes: 100, requiredBytes: 300) }
                if url.lastPathComponent == "cancel.mov" { throw CancellationError() }
                return .init(output: url, originalBytes: 1000, outputBytes: 500, note: nil)
            })
        var successes = 0
        var failures: [FailureNotice] = []
        let successObserver = queue.completionEvents.sink { _ in successes += 1 }
        let failureObserver = queue.failureEvents.sink { failures.append($0) }
        queue.enqueue(["ok.mov", "full.mov", "cancel.mov"].map { folder.appendingPathComponent($0) }, mode: .both)
        await queue.waitUntilIdle()
        XCTAssertEqual(successes, 1)
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.diskSpaceIssue?.additionalBytes, 200)
        let restored = JobQueue(storage: storage)
        XCTAssertEqual(restored.jobs.first(where: { $0.phase == .failed })?.diskSpaceIssue?.additionalBytes, 200)
        XCTAssertNil(restored.completionNotice)
        var restoredEvents = 0
        let restoredObserver = restored.failureEvents.sink { _ in restoredEvents += 1 }
        await Task.yield()
        XCTAssertEqual(restoredEvents, 0)
        withExtendedLifetime([successObserver, failureObserver, restoredObserver]) {}
    }
}
