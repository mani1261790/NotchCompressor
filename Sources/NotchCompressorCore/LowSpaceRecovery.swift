import Foundation
import CryptoKit
import Darwin

public struct LowSpaceRecord: Codable, Identifiable, Sendable {
    public enum Stage: String, Codable, Sendable { case encoding, prepared, installed }
    public let id: UUID
    public let source: URL
    public let sourceVolumeUUID: String
    public let workspace: URL
    public let workspaceVolumeUUID: String
    public let directory: URL
    let originalSize: UInt64
    let originalModified: Date
    let originalInode: UInt64
    public var stage: Stage = .encoding
    var originalHash: String?
    var candidateHash: String?
    public var backup: URL { workspace.appendingPathComponent("original." + source.pathExtension) }
    var candidate: URL { workspace.appendingPathComponent("output." + source.pathExtension.lowercased()) }
    var incoming: URL {
        source.deletingLastPathComponent().appendingPathComponent(".notchcompressor-return-" + id.uuidString)
    }
    var journal: URL { directory.appendingPathComponent(id.uuidString + ".json") }

    init(source: URL, fingerprint: Fingerprint, workspace: URL, context: LowSpaceWorkspace) throws {
        id = UUID(); self.source = source; self.workspace = workspace; directory = context.recoveryDirectory
        originalSize = fingerprint.size; originalModified = fingerprint.modified; originalInode = fingerprint.inode
        sourceVolumeUUID = try LowSpaceRecovery.volumeUUID(source)
        workspaceVolumeUUID = context.volumeUUID
    }
    func sourceUnchanged() -> Bool {
        guard let value = try? Fingerprint(source) else { return false }
        return value.size == originalSize && value.modified == originalModified && value.inode == originalInode
    }
}

public struct LowSpaceRecoveryRequired: LocalizedError, Sendable {
    public let record: LowSpaceRecord
    public var errorDescription: String? { L10n.text("lowSpace.recoveryRequired") }
}

public enum LowSpaceRecovery {
    public static func pending(in directory: URL) throws -> [LowSpaceRecord] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.map { url in
                let record = try JSONDecoder().decode(LowSpaceRecord.self, from: Data(contentsOf: url))
                guard record.journal.standardizedFileURL == url.standardizedFileURL else {
                    throw CompressionError.localized(.init("lowSpace.invalidRecord"))
                }
                return record
            }
    }

    static func volumeUUID(_ url: URL) throws -> String {
        guard let value = try url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString else {
            throw CompressionError.localized(.init("lowSpace.unverifiedDisk"))
        }
        return value
    }

    static func save(_ record: LowSpaceRecord) throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: record.directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(record)
        try data.write(to: record.workspace.appendingPathComponent("recovery.json"), options: .atomic)
        try sync(record.workspace.appendingPathComponent("recovery.json"))
        try sync(record.workspace)
        try data.write(to: record.journal, options: .atomic)
        try sync(record.journal)
        try sync(record.directory)
    }

    static func hash(_ url: URL) throws -> String {
        guard try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isRegularFile == true,
            try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true
        else {
            throw CompressionError.localized(.init("lowSpace.invalidRecord"))
        }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var digest = SHA256()
        while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty { digest.update(data: data) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func sync(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        // Ask for the device's write cache to be flushed where the filesystem supports it.
        _ = fcntl(fd, F_FULLFSYNC)
    }

    static func verifyVolumes(_ record: LowSpaceRecord) throws {
        guard try volumeUUID(record.workspace) == record.workspaceVolumeUUID,
            try volumeUUID(record.source.deletingLastPathComponent()) == record.sourceVolumeUUID,
            record.workspace.lastPathComponent.hasPrefix(".notchcompressor-"),
            record.workspace.resolvingSymlinksInPath() == record.workspace.standardizedFileURL
        else { throw CompressionError.localized(.init("lowSpace.wrongDisk")) }
    }

    /// All work after 'prepared' is recoverable; no error/cancellation may erase the backup.
    static func install(
        _ record: inout LowSpaceRecord, expected: Fingerprint,
        fault: (String) throws -> Void = { _ in }
    ) throws {
        let fm = FileManager.default
        try verifyVolumes(record)
        try Task.checkCancellation()
        guard try Fingerprint(record.source) == expected else {
            throw CompressionError.localized(.init("error.changedReplace"))
        }
        // Compression has already been fully validated by the media engine.
        record.candidateHash = try hash(record.candidate)
        try sync(record.candidate)
        try fm.copyItem(at: record.source, to: record.backup)
        let digest = try hash(record.backup)
        guard try hash(record.source) == digest, try Fingerprint(record.source) == expected else {
            throw CompressionError.localized(.init("error.changedReplace"))
        }
        try sync(record.backup)
        record.originalHash = digest
        try fault("backupVerified")
        try Task.checkCancellation()
        // Do not set the in-memory stage until both journals have been durably written.
        var prepared = record; prepared.stage = .prepared
        try save(prepared)
        record = prepared
        try fault("prepared")
        guard try Fingerprint(record.source) == expected else {
            throw CompressionError.localized(.init("error.changedReplace"))
        }
        let size = Int64(clamping: try Fingerprint(record.candidate).size)
        guard let before = try DiskSpaceIssue.availableCapacity(in: record.source.deletingLastPathComponent()) else {
            throw DiskSpaceIssue(requiredBytes: size + 64 * 1024 * 1024)
        }
        guard Double(before) + Double(expected.size) >= Double(size) + 64 * 1024 * 1024 else {
            throw DiskSpaceIssue(availableBytes: before, requiredBytes: size + 64 * 1024 * 1024)
        }
        try fm.removeItem(at: record.source)
        try sync(record.source.deletingLastPathComponent())
        try fault("sourceRemoved")
        // Snapshots/clones may prevent unlinking from reclaiming the logical file size.
        if let capacity = try DiskSpaceIssue.availableCapacity(in: record.source.deletingLastPathComponent()),
            capacity < size + 64 * 1024 * 1024
        {
            throw DiskSpaceIssue(availableBytes: capacity, requiredBytes: size + 64 * 1024 * 1024)
        }
        try copyBack(record.candidate, digest: record.candidateHash!, record: record)
        try fault("installed")
        record.stage = .installed
        try save(record)
        try finish(record)
    }

    private static func copyBack(_ file: URL, digest: String, record: LowSpaceRecord) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: record.source.path) else {
            throw CompressionError.localized(.init("lowSpace.destinationExists"))
        }
        if fm.fileExists(atPath: record.incoming.path) { try fm.removeItem(at: record.incoming) }
        do {
            try fm.copyItem(at: file, to: record.incoming)
            guard try hash(record.incoming) == digest else {
                throw CompressionError.localized(.init("lowSpace.copyVerification"))
            }
            try sync(record.incoming)
            // Refuse to overwrite a new file created at the original path during the copy.
            guard renamex_np(record.incoming.path, record.source.path, UInt32(RENAME_EXCL)) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            try sync(record.source.deletingLastPathComponent())
        } catch {
            try? fm.removeItem(at: record.incoming)
            throw error
        }
    }

    /// Restore the original when absent; never overwrite an unrelated file.
    public static func recover(_ record: LowSpaceRecord) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: record.workspace.path),
            try volumeUUID(record.workspace.deletingLastPathComponent()) == record.workspaceVolumeUUID,
            try volumeUUID(record.source) == record.sourceVolumeUUID
        {
            let digest = try hash(record.source)
            guard record.sourceUnchanged() || digest == record.originalHash || digest == record.candidateHash else {
                throw CompressionError.localized(.init("lowSpace.destinationExists"))
            }
            try finish(record); return
        }
        try verifyVolumes(record)
        if record.stage == .encoding {
            guard record.sourceUnchanged() else {
                throw CompressionError.localized(.init("lowSpace.destinationExists"))
            }
            try finish(record); return
        }
        if fm.fileExists(atPath: record.source.path) {
            let digest = try hash(record.source)
            guard digest == record.originalHash || digest == record.candidateHash else {
                throw CompressionError.localized(.init("lowSpace.destinationExists"))
            }
            try sync(record.source)
            try sync(record.source.deletingLastPathComponent())
        } else {
            guard let digest = record.originalHash, try hash(record.backup) == digest else {
                throw CompressionError.localized(.init("lowSpace.copyVerification"))
            }
            try copyBack(record.backup, digest: digest, record: record)
        }
        try finish(record)
    }

    static func finish(_ record: LowSpaceRecord) throws {
        let fm = FileManager.default
        // Keep the local locator if external cleanup fails (e.g. disconnected volume).
        if fm.fileExists(atPath: record.incoming.path) { try fm.removeItem(at: record.incoming) }
        if fm.fileExists(atPath: record.workspace.path) { try fm.removeItem(at: record.workspace) }
        if fm.fileExists(atPath: record.journal.path) { try fm.removeItem(at: record.journal) }
        if (try? fm.contentsOfDirectory(atPath: record.directory.path).isEmpty) == true {
            try? fm.removeItem(at: record.directory)
        }
    }
}
