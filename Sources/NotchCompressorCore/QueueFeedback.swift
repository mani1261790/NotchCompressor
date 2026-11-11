import Foundation

public struct CompletionNotice: Equatable, Sendable {
    public private(set) var count = 0
    public private(set) var originalBytes: Int64 = 0
    public private(set) var outputBytes: Int64 = 0

    public init() {}
    public mutating func include(_ result: CompressionResult) {
        count += 1
        originalBytes += result.originalBytes
        outputBytes += result.outputBytes
    }
    public var savedBytes: Int64 { originalBytes - outputBytes }
    public var text: String {
        let bytes = ByteCountFormatter.string(fromByteCount: abs(savedBytes), countStyle: .file)
        let difference = savedBytes > 0 ? "\(bytes)削減" : savedBytes < 0 ? "\(bytes)増加" : "容量の変化なし"
        return "\(count)件完了 · \(difference)"
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
        if activeCount > 0 { parts.append("実行中 \(activeCount)件") }
        if pausedCount > 0 { parts.append("一時停止 \(pausedCount)件") }
        if waitingCount > 0 { parts.append("待機 \(waitingCount)件") }
        if failedCount > 0 { parts.append("要確認 \(failedCount)件") }
        title = parts.isEmpty ? "キューは空です" : parts.joined(separator: " · ")
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
