import Combine
import Foundation

/// Owns one process activity while workers are doing work, independently of any window.
@MainActor
public final class QueueActivity {
    public nonisolated static let options: ProcessInfo.ActivityOptions = [.userInitiated, .idleSystemSleepDisabled]
    private var token: NSObjectProtocol?
    private let begin: () -> NSObjectProtocol
    private let finish: (NSObjectProtocol) -> Void
    private var observation: AnyCancellable?
    public var isActive: Bool { token != nil }

    public init(
        queue: JobQueue,
        begin: @escaping () -> NSObjectProtocol = {
            ProcessInfo.processInfo.beginActivity(options: QueueActivity.options, reason: L10n.text("activity.reason"))
        },
        finish: @escaping (NSObjectProtocol) -> Void = { ProcessInfo.processInfo.endActivity($0) }
    ) {
        self.begin = begin
        self.finish = finish
        observation = queue.$runningIDs.combineLatest(queue.$pausedIDs, queue.$cancelling)
            .combineLatest(queue.$systemSleeping)
            .map { state, sleeping in !sleeping && (!state.0.subtracting(state.1).isEmpty || !state.2.isEmpty) }
            .removeDuplicates()
            .sink { [weak self] working in self?.setWorking(working) }
    }

    private func setWorking(_ working: Bool) {
        if working, token == nil { token = begin() }
        if !working, let current = token {
            token = nil
            finish(current)
        }
    }
    deinit { if let token { finish(token) } }
}
