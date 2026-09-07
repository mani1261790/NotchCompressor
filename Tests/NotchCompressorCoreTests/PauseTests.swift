import XCTest
@testable import NotchCompressorCore

private final class ProgressCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    func update(_ value: String) { lock.withLock { text = value } }
    var value: String { lock.withLock { text } }
}

final class PauseTests: XCTestCase {
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for process output")
    }

    func testSameProcessResumesAndPausedTimeDoesNotConsumeTimeout() async throws {
        let control = CompressionControl(), output = ProgressCapture()
        let task = Task {
            try await CompressionControl.$current.withValue(control) {
                try await ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "echo $$; i=0; while [ $i -lt 15 ]; do echo $i; i=$((i+1)); sleep 0.1; done"],
                    timeout: 3, progress: { output.update($0) })
            }
        }
        try await waitFor { output.value.split(separator: "\n").count >= 3 }
        XCTAssertTrue(control.pause())
        XCTAssertTrue(control.pause(), "Repeated pause must not require two resumes")
        try await Task.sleep(for: .milliseconds(200))
        let held = output.value
        try await Task.sleep(for: .seconds(3.2))
        XCTAssertEqual(output.value, held)
        XCTAssertTrue(control.resume())
        let data = try await task.value
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, held.split(separator: "\n").first.map(String.init))
        XCTAssertEqual(Array(lines.dropFirst()), (0..<15).map(String.init), "Continue the same process without restarting or skipping output")
    }

    func testCancelSuspendedProcessExitsAndCommitCannotBePaused() async throws {
        let control = CompressionControl(), output = ProgressCapture()
        let task = Task {
            try await CompressionControl.$current.withValue(control) {
                try await ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "echo ready; exec /bin/sleep 60"], progress: { output.update($0) })
            }
        }
        try await waitFor { output.value.contains("ready") }
        XCTAssertTrue(control.pause())
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let commit = CompressionControl()
        XCTAssertTrue(commit.pause())
        XCTAssertNil(commit.commit { 42 })
        XCTAssertTrue(commit.resume())
        XCTAssertEqual(commit.commit { 42 }, 42)
        XCTAssertFalse(commit.pause(), "Do not report paused after the source was replaced")
    }
}
