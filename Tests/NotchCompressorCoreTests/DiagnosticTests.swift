import XCTest
@testable import NotchCompressorCore

final class DiagnosticTests: XCTestCase {
    func testReportExcludesAllUserContentAndRawErrors() {
        let secret = "sensitive-project-and-person"
        var job = CompressionJob(
            input: URL(fileURLWithPath: "/Users/private/\(secret).mov"), mode: .both, settings: .init())
        job.phase = .failed
        job.message = "ffmpeg raw stderr: \(secret)"
        job.result = .init(output: job.input, originalBytes: 999, outputBytes: 500, note: secret)
        let report = DiagnosticReport.make(
            version: "0.1.0", build: "2",
            os: .init(majorVersion: 26, minorVersion: 1, patchVersion: 0),
            jobs: [job], persistenceFailed: true, engineAvailable: false)
        for forbidden in [secret, "/Users", ".mov", "stderr", job.id.uuidString, "999"] {
            XCTAssertFalse(report.contains(forbidden), forbidden)
        }
        XCTAssertTrue(report.contains("compression_failed"))
        XCTAssertTrue(report.contains("失敗: 1件"))
        XCTAssertTrue(report.contains("履歴保存: エラーあり"))
        XCTAssertTrue(report.contains("macOS: 26.1.0"))
    }
}
