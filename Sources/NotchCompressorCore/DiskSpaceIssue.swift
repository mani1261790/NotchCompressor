import Foundation

public struct DiskSpaceIssue: LocalizedError, Codable, Equatable, Sendable {
    public let availableBytes: Int64?
    public let requiredBytes: Int64?

    public init(availableBytes: Int64? = nil, requiredBytes: Int64? = nil) {
        self.availableBytes = availableBytes
        self.requiredBytes = requiredBytes
    }
    // Some non-APFS volumes report zero for the important-usage estimate even
    // when ordinary free space is available. Never undercount that free space.
    static func availableCapacity(in folder: URL) throws -> Int64? {
        let values = try folder.resourceValues(forKeys: [
            .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ])
        return [
            values.volumeAvailableCapacity.map(Int64.init),
            values.volumeAvailableCapacityForImportantUsage,
        ].compactMap { $0 }.map { max(0, $0) }.max()
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
