import Foundation

/// One control per job. The lock serializes process transitions and the final
/// atomic replacement, so a pause can never be accepted after commit begins.
public final class CompressionControl: @unchecked Sendable {
    @TaskLocal public static var current: CompressionControl?
    private let lock = NSLock()
    private var process: Process?
    private var suspended = false
    private var paused = false
    private var finished = false

    public init() {}
    public var isPaused: Bool { lock.withLock { paused } }

    @discardableResult
    public func pause() -> Bool {
        lock.withLock {
            guard !finished else { return false }
            if paused { return true }
            if let process, process.isRunning {
                guard process.suspend() else { return false }
                suspended = true
            }
            paused = true
            return true
        }
    }

    @discardableResult
    public func resume() -> Bool {
        lock.withLock {
            if suspended, let process, process.isRunning {
                guard process.resume() else { return false }
            }
            suspended = false
            paused = false
            return true
        }
    }

    func launch(_ process: Process) throws {
        try lock.withLock {
            try process.run()
            self.process = process
            if paused, process.isRunning {
                guard process.suspend() else {
                    process.terminate()
                    throw CompressionError.message("圧縮を一時停止できませんでした。")
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
            guard !paused else { return nil }
            finished = true
            return try body()
        }
    }
}
