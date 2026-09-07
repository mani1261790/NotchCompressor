import Foundation

public enum QueueExecution: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic, serial, parallel
    public var id: String { rawValue }
    public var title: String {
        switch self { case .automatic: "自動"; case .serial: "1件ずつ"; case .parallel: "最大2件" }
    }
}

public enum JobPriority: Int, CaseIterable, Codable, Identifiable, Sendable {
    case low = 0, normal = 1, high = 2
    public var id: Int { rawValue }
    public var title: String {
        switch self { case .low: "低"; case .normal: "標準"; case .high: "高" }
    }
}

public struct SchedulingEnvironment: Equatable, Sendable {
    public var conservesResources: Bool
    public init(conservesResources: Bool) { self.conservesResources = conservesResources }
    public static var current: Self {
        let process = ProcessInfo.processInfo
        return .init(conservesResources: process.isLowPowerModeEnabled || process.thermalState != .nominal
                     || process.activeProcessorCount < 4 || process.physicalMemory < 8 * 1_024 * 1_024 * 1_024)
    }
}
