import Foundation

/// One control per job. The lock serializes process transitions and the final
/// atomic replacement, so a pause can never be accepted after commit begins.
public final class CompressionControl: @unchecked Sendable {
    @TaskLocal public static var current: CompressionControl?
    private let lock = NSLock()
    private var process: Process?
    private var suspended = false
    public enum PauseReason: Hashable, Sendable { case user, systemSleep }
    private var reasons = Set<PauseReason>()
    private var finished = false
    private var sleepGeneration: UInt64 = 0

    public init() {}
    var hasCommitted: Bool { lock.withLock { finished } }
    public var isPaused: Bool { lock.withLock { !reasons.isEmpty } }
    /// A successful system-sleep pause invalidates assumptions about hardware sessions.
    /// User pauses and duplicate sleep notifications must not trigger recovery retries.
    var systemSleepGeneration: UInt64 { lock.withLock { sleepGeneration } }

    @discardableResult
    public func pause(_ reason: PauseReason = .user) -> Bool {
        lock.withLock {
            guard !finished else { return false }
            if !reasons.isEmpty {
                if reason == .systemSleep, !reasons.contains(reason) { sleepGeneration &+= 1 }
                reasons.insert(reason)
                return true
            }
            if let process, process.isRunning {
                guard process.suspend() else { return false }
                suspended = true
            }
            reasons.insert(reason)
            if reason == .systemSleep { sleepGeneration &+= 1 }
            return true
        }
    }

    @discardableResult
    public func resume(_ reason: PauseReason = .user) -> Bool {
        lock.withLock {
            var remaining = reasons
            remaining.remove(reason)
            if !remaining.isEmpty { reasons = remaining; return true }
            if suspended, let process, process.isRunning {
                guard process.resume() else { return false }
            }
            suspended = false
            reasons = remaining
            return true
        }
    }

    /// Cancellation must release every suspension reason before terminating a child.
    func resumeForCancellation() {
        lock.withLock {
            if suspended, let process, process.isRunning { _ = process.resume() }
            suspended = false
            reasons.removeAll()
        }
    }

    func launch(_ process: Process) throws {
        try lock.withLock {
            try process.run()
            self.process = process
            if !reasons.isEmpty, process.isRunning {
                guard process.suspend() else {
                    process.terminate()
                    throw CompressionError.localized(.init("error.pause"))
                }
                suspended = true
            }
        }
    }

    func detach(_ process: Process) {
        lock.withLock {
            if self.process === process { self.process = nil; suspended = false }
        }
    }

    public func checkpoint() async throws {
        if lock.withLock({ finished }) { return }
        while isPaused {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(50))
        }
        try Task.checkCancellation()
    }

    /// Returns nil when a pause won the race; caller waits and tries again.
    func commit<T>(_ body: () throws -> T) rethrows -> T? {
        try lock.withLock {
            guard reasons.isEmpty else { return nil }
            finished = true
            return try body()
        }
    }
}
