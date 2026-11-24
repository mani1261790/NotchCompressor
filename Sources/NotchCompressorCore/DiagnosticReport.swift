import Foundation

public enum DiagnosticReport {
    /// Build from an allowlist. Never serialize a job, URL, result note, or error message.
    public static func make(
        version: String, build: String, os: OperatingSystemVersion,
        jobs: [CompressionJob], persistenceFailed: Bool, engineAvailable: Bool
    ) -> String {
        var lines = [
            L10n.text("diagnostic.title"),
            L10n.text("diagnostic.app", version, build),
            "macOS: \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            L10n.text(
                "diagnostic.engine",
                engineAvailable ? L10n.text("diagnostic.available") : L10n.text("diagnostic.missing")),
            L10n.text(
                "diagnostic.storage",
                persistenceFailed ? L10n.text("diagnostic.error") : L10n.text("diagnostic.noError")),
            "",
            L10n.text("diagnostic.queue"),
        ]
        for phase in [
            JobPhase.waiting, .probing, .encoding, .validating, .paused, .completed, .failed, .cancelled, .interrupted,
        ] {
            lines.append(
                L10n.text("diagnostic.count", phase.title, L10n.integer(jobs.filter { $0.phase == phase }.count)))
        }
        let failed = jobs.filter { $0.phase == .failed }
        if !failed.isEmpty {
            lines.append("\n" + L10n.text("diagnostic.failure"))
            for mode in CompressionMode.allCases {
                lines.append(
                    L10n.text("diagnostic.count", mode.title, L10n.integer(failed.filter { $0.mode == mode }.count)))
            }
        }
        lines.append("\n" + L10n.text("diagnostic.privacy"))
        return lines.joined(separator: "\n")
    }
}
