import XCTest
@testable import NotchCompressorCore

private actor WorkGate {
    var started: [String] = []
    private var continuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var open = false
    func run(_ url: URL) async throws -> CompressionResult {
        let name = url.lastPathComponent
        started.append(name)
        if !open {
            await withCheckedContinuation { continuations[name] = $0 }
        }
        try Task.checkCancellation()
        return CompressionResult(output: url, originalBytes: 100, outputBytes: 50, note: nil)
    }
    func release(_ name: String) { continuations.removeValue(forKey: name)?.resume() }
    func finishAll() {
        open = true
        let pending = continuations.values
        continuations.removeAll()
        for continuation in pending { continuation.resume() }
    }
}

final class SchedulingTests: XCTestCase {
    private func input(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/queue-scheduling-" + name + ".mov") }
    @MainActor private func waitFor(_ condition: () async -> Bool) async throws {
        for _ in 0..<1000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for scheduler transition")
    }

    @MainActor
    func testAutomaticBackfillsAudioAndAcceptsRepeatedBatches() async throws {
        let gate = WorkGate()
        let queue = JobQueue(environment: { .init(conservesResources: false) }) { url, _, _, _ in try await gate.run(url) }
        XCTAssertEqual(queue.enqueue([input("v1"), input("v2")], mode: .both), 2)
        XCTAssertEqual(queue.enqueue([input("a1"), input("a2")], mode: .audio), 2)
        try await waitFor { await gate.started.count == 2 }
        let initial = await gate.started
        XCTAssertEqual(Set(initial), Set([input("v1").lastPathComponent, input("a1").lastPathComponent]))
        XCTAssertEqual(queue.runningCount, 2)
        await gate.release(input("a1").lastPathComponent)
        try await waitFor { await gate.started.count == 3 }
        let backfill = await gate.started
        XCTAssertEqual(backfill.last, input("a2").lastPathComponent)
        XCTAssertEqual(queue.waitingJobs.map(\.input), [input("v2")])
        await gate.finishAll(); await queue.waitUntilIdle()
        XCTAssertTrue(queue.jobs.allSatisfy { $0.phase == .completed })
    }

    @MainActor
    func testDragReorderAndPausePreserveWaitingOrder() async throws {
        let gate = WorkGate()
        let queue = JobQueue(operation: { url, _, _, _ in try await gate.run(url) })
        queue.execution = .serial
        queue.togglePause()
        queue.enqueue([input("first"), input("second"), input("third"), input("fourth")], mode: .both)
        let third = queue.jobs[2].id, second = queue.jobs[1].id, first = queue.jobs[0].id
        XCTAssertTrue(queue.moveWaiting(third, to: first))
        XCTAssertTrue(queue.moveWaiting(second, to: third))
        XCTAssertEqual(queue.waitingJobs.map(\.input), [input("second"), input("third"), input("first"), input("fourth")])
        XCTAssertEqual(queue.runningCount, 0)
        await gate.finishAll()
        queue.togglePause()
        await queue.waitUntilIdle()
        let started = await gate.started
        XCTAssertEqual(started, ["second", "third", "first", "fourth"].map { input($0).lastPathComponent })
    }

    @MainActor
    func testResourceChangesDrainExistingWorkersBeforeReducingConcurrency() async throws {
        let gate = WorkGate()
        var constrained = false
        let queue = JobQueue(environment: { .init(conservesResources: constrained) }) { url, _, _, _ in try await gate.run(url) }
        queue.enqueue([input("a"), input("b"), input("c"), input("d")], mode: .audio)
        try await waitFor { await gate.started.count == 2 }
        constrained = true
        queue.refreshEnvironment()
        XCTAssertEqual(queue.runningCount, 2, "Changing power state must not abort existing encodes")
        await gate.release(input("a").lastPathComponent)
        try await waitFor { queue.runningCount == 1 }
        XCTAssertEqual(queue.waitingJobs.count, 2)
        await gate.release(input("b").lastPathComponent)
        try await waitFor { await gate.started.count == 3 }
        XCTAssertEqual(queue.runningCount, 1)
        constrained = false
        queue.refreshEnvironment()
        try await waitFor { await gate.started.count == 4 }
        XCTAssertEqual(queue.runningCount, 2)
        await gate.finishAll(); await queue.waitUntilIdle()
    }

    @MainActor
    func testSameFileAliasesNeverRunTogetherEvenInParallelMode() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("original.mov")
        let hard = folder.appendingPathComponent("hard.mov")
        let symbolic = folder.appendingPathComponent("symbolic.mov")
        try Data([1]).write(to: original)
        try FileManager.default.linkItem(at: original, to: hard)
        try FileManager.default.createSymbolicLink(at: symbolic, withDestinationURL: original)
        let gate = WorkGate()
        let queue = JobQueue(operation: { url, _, _, _ in try await gate.run(url) })
        queue.execution = .parallel
        queue.enqueue([original], mode: .both)
        queue.enqueue([hard, symbolic], mode: .audio)
        queue.enqueue([input("independent")], mode: .both)
        try await waitFor { await gate.started.count == 2 }
        let started = await gate.started
        XCTAssertEqual(Set(started), Set(["original.mov", input("independent").lastPathComponent]))
        XCTAssertEqual(queue.waitingJobs.count, 2)
        await gate.finishAll(); await queue.waitUntilIdle()
        XCTAssertTrue(queue.jobs.allSatisfy { $0.phase == .completed })
    }

    @MainActor
    func testCancellationHoldsSlotUntilWorkerStopsAndTerminationCancelsAll() async throws {
        let gate = WorkGate()
        let queue = JobQueue(operation: { url, _, _, _ in try await gate.run(url) })
        queue.execution = .serial
        queue.enqueue([input("a"), input("b"), input("c")], mode: .audio)
        try await waitFor { await gate.started.count == 1 }
        let first = queue.jobs[0].id
        queue.cancel(first)
        XCTAssertEqual(queue.runningCount, 1)
        XCTAssertTrue(queue.cancelling.contains(first))
        XCTAssertEqual(queue.waitingJobs.count, 2)
        await gate.release(input("a").lastPathComponent)
        try await waitFor { await gate.started.count == 2 }
        XCTAssertEqual(queue.jobs[0].phase, .cancelled)
        let stop = Task { await queue.stopForTermination() }
        try await waitFor { queue.cancelling.count == 1 }
        await gate.finishAll(); await stop.value
        XCTAssertFalse(queue.isBusy)
        XCTAssertTrue(queue.jobs.allSatisfy { $0.phase == .cancelled })
        XCTAssertEqual(queue.enqueue([input("new")], mode: .video), 0)
    }

    @MainActor
    func testPauseAllowsActiveWorkToFinishAndParallelFailureFreesOnlyOneSlot() async throws {
        let gate = WorkGate()
        let queue = JobQueue(operation: { url, _, _, _ in
            let result = try await gate.run(url)
            if url.lastPathComponent.contains("failure") { throw CompressionError.message("fixture failure") }
            return result
        })
        queue.execution = .parallel
        queue.enqueue([input("failure"), input("good"), input("waiting")], mode: .both)
        try await waitFor { await gate.started.count == 2 }
        queue.togglePause()
        await gate.release(input("failure").lastPathComponent)
        try await waitFor { queue.jobs[0].phase == .failed }
        XCTAssertEqual(queue.runningCount, 1)
        XCTAssertEqual(queue.waitingJobs.count, 1)
        queue.togglePause()
        try await waitFor { await gate.started.count == 3 }
        XCTAssertEqual(queue.runningCount, 2)
        queue.execution = .serial
        XCTAssertEqual(queue.runningCount, 2, "Serial preference must drain, not cancel, active work")
        await gate.finishAll(); await queue.waitUntilIdle()
        XCTAssertEqual(queue.jobs.map(\.phase), [.failed, .completed, .completed])
    }

    @MainActor
    func testDraggingDownAndInvalidOrRunningCards() async throws {
        let gate = WorkGate()
        let queue = JobQueue(operation: { url, _, _, _ in try await gate.run(url) })
        queue.execution = .serial
        queue.enqueue([input("active"), input("a"), input("b"), input("c")], mode: .both)
        let active = queue.jobs[0].id, a = queue.jobs[1].id, c = queue.jobs[3].id
        XCTAssertFalse(queue.moveWaiting(active, to: c))
        XCTAssertFalse(queue.moveWaiting(c, to: active))
        XCTAssertFalse(queue.moveWaiting(UUID(), to: c))
        XCTAssertFalse(queue.moveWaiting(a, to: a))
        XCTAssertTrue(queue.moveWaiting(a, to: c))
        XCTAssertEqual(queue.waitingJobs.map(\.input), [input("b"), input("c"), input("a")])
        queue.cancel(c)
        XCTAssertFalse(queue.moveWaiting(a, to: c))
        await gate.finishAll(); await queue.waitUntilIdle()
    }

    @MainActor
    func testSchedulingPreferencesPersistAndLegacySnapshotRemainsReadable() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = folder.appendingPathComponent("queue.json")
        let queue = JobQueue(storage: storage)
        queue.togglePause()
        queue.execution = .parallel
        queue.enqueue([input("persist"), input("move")], mode: .both)
        queue.moveWaiting(queue.jobs[1].id, to: queue.jobs[0].id)
        let restored = JobQueue(storage: storage)
        XCTAssertEqual(restored.execution, .parallel)
        XCTAssertEqual(restored.jobs.map(\.input), [input("move"), input("persist")])
        XCTAssertEqual(restored.jobs[0].phase, .interrupted)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: storage)) as? [String: Any])
        legacy.removeValue(forKey: "execution")
        var jobs = try XCTUnwrap(legacy["jobs"] as? [[String: Any]])
        jobs[0]["priority"] = 2; legacy["jobs"] = jobs
        try JSONSerialization.data(withJSONObject: legacy).write(to: storage)
        let migrated = JobQueue(storage: storage)
        XCTAssertNil(migrated.persistenceError)
        XCTAssertEqual(migrated.execution, .automatic)
        XCTAssertEqual(migrated.jobs.map(\.input), [input("move"), input("persist")])
    }
}
