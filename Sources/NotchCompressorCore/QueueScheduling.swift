import Foundation

public enum QueueExecution: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic, serial, parallel
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .automatic: L10n.text("schedule.automatic");
        case .serial: L10n.text("schedule.serial");
        case .parallel: L10n.text("schedule.parallel")
        }
    }
}

public struct SchedulingEnvironment: Equatable, Sendable {
    public var conservesResources: Bool
    public init(conservesResources: Bool) { self.conservesResources = conservesResources }
    public static var current: Self {
        let process = ProcessInfo.processInfo
        return .init(
            conservesResources: process.isLowPowerModeEnabled || process.thermalState != .nominal
                || process.activeProcessorCount < 4 || process.physicalMemory < 8 * 1_024 * 1_024 * 1_024)
    }
}
