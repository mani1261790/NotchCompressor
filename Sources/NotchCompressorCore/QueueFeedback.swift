import Foundation

public struct CompletionNotice: Equatable, Sendable {
    public private(set) var count = 0
    public private(set) var originalKeptCount = 0
    public private(set) var originalBytes: Int64 = 0
    public private(set) var outputBytes: Int64 = 0

    public init() {}
    public mutating func include(_ result: CompressionResult) {
        count += 1
        if result.effectiveOutcome == .originalKept { originalKeptCount += 1 }
        originalBytes += result.originalBytes
        outputBytes += result.outputBytes
    }
    public var savedBytes: Int64 { originalBytes - outputBytes }
    public var sizeTransition: String {
        "\(L10n.bytes(originalBytes)) → \(L10n.bytes(outputBytes))"
    }
    public var text: String {
        let bytes = L10n.bytes(abs(savedBytes))
        let difference =
            savedBytes > 0
            ? L10n.text("completion.saved", bytes)
            : savedBytes < 0 ? L10n.text("completion.grew", bytes) : L10n.text("completion.unchanged")
        let retained = originalKeptCount == 0 ? "" : L10n.text("completion.retained", L10n.integer(originalKeptCount))
        return L10n.text("completion.summary", L10n.integer(count), sizeTransition, difference) + retained
    }
}

public struct QueueStatus: Equatable, Sendable {
    public let symbol: String
    public let title: String
    public let count: Int

    public init(jobs: [CompressionJob], running: Set<UUID>, paused: Set<UUID>) {
        let activeCount = running.subtracting(paused).count
        let pausedCount = paused.count
        let waitingCount = jobs.filter { $0.phase == .waiting && !running.contains($0.id) }.count
        let failedCount = jobs.filter { $0.phase == .failed || $0.phase == .interrupted }.count
        var parts: [String] = []
        if activeCount > 0 { parts.append(L10n.text("status.active", L10n.integer(activeCount))) }
        if pausedCount > 0 { parts.append(L10n.text("status.paused", L10n.integer(pausedCount))) }
        if waitingCount > 0 { parts.append(L10n.text("status.waiting", L10n.integer(waitingCount))) }
        if failedCount > 0 { parts.append(L10n.text("status.failed", L10n.integer(failedCount))) }
        title = parts.isEmpty ? L10n.text("status.empty") : parts.joined(separator: " · ")
        symbol =
            activeCount > 0
            ? "arrow.triangle.2.circlepath"
            : pausedCount > 0
                ? "pause.circle"
                : waitingCount > 0
                    ? "clock" : failedCount > 0 ? "exclamationmark.circle" : "arrow.down.right.and.arrow.up.left"
        count = activeCount + pausedCount + waitingCount + failedCount
    }
}

public struct FailureNotice: Equatable, Sendable {
    public let diskSpaceIssue: DiskSpaceIssue?
    public let jobID: UUID?
    public let recoveryRequired: Bool
    public init(diskSpaceIssue: DiskSpaceIssue? = nil, recoveryRequired: Bool = false, jobID: UUID? = nil) {
        self.diskSpaceIssue = diskSpaceIssue; self.recoveryRequired = recoveryRequired; self.jobID = jobID
    }
    public var title: String { diskSpaceIssue == nil ? L10n.text("failure.title") : L10n.text("disk.title") }
    public var body: String {
        if recoveryRequired { return L10n.text("lowSpace.recoveryRequired") }
        if let issue = diskSpaceIssue {
            let deficit =
                issue.additionalBytes.map {
                    L10n.text("disk.freeMore", L10n.bytes($0))
                } ?? L10n.text("disk.check")
            return L10n.text("disk.notice", deficit)
        }
        return L10n.text("failure.body")
    }
}
