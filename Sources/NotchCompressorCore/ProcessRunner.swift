import Foundation
import Darwin

private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

public struct ProcessRunner: Sendable {
    public init() {}

    public func run(executable: URL, arguments: [String], timeout: TimeInterval = 86_400,
                    progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> Data {
        let cancellation = CancellationFlag()
        let control = CompressionControl.current
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await Task.detached(priority: .utility) {
                let fm = FileManager.default
                let folder = fm.temporaryDirectory.appendingPathComponent("NotchCompressor-process-" + UUID().uuidString)
                try fm.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                defer { try? fm.removeItem(at: folder) }
                let stdout = folder.appendingPathComponent("stdout")
                let stderr = folder.appendingPathComponent("stderr")
                fm.createFile(atPath: stdout.path, contents: nil)
                fm.createFile(atPath: stderr.path, contents: nil)
                let output = try FileHandle(forWritingTo: stdout)
                let errors = try FileHandle(forWritingTo: stderr)
                defer { try? output.close(); try? errors.close() }
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = output
                process.standardError = errors
                guard !cancellation.cancelled else { throw CancellationError() }
                if let control { try control.launch(process) } else { try process.run() }
                defer { control?.detach(process) }
                var lastTick = ProcessInfo.processInfo.systemUptime
                var activeTime: TimeInterval = 0
                var stopTime: Date?
                var timedOut = false
                while process.isRunning {
                    let now = ProcessInfo.processInfo.systemUptime
                    if control?.isPaused != true { activeTime += now - lastTick }
                    lastTick = now
                    if cancellation.cancelled || activeTime > timeout {
                        timedOut = !cancellation.cancelled
                        if stopTime == nil {
                            _ = control?.resume()
                            process.terminate(); stopTime = Date()
                        }
                        if let stopTime, Date().timeIntervalSince(stopTime) > 2, process.isRunning {
                            kill(process.processIdentifier, SIGKILL)
                        }
                    }
                    if control?.isPaused != true, let tail = try? Self.tail(stdout, limit: 8192), let text = String(data: tail, encoding: .utf8) { progress(text) }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                if cancellation.cancelled { throw CancellationError() }
                if timedOut { throw CompressionError.message("処理が制限時間を超えました。ファイルとツールを確認してください。") }
                guard process.terminationStatus == 0 else {
                    let message = String(data: (try? Self.tail(stderr, limit: 4096)) ?? Data(), encoding: .utf8) ?? ""
                    throw CompressionError.message("変換ツールが失敗しました（\(process.terminationStatus)）。\n\(message.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
                let data = try Self.tail(stdout, limit: 4 * 1024 * 1024)
                if let text = String(data: data, encoding: .utf8) { progress(text) }
                return data
            }.value
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func tail(_ url: URL, limit: UInt64) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        try handle.seek(toOffset: end > limit ? end - limit : 0)
        return try handle.readToEnd() ?? Data()
    }
}
