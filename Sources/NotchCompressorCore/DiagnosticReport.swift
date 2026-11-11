import Foundation

public enum DiagnosticReport {
    /// Build from an allowlist. Never serialize a job, URL, result note, or error message.
    public static func make(version: String, build: String, os: OperatingSystemVersion,
                            jobs: [CompressionJob], persistenceFailed: Bool, engineAvailable: Bool) -> String {
        var lines = [
            "NotchCompressor 診断情報 v1",
            "アプリ: \(version) (\(build))",
            "macOS: \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "圧縮エンジン: \(engineAvailable ? "利用可能" : "検出できません")",
            "履歴保存: \(persistenceFailed ? "エラーあり" : "エラーなし")",
            "",
            "キューの状態（保持中の履歴を含む）"
        ]
        for phase in [JobPhase.waiting, .probing, .encoding, .validating, .paused, .completed, .failed, .cancelled, .interrupted] {
            lines.append("\(phase.title): \(jobs.filter { $0.phase == phase }.count)件")
        }
        let failed = jobs.filter { $0.phase == .failed }
        if !failed.isEmpty {
            lines.append("\nエラー分類: compression_failed（詳しい原因は含めません）")
            for mode in CompressionMode.allCases {
                lines.append("\(mode.title): \(failed.filter { $0.mode == mode }.count)件")
            }
        }
        lines.append("\n動画名・パス・動画の内容・生ログは含めていません。自動送信は行いません。")
        return lines.joined(separator: "\n")
    }
}
