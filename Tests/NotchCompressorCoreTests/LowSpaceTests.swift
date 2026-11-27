import XCTest
@testable import NotchCompressorCore

final class LowSpaceTests: XCTestCase {
    private func fixture(_ body: (LowSpaceRecord, Fingerprint) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.mov")
        try Data(repeating: 42, count: 8192).write(to: source)
        let workspace = root.appendingPathComponent(".notchcompressor-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        let context = LowSpaceWorkspace(
            folder: root, volumeUUID: try LowSpaceRecovery.volumeUUID(root),
            recoveryDirectory: root.appendingPathComponent("records"))
        let fingerprint = try Fingerprint(source)
        let record = try LowSpaceRecord(
            source: source, fingerprint: fingerprint, workspace: workspace, context: context)
        try Data(repeating: 7, count: 2048).write(to: record.candidate)
        try LowSpaceRecovery.save(record)
        try body(record, fingerprint)
    }
    func testOrdinaryCapacityDoesNotCountPurgeableSpace() {
        XCTAssertEqual(DiskSpaceIssue.usableCapacity(ordinary: 0, important: 100000), 0)
        XCTAssertEqual(DiskSpaceIssue.usableCapacity(ordinary: 12, important: 100000), 12)
    }
    func testSuccessfulInstallRemovesTemporaryRecords() throws {
        try fixture { initial, fingerprint in
            var record = initial
            try LowSpaceRecovery.install(&record, expected: fingerprint)
            XCTAssertEqual(try Data(contentsOf: record.source), Data(repeating: 7, count: 2048))
            XCTAssertFalse(FileManager.default.fileExists(atPath: record.workspace.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: record.directory.path))
        }
    }
    func testCrashBoundariesRecoverOriginalOrInstalledCandidate() throws {
        struct Injected: Error {}
        for stage in ["backupVerified", "prepared", "sourceRemoved", "installed"] {
            try fixture { initial, fingerprint in
                var record = initial
                XCTAssertThrowsError(
                    try LowSpaceRecovery.install(
                        &record, expected: fingerprint,
                        fault: {
                            if $0 == stage { throw Injected() }
                        }))
                let persisted = try XCTUnwrap(LowSpaceRecovery.pending(in: record.directory).first)
                if stage == "sourceRemoved" {
                    XCTAssertFalse(FileManager.default.fileExists(atPath: record.source.path))
                    XCTAssertEqual(try Data(contentsOf: record.backup), Data(repeating: 42, count: 8192))
                }
                try LowSpaceRecovery.recover(persisted)
                let expected =
                    ["installed", "sourceRemoved"].contains(stage)
                    ? Data(repeating: 7, count: 2048) : Data(repeating: 42, count: 8192)
                XCTAssertEqual(try Data(contentsOf: record.source), expected)
                XCTAssertFalse(FileManager.default.fileExists(atPath: record.directory.path))
            }
        }
    }
    func testRecoveryNeverOverwritesUnrelatedFile() throws {
        struct Injected: Error {}
        try fixture { initial, fingerprint in
            var record = initial
            XCTAssertThrowsError(
                try LowSpaceRecovery.install(
                    &record, expected: fingerprint,
                    fault: {
                        if $0 == "sourceRemoved" { throw Injected() }
                    }))
            try Data("new user file".utf8).write(to: record.source)
            XCTAssertThrowsError(try LowSpaceRecovery.recover(record))
            XCTAssertEqual(try Data(contentsOf: record.source), Data("new user file".utf8))
            XCTAssertTrue(FileManager.default.fileExists(atPath: record.backup.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: record.journal.path))
        }
    }
    func testWriteProbeLeavesNoFilesAndDoesNotCreateMissingFolder() throws {
        try fixture { record, _ in
            let before = try FileManager.default.contentsOfDirectory(atPath: record.workspace.path)
            try LowSpaceWorkspace.checkWritable(in: record.workspace)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: record.workspace.path), before)
            let missing = record.workspace.appendingPathComponent("missing")
            XCTAssertThrowsError(try LowSpaceWorkspace.checkWritable(in: missing))
            XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        }
    }
    func testUnknownOrdinaryCapacityDoesNotOfferPurgeableSpace() {
        XCTAssertNil(DiskSpaceIssue.usableCapacity(ordinary: nil, important: 10_000_000_000))
    }
    func testExternalSpaceEstimateDoesNotGrowOnEveryRetry() throws {
        try fixture { record, _ in
            let required = try LowSpaceDisk.requiredBytes(for: record.source, estimatedOutput: 100_000_000)
            let issue = DiskSpaceIssue(availableBytes: 1, requiredBytes: required, externalWorkspaceBytes: required)
            for _ in 0..<5 {
                XCTAssertEqual(try LowSpaceDisk.requiredBytes(for: record.source, issue: issue), required)
            }
            let restored = try JSONDecoder().decode(DiskSpaceIssue.self, from: JSONEncoder().encode(issue))
            XCTAssertEqual(restored.externalWorkspaceBytes, required)
            let legacy = try JSONDecoder().decode(DiskSpaceIssue.self, from: Data("{\"requiredBytes\":123}".utf8))
            XCTAssertNil(legacy.externalWorkspaceBytes)
        }
    }
    func testCorruptRecordDoesNotHideOtherRecoveries() throws {
        try fixture { record, _ in
            let corrupt = record.directory.appendingPathComponent("corrupt.json")
            try Data("broken".utf8).write(to: corrupt)
            let scan = try LowSpaceRecovery.scan(in: record.directory)
            XCTAssertEqual(scan.records.map(\.id), [record.id])
            XCTAssertEqual(scan.unreadable.map { $0.resolvingSymlinksInPath() }, [corrupt.resolvingSymlinksInPath()])
            XCTAssertTrue(FileManager.default.fileExists(atPath: corrupt.path))
        }
    }
    func testCapacityLossAfterEvacuationRetainsBackupAndResumesSmallerOutput() throws {
        try fixture { initial, fingerprint in
            var record = initial, checks = 0
            XCTAssertThrowsError(
                try LowSpaceRecovery.install(
                    &record, expected: fingerprint,
                    capacity: { _ in
                        checks += 1
                        return checks == 1 ? 100_000_000 : 0
                    }))
            XCTAssertFalse(FileManager.default.fileExists(atPath: record.source.path))
            XCTAssertEqual(try Data(contentsOf: record.backup), Data(repeating: 42, count: 8192))
            try LowSpaceRecovery.recover(record)
            XCTAssertEqual(try Data(contentsOf: record.source), Data(repeating: 7, count: 2048))
        }
    }
    func testUnknownCapacityDoesNotRemoveOriginal() throws {
        try fixture { initial, fingerprint in
            var record = initial
            XCTAssertThrowsError(try LowSpaceRecovery.install(&record, expected: fingerprint, capacity: { _ in nil }))
            XCTAssertTrue(record.sourceUnchanged())
            try LowSpaceRecovery.recover(record)
            XCTAssertFalse(FileManager.default.fileExists(atPath: record.journal.path))
        }
    }
    func testDamagedCandidateRecoveryFallsBackToVerifiedOriginal() throws {
        struct Injected: Error {}
        try fixture { initial, fingerprint in
            var record = initial
            XCTAssertThrowsError(
                try LowSpaceRecovery.install(
                    &record, expected: fingerprint,
                    fault: {
                        if $0 == "sourceRemoved" { throw Injected() }
                    }))
            try Data("broken".utf8).write(to: record.candidate)
            try LowSpaceRecovery.recover(record)
            XCTAssertEqual(try Data(contentsOf: record.source), Data(repeating: 42, count: 8192))
        }
    }
    @MainActor
    func testStaleTaskDoesNotInspectOrWriteToDisk() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let disk = LowSpaceDisk(root: root, name: "not accessed", uuid: "test", storageGroup: "test", availableBytes: 1)
        let queue = JobQueue()
        do {
            try await queue.retryUsingExternalDisk(UUID(), folder: root, disk: disk)
            XCTFail("A removed task must not succeed")
        } catch let error as CompressionError {
            XCTAssertEqual(error.localizedMessage.key, "lowSpace.taskUnavailable")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
    func testCrossVolumeBackupAndInstall() throws {
        try fixture { initial, fingerprint in
            let root = initial.source.deletingLastPathComponent()
            let mount = root.appendingPathComponent("mounted")
            try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
            func diskImage(_ arguments: [String]) throws {
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                process.arguments = arguments; process.standardOutput = FileHandle.nullDevice;
                process.standardError = FileHandle.nullDevice
                try process.run(); process.waitUntilExit()
                XCTAssertEqual(process.terminationStatus, 0)
            }
            let image = root.appendingPathComponent("external.dmg")
            try diskImage(["create", "-size", "64m", "-fs", "HFS+", "-type", "UDIF", image.path])
            try diskImage(["attach", "-nobrowse", "-mountpoint", mount.path, image.path])
            defer { try? diskImage(["detach", mount.path]) }
            let workspace = mount.appendingPathComponent(".notchcompressor-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
            let context = LowSpaceWorkspace(
                folder: mount, volumeUUID: try LowSpaceRecovery.volumeUUID(mount),
                recoveryDirectory: root.appendingPathComponent("external-records"))
            var record = try LowSpaceRecord(
                source: initial.source, fingerprint: fingerprint, workspace: workspace, context: context)
            XCTAssertNotEqual(record.sourceVolumeUUID, record.workspaceVolumeUUID)
            try Data(repeating: 7, count: 2048).write(to: record.candidate)
            try LowSpaceRecovery.save(record)
            try LowSpaceRecovery.install(&record, expected: fingerprint)
            XCTAssertEqual(try Data(contentsOf: record.source), Data(repeating: 7, count: 2048))
            XCTAssertFalse(FileManager.default.fileExists(atPath: record.workspace.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: record.journal.path))
        }
    }
    func testInternalDiskIsNotOfferedAsExternalWorkspace() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("source.mov")
        XCTAssertThrowsError(
            try LowSpaceDisk.inspect(source.deletingLastPathComponent(), source: source, requiredBytes: 1))
    }
    func testCleanupInterruptionCanBeRecovered() throws {
        try fixture { initial, _ in
            // Crash after encoding cleanup removed its workspace, before removing its local locator.
            try FileManager.default.removeItem(at: initial.workspace)
            try LowSpaceRecovery.recover(initial)
            XCTAssertTrue(initial.sourceUnchanged())
            XCTAssertFalse(FileManager.default.fileExists(atPath: initial.journal.path))
        }
    }
    @MainActor
    func testExternalRetryRunsAloneAndDoesNotPersistSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = LowSpaceExecutionLog()
        let storage = root.appendingPathComponent("queue.json")
        let queue = JobQueue(
            storage: storage,
            operation: { url, _, _, _ in
                let external = LowSpaceWorkspace.current != nil
                if url.lastPathComponent == "external.mov" && !external { throw DiskSpaceIssue() }
                await log.start(external: external)
                try await Task.sleep(for: .milliseconds(80))
                await log.finish(external: external)
                return CompressionResult(output: url, originalBytes: 100, outputBytes: 50, note: nil)
            })
        queue.execution = .parallel
        queue.enqueue([root.appendingPathComponent("external.mov")], mode: .both)
        await queue.waitUntilIdle()
        let id = try XCTUnwrap(queue.jobs.first?.id)
        queue.togglePause()
        let workspace = LowSpaceWorkspace(
            folder: root.appendingPathComponent("never-save-this-location"),
            volumeUUID: "selection-not-saved", recoveryDirectory: root.appendingPathComponent("records"))
        queue.scheduleExternalRetry(id, workspace: workspace)
        queue.enqueue([root.appendingPathComponent("other.mov"), root.appendingPathComponent("last.mov")], mode: .both)
        let json = try String(contentsOf: storage)
        XCTAssertFalse(json.contains("never-save-this-location"))
        XCTAssertFalse(json.contains("selection-not-saved"))
        queue.togglePause()
        await queue.waitUntilIdle()
        let violation = await log.overlappedExternal
        XCTAssertFalse(violation)
        XCTAssertEqual(queue.jobs.filter { $0.phase == .completed }.count, 3)
    }

}

private actor LowSpaceExecutionLog {
    var running = 0
    var externalRunning = false
    var overlappedExternal = false
    func start(external: Bool) {
        if external && running > 0 || externalRunning { overlappedExternal = true }
        running += 1; externalRunning = externalRunning || external
    }
    func finish(external: Bool) { running -= 1; if external { externalRunning = false } }
}
