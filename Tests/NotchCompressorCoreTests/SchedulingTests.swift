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
        XCTAssertTrue(queue.moveQueued(third, to: first))
        XCTAssertTrue(queue.moveQueued(second, to: third))
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
        XCTAssertFalse(queue.moveQueued(active, to: c))
        XCTAssertFalse(queue.moveQueued(c, to: active))
        XCTAssertFalse(queue.moveQueued(UUID(), to: c))
        XCTAssertFalse(queue.moveQueued(a, to: a))
        XCTAssertTrue(queue.moveQueued(a, to: c))
        XCTAssertEqual(queue.waitingJobs.map(\.input), [input("b"), input("c"), input("a")])
        queue.cancel(c)
        XCTAssertTrue(queue.moveQueued(a, to: c))
        await gate.finishAll(); await queue.waitUntilIdle()
    }

    @MainActor
    func testCompletedCardsDisappearIndividuallyWhileOthersKeepRunning() async throws {
        let gate = WorkGate()
        let queue = JobQueue(operation: { url, _, _, _ in try await gate.run(url) })
        queue.execution = .parallel
        queue.enqueue([input("a"), input("b"), input("c")], mode: .both)
        try await waitFor { await gate.started.count == 2 }
        XCTAssertEqual(queue.displayedJobs.count, 3)
        await gate.release(input("b").lastPathComponent)
        try await waitFor { await gate.started.count == 3 }
        XCTAssertEqual(Set(queue.displayedJobs.map(\.input)), Set([input("a"), input("c")]))
        XCTAssertEqual(queue.jobs.first { $0.input == input("b") }?.phase, .completed)
        queue.cancel(queue.jobs.first { $0.input == input("c") }!.id)
        await gate.finishAll(); await queue.waitUntilIdle()
        XCTAssertEqual(queue.displayedJobs.map(\.phase), [.cancelled])
        XCTAssertEqual(queue.jobs.filter { $0.phase == .completed }.count, 2)
        queue.clearFinished()
        XCTAssertTrue(queue.displayedJobs.isEmpty)
    }

    @MainActor
    func testRunningAndStoppingStayPinnedUntilWorkerReturns() async throws {
        let gate = WorkGate()
        let queue = JobQueue(environment: { .init(conservesResources: false) }) { url, _, _, _ in try await gate.run(url) }
        queue.enqueue([input("v1"), input("v2")], mode: .video)
        queue.enqueue([input("audio")], mode: .audio)
        try await waitFor { await gate.started.count == 2 }
        let v1 = queue.jobs[0].id, v2 = queue.jobs[1].id, audio = queue.jobs[2].id
        XCTAssertEqual(queue.displayedJobs.map(\.id), [v1, audio, v2])
        XCTAssertFalse(queue.remove(v1))
        XCTAssertFalse(queue.moveQueued(v2, to: audio))
        queue.cancel(v1)
        XCTAssertTrue(queue.cancelling.contains(v1))
        XCTAssertFalse(queue.remove(v1))
        XCTAssertFalse(queue.moveQueued(v1, to: v2))
        XCTAssertEqual(queue.displayedJobs.first?.id, v1)
        XCTAssertFalse(queue.cancelling.contains(audio), "Individual stop must not cancel another worker")
        await gate.release(input("v1").lastPathComponent)
        try await waitFor { await gate.started.count == 3 }
        XCTAssertEqual(queue.displayedJobs.map(\.id), [audio, v2, v1], "Backfilled work must follow the already running card")
        XCTAssertTrue(queue.remove(v1))
        XCTAssertFalse(queue.remove(audio))
        await gate.finishAll(); await queue.waitUntilIdle()
    }

    @MainActor
    func testStopAllPausesDispatchAndLeavesWaitingCardsRemovable() async throws {
        let gate = WorkGate()
        let queue = JobQueue(operation: { url, _, _, _ in try await gate.run(url) })
        queue.execution = .parallel
        queue.enqueue([input("a"), input("b"), input("c"), input("d")], mode: .both)
        try await waitFor { await gate.started.count == 2 }
        let ids = queue.jobs.map(\.id)
        queue.stopAll()
        XCTAssertTrue(queue.isPaused)
        XCTAssertEqual(queue.cancelling, Set(ids.prefix(2)))
        XCTAssertFalse(queue.remove(ids[0]))
        XCTAssertTrue(queue.moveQueued(ids[3], to: ids[2]))
        XCTAssertTrue(queue.remove(ids[2]))
        await gate.finishAll(); await queue.waitUntilIdle()
        let started = await gate.started
        XCTAssertEqual(started.count, 2, "Stopping all must not dispatch a waiting job as workers exit")
        XCTAssertEqual(queue.waitingJobs.map(\.id), [ids[3]])
        XCTAssertTrue(queue.moveQueued(ids[0], to: ids[3]))
        XCTAssertTrue(queue.remove(ids[1]))
        queue.togglePause()
        await queue.waitUntilIdle()
        XCTAssertEqual(queue.jobs.first { $0.id == ids[3] }?.phase, .completed)
    }

    @MainActor
    func testRemovingInactiveCardsPersistsWithoutDeletingFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.mov")
        let storage = folder.appendingPathComponent("queue.json")
        let bytes = Data("preserve original".utf8)
        try bytes.write(to: source)
        let queue = JobQueue(storage: storage)
        queue.togglePause()
        queue.enqueue([source], mode: .both)
        XCTAssertTrue(queue.remove(queue.jobs[0].id))
        XCTAssertFalse(queue.remove(UUID()))
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertTrue(JobQueue(storage: storage).jobs.isEmpty)
        for phase: JobPhase in [.cancelled, .failed, .interrupted] {
            var job = CompressionJob(input: source, mode: .both, settings: .init())
            job.phase = phase
            try JSONEncoder().encode(QueueSnapshot(settings: .init(), jobs: [job])).write(to: storage)
            let restored = JobQueue(storage: storage)
            XCTAssertTrue(restored.remove(job.id))
            XCTAssertTrue(JobQueue(storage: storage).jobs.isEmpty)
            XCTAssertEqual(try Data(contentsOf: source), bytes)
        }
    }

    @MainActor
    func testStoppedCardRemainsFirstAndSurvivesHistoryTrimmingAndRestore() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = folder.appendingPathComponent("queue.json")
        var old = CompressionJob(input: input("old"), mode: .both, settings: .init())
        old.phase = .cancelled
        try JSONEncoder().encode(QueueSnapshot(settings: .init(), jobs: [old])).write(to: storage)
        let gate = WorkGate()
        let queue = JobQueue(storage: storage, operation: { url, _, _, _ in try await gate.run(url) })
        queue.execution = .serial
        queue.enqueue([input("stop"), input("waiting")], mode: .both)
        try await waitFor { await gate.started.count == 1 }
        let stoppedID = try XCTUnwrap(queue.jobs.first { $0.input == input("stop") }?.id)
        queue.stopAll()
        await gate.finishAll(); await queue.waitUntilIdle()
        XCTAssertEqual(queue.displayedJobs.first?.id, stoppedID)
        XCTAssertEqual(queue.displayedJobs.first?.phase, .cancelled)
        XCTAssertTrue(queue.canRemove(stoppedID))
        XCTAssertTrue(queue.canReorder(stoppedID))
        XCTAssertEqual(JobQueue(storage: storage).displayedJobs.first?.id, stoppedID)
        // Retained stopped cards must not be pruned as completed history grows.
        queue.togglePause()
        queue.enqueue((0..<105).map { input("history-\($0)") }, mode: .audio)
        await queue.waitUntilIdle()
        XCTAssertEqual(queue.displayedJobs.map(\.id), [stoppedID, old.id])
        XCTAssertEqual(queue.jobs.filter { $0.phase == .completed }.count, 100)
        XCTAssertTrue(queue.moveQueued(stoppedID, to: old.id))
        XCTAssertEqual(queue.displayedJobs.last?.id, stoppedID)
        XCTAssertTrue(queue.remove(stoppedID))
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
        queue.moveQueued(queue.jobs[1].id, to: queue.jobs[0].id)
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
