import Foundation

public struct DiskSpaceIssue: LocalizedError, Codable, Equatable, Sendable {
    public let availableBytes: Int64?
    public let requiredBytes: Int64?
    public let externalWorkspaceBytes: Int64?

    public init(availableBytes: Int64? = nil, requiredBytes: Int64? = nil, externalWorkspaceBytes: Int64? = nil) {
        self.availableBytes = availableBytes
        self.requiredBytes = requiredBytes
        self.externalWorkspaceBytes = externalWorkspaceBytes
    }
    // Reclaimable/important-usage space is not guaranteed to be free for this write.
    static func availableCapacity(in folder: URL) throws -> Int64? {
        let values = try folder.resourceValues(forKeys: [
            .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ])
        return usableCapacity(
            ordinary: values.volumeAvailableCapacity.map(Int64.init),
            important: values.volumeAvailableCapacityForImportantUsage)
    }

    static func usableCapacity(ordinary: Int64?, important: Int64?) -> Int64? {
        if let ordinary { return max(0, ordinary) }
        // Purgeable space alone is not proof that an external workspace can be written.
        return nil
    }

    public var additionalBytes: Int64? {
        guard let availableBytes, let requiredBytes else { return nil }
        return max(0, requiredBytes - availableBytes)
    }
    public var errorDescription: String? {
        var lines = [availableBytes == nil ? L10n.text("disk.unknown") : L10n.text("disk.source")]
        if let availableBytes, let requiredBytes, let additionalBytes {
            let format = { L10n.bytes($0) }
            lines.append(
                L10n.text("disk.amounts", format(availableBytes), format(requiredBytes), format(additionalBytes)))
        }
        lines.append(L10n.text("disk.staging"))
        lines.append(L10n.text("disk.cleanup"))
        lines.append(L10n.text("disk.move"))
        lines.append(L10n.text("disk.estimate"))
        return lines.joined(separator: "\n\n")
    }

    public static func classify(_ error: Error) -> DiskSpaceIssue? {
        if let issue = error as? DiskSpaceIssue { return issue }
        var current = error as NSError
        for _ in 0..<8 {
            if (current.domain == NSPOSIXErrorDomain && current.code == Int(ENOSPC))
                || (current.domain == NSCocoaErrorDomain && current.code == CocoaError.fileWriteOutOfSpace.rawValue)
            {
                return DiskSpaceIssue()
            }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
            current = underlying
        }
        return nil
    }
}
