import AppKit
import XCTest
@testable import NotchCompressorCore

final class SleepTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func inputs(_ folder: URL) throws -> [URL] {
        try ["a.mov", "b.mov", "c.mov"].map {
            let url = folder.appendingPathComponent($0)
            try Data([1, 2, 3]).write(to: url)
            return url
        }
    }

    private static let operation: JobQueue.Operation = { url, _, _, update in
        update(.encoding, 0.2, nil)
        _ = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["0.4"])
        try await CompressionControl.current?.checkpoint()
        return .init(output: url, originalBytes: 3, outputBytes: 3, note: nil, outcome: .originalKept)
    }

    @MainActor
    func testWorkspaceSleepPreservesUserPauseAndGatesDispatch() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let urls = try inputs(folder)
        let queue = JobQueue(operation: Self.operation)
        queue.execution = .parallel
        let center = NotificationCenter()
        let monitor = QueueSleepMonitor(queue: queue, center: center)
        var balance = 0
        let activity = QueueActivity(
            queue: queue,
            begin: {
                balance += 1; return NSObject()
            }, finish: { _ in balance -= 1 })
        queue.enqueue(Array(urls.prefix(2)), mode: .both)
        let manual = queue.jobs[0].id, automatic = queue.jobs[1].id
        queue.pause(manual)
        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        XCTAssertFalse(queue.systemSleeping)
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        XCTAssertEqual(queue.pausedIDs, [manual, automatic])
        XCTAssertEqual(balance, 0)
        queue.enqueue([urls[2]], mode: .both)
        XCTAssertEqual(queue.waitingJobs.count, 1)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertEqual(queue.pausedIDs, [manual])
        XCTAssertEqual(balance, 1)
        for _ in 0..<100 where queue.jobs.filter({ $0.phase == .completed }).count < 2 {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(queue.jobs.filter { $0.phase == .completed }.count, 2)
        XCTAssertEqual(queue.pausedIDs, [manual])
        queue.resume(manual)
        await queue.waitUntilIdle()
        XCTAssertEqual(queue.jobs.filter { $0.phase == .completed }.count, 3)
        XCTAssertEqual(balance, 0)
        withExtendedLifetime((monitor, activity)) {}
    }

    @MainActor
    func testUserCanKeepSystemPausedJobPausedAndMissingDiskFails() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let urls = try inputs(folder)
        let queue = JobQueue(operation: Self.operation)
        queue.execution = .parallel
        queue.enqueue(Array(urls.prefix(2)), mode: .both)
        let kept = queue.jobs[0].id, missing = queue.jobs[1].id
        queue.prepareForSystemSleep()
        queue.pause(kept)  // Add user intent to an already system-paused job.
        try FileManager.default.removeItem(at: urls[1])
        queue.resumeAfterSystemSleep()
        for _ in 0..<100 where queue.runningIDs.contains(missing) {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(queue.jobs.first { $0.id == missing }?.phase, .failed)
        XCTAssertTrue(queue.jobs.first { $0.id == missing }?.displayMessage == L10n.text("error.wakeStorage"))
        XCTAssertTrue(queue.pausedIDs.contains(kept))
        queue.cancel(kept)
        await queue.waitUntilIdle()
        XCTAssertEqual(queue.jobs.first { $0.id == kept }?.phase, .cancelled)
    }

    func testPauseReasonsBlockCommitUntilBothReleased() {
        let control = CompressionControl()
        XCTAssertTrue(control.pause(.systemSleep))
        XCTAssertTrue(control.pause(.user))
        XCTAssertTrue(control.resume(.user))
        XCTAssertNil(control.commit { 1 })
        XCTAssertTrue(control.isPaused)
        XCTAssertTrue(control.resume(.systemSleep))
        XCTAssertEqual(control.commit { 1 }, 1)
        XCTAssertFalse(control.pause(.systemSleep))
    }

    func testSleepGenerationDistinguishesUserPauseAndRepeatedNotifications() {
        let control = CompressionControl()
        XCTAssertEqual(control.systemSleepGeneration, 0)
        XCTAssertTrue(control.pause(.user))
        XCTAssertEqual(control.systemSleepGeneration, 0)
        XCTAssertTrue(control.pause(.systemSleep))
        XCTAssertEqual(control.systemSleepGeneration, 1)
        XCTAssertTrue(control.pause(.systemSleep))
        XCTAssertEqual(control.systemSleepGeneration, 1)
        XCTAssertTrue(control.resume(.systemSleep))
        XCTAssertTrue(control.isPaused)
        XCTAssertEqual(control.systemSleepGeneration, 1)
        XCTAssertTrue(control.pause(.systemSleep))
        XCTAssertEqual(control.systemSleepGeneration, 2)
        XCTAssertTrue(control.resume(.systemSleep))
        XCTAssertTrue(control.resume(.user))
        XCTAssertEqual(control.commit { 1 }, 1)
        XCTAssertFalse(control.pause(.systemSleep))
        XCTAssertEqual(control.systemSleepGeneration, 2)
    }

    func testFailedStageRetriesOnceAfterSleep() async throws {
        let control = CompressionControl()
        var attempts = [Bool]()
        try await CompressionEngine.recoverAfterSleep(control: control) { retrying in
            attempts.append(retrying)
            if !retrying {
                XCTAssertTrue(control.pause(.systemSleep))
                XCTAssertTrue(control.resume(.systemSleep))
                throw CompressionError.localized(.init("error.process", "183"))
            }
        }
        XCTAssertEqual(attempts, [false, true])
        XCTAssertFalse(control.hasCommitted)
    }

    func testRecoveryDoesNotLoopOrRetryUnrelatedFailures() async throws {
        for key in ["error.process", "error.changedRetry", "error.replace"] {
            let control = CompressionControl()
            var attempts = 0
            do {
                try await CompressionEngine.recoverAfterSleep(control: control) { _ in
                    attempts += 1
                    XCTAssertTrue(control.pause(.systemSleep))
                    XCTAssertTrue(control.resume(.systemSleep))
                    throw CompressionError.localized(.init(key))
                }
                XCTFail("Expected failure")
            } catch let error as CompressionError {
                XCTAssertEqual(error.localizedMessage.key, key)
            }
            XCTAssertEqual(attempts, key == "error.process" ? 2 : 1)
        }
    }

    func testUserPauseDoesNotTriggerRecovery() async throws {
        let control = CompressionControl()
        var attempts = 0
        do {
            try await CompressionEngine.recoverAfterSleep(control: control) { _ in
                attempts += 1
                XCTAssertTrue(control.pause(.user))
                XCTAssertTrue(control.resume(.user))
                throw CompressionError.localized(.init("error.process", "183"))
            }
            XCTFail("Expected failure")
        } catch let error as CompressionError {
            XCTAssertEqual(error.localizedMessage.key, "error.process")
        }
        XCTAssertEqual(attempts, 1)
    }

    func testRecoveryWaitsForManualResume() async throws {
        let control = CompressionControl()
        var resumeTask: Task<Void, Never>?
        defer { resumeTask?.cancel() }
        var attempts = 0
        try await CompressionEngine.recoverAfterSleep(control: control) { retrying in
            attempts += 1
            if !retrying {
                XCTAssertTrue(control.pause(.systemSleep))
                XCTAssertTrue(control.pause(.user))
                XCTAssertTrue(control.resume(.systemSleep))
                resumeTask = Task {
                    try? await Task.sleep(for: .milliseconds(100))
                    XCTAssertTrue(control.resume(.user))
                }
                throw CompressionError.localized(.init("error.validation"))
            }
            XCTAssertFalse(control.isPaused, "Recovery must wait for the user's resume")
        }
        XCTAssertEqual(attempts, 2)
        await resumeTask?.value
    }

    func testCancellationAfterSleepDoesNotRetry() async throws {
        let control = CompressionControl()
        var attempts = 0
        do {
            try await CompressionEngine.recoverAfterSleep(control: control) { _ in
                attempts += 1
                XCTAssertTrue(control.pause(.systemSleep))
                XCTAssertTrue(control.resume(.systemSleep))
                throw CancellationError()
            }
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
        XCTAssertEqual(attempts, 1)
    }
}
