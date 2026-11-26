import Foundation

/// Same-folder staging, or a task-scoped external workspace with recoverable replacement.
final class OutputTransaction {
    private var recovery: LowSpaceRecord?
    let source: URL
    let fingerprint: Fingerprint
    let staging: URL
    let output: URL

    init(source: URL, estimatedBytes: Double, expected: Fingerprint? = nil) throws {
        self.source = source
        fingerprint = try Fingerprint(source)
        if let expected, expected != fingerprint { throw CompressionError.localized(.init("error.changedRetry")) }
        let originalFolder = source.deletingLastPathComponent()
        let folder = LowSpaceWorkspace.current?.folder ?? originalFolder
        guard FileManager.default.isWritableFile(atPath: folder.path),
            FileManager.default.isWritableFile(atPath: originalFolder.path)
        else {
            throw CompressionError.localized(.init("error.folder"))
        }
        if let workspace = LowSpaceWorkspace.current {
            let required = try LowSpaceDisk.requiredBytes(
                for: source, estimatedOutput: Int64(min(estimatedBytes.rounded(.up), Double(Int64.max - 1024))))
            let disk = try LowSpaceDisk.inspect(folder, source: source, requiredBytes: required)
            guard disk.uuid == workspace.volumeUUID else {
                throw CompressionError.localized(.init("lowSpace.wrongDisk"))
            }
        }
        if let capacity = try DiskSpaceIssue.availableCapacity(in: folder), Double(capacity) < estimatedBytes {
            throw DiskSpaceIssue(
                availableBytes: max(0, capacity),
                requiredBytes: Int64(min(estimatedBytes.rounded(.up), Double(Int64.max - 1024))))
        }
        staging = folder.appendingPathComponent(".notchcompressor-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        output = staging.appendingPathComponent("output." + source.pathExtension.lowercased())
        if let context = LowSpaceWorkspace.current {
            do {
                let record = try LowSpaceRecord(
                    source: source, fingerprint: fingerprint, workspace: staging, context: context)
                try LowSpaceRecovery.save(record)
                recovery = record
            } catch {
                try? FileManager.default.removeItem(at: staging)
                throw error
            }
        }
    }

    func cleanUp() {
        if let recovery {
            if recovery.stage == .encoding && recovery.sourceUnchanged() { try? LowSpaceRecovery.finish(recovery) }
        } else {
            try? FileManager.default.removeItem(at: staging)
        }
    }

    func commit(note: String? = nil, noteMessage: LocalizedMessage? = nil) async throws -> CompressionResult {
        if var record = recovery {
            let candidate = Int64(clamping: try Fingerprint(output).size)
            let original = Int64(clamping: fingerprint.size)
            // Seal the commit under the control lock, then perform the long copy without holding it.
            if let control = CompressionControl.current {
                while true {
                    try await control.checkpoint()
                    if control.commit({ true }) == true { break }
                }
            }
            if candidate < original {
                do { try LowSpaceRecovery.install(&record, expected: fingerprint); recovery = nil } catch {
                    recovery = record
                    if record.stage != .encoding { throw LowSpaceRecoveryRequired(record: record) }
                    throw error
                }
            } else {
                try Task.checkCancellation()
                guard try Fingerprint(source) == fingerprint else {
                    throw CompressionError.localized(.init("error.changed"))
                }
            }
            return CompressionResult(
                output: source, originalBytes: original,
                outputBytes: candidate < original ? candidate : original, note: note,
                outcome: candidate < original ? .replaced : .originalKept, candidateBytes: candidate,
                noteMessage: noteMessage)
        }
        if let control = CompressionControl.current {
            while true {
                try await control.checkpoint()
                if let result = try control.commit({
                    try CompressionEngine.finalizeVerifiedOutput(
                        output, original: source, expected: fingerprint, note: note, noteMessage: noteMessage)
                }) {
                    return result
                }
            }
        }
        return try CompressionEngine.finalizeVerifiedOutput(
            output, original: source, expected: fingerprint, note: note, noteMessage: noteMessage)
    }
}
