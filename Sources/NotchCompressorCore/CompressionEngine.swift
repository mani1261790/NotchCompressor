import Foundation

public enum JobPhase: String, Codable, Sendable {
    case waiting, probing, encoding, validating, paused, completed, failed, cancelled, interrupted
    public var title: String {
        switch self {
        case .paused: L10n.text("phase.paused");
        case .waiting: L10n.text("phase.waiting");
        case .probing: L10n.text("phase.probing");
        case .encoding: L10n.text("phase.encoding");
        case .validating: L10n.text("phase.validating")
        case .completed: L10n.text("phase.completed");
        case .failed: L10n.text("phase.failed");
        case .cancelled: L10n.text("phase.cancelled");
        case .interrupted: L10n.text("phase.interrupted")
        }
    }
    public var isFinished: Bool { [.completed, .failed, .cancelled, .interrupted].contains(self) }
}

public enum CompressionOutcome: String, Codable, Sendable {
    case replaced, originalKept
}

public struct CompressionResult: Codable, Sendable {
    public let output: URL
    public let originalBytes: Int64
    public let outputBytes: Int64
    public let note: String?
    public let noteMessage: LocalizedMessage?
    public let outcome: CompressionOutcome?
    public let candidateBytes: Int64?
    public var effectiveOutcome: CompressionOutcome { outcome ?? .replaced }
    public var completionMessage: String? {
        effectiveOutcome == .originalKept
            ? L10n.text("result.originalKept") : noteMessage?.text ?? (note == nil ? nil : L10n.text("history.legacy"))
    }
    public init(
        output: URL, originalBytes: Int64, outputBytes: Int64, note: String?,
        outcome: CompressionOutcome? = nil, candidateBytes: Int64? = nil, noteMessage: LocalizedMessage? = nil
    ) {
        self.output = output
        self.originalBytes = originalBytes
        self.outputBytes = outputBytes
        self.note = noteMessage == nil ? note : nil
        self.noteMessage = noteMessage
        self.outcome = outcome
        self.candidateBytes = candidateBytes
    }
    public var savedFraction: Double { 1 - Double(outputBytes) / Double(max(1, originalBytes)) }
}

struct Fingerprint: Equatable {
    let size: UInt64
    let modified: Date
    let inode: UInt64
    init(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        modified = attributes[.modificationDate] as? Date ?? .distantPast
        inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
    }
}

public struct CompressionEngine: Sendable {
    private let runner = ProcessRunner()
    public init() {}

    public func probe(_ input: URL, tools: Toolchain) async throws -> MediaInfo {
        let size = try InputFile.validate(input)
        let data = try await runner.run(
            executable: tools.ffprobe,
            arguments: [
                "-v", "error", "-protocol_whitelist", "file,pipe", "-show_streams", "-show_format", "-of", "json",
                input.path,
            ], timeout: 30)
        return try MediaInfo.decode(data, fileSize: size)
    }

    public func compress(
        input: URL, mode: CompressionMode, settings: CompressionSettings,
        update: @escaping @Sendable (JobPhase, Double, String?) -> Void = { _, _, _ in }
    ) async throws -> CompressionResult {
        try await CompressionControl.current?.checkpoint()
        try Task.checkCancellation()
        update(.probing, 0, nil)
        let source = input.resolvingSymlinksInPath()
        let tools = try Toolchain.discover(directory: settings.toolsDirectory)
        _ = try InputFile.validate(source)
        let fingerprint = try Fingerprint(source)
        let media = try await probe(source, tools: tools)
        try await CompressionControl.current?.checkpoint()
        let plan = try CompressionPlan(media: media, mode: mode, settings: settings)
        let folder = source.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            throw CompressionError.localized(.init("error.folder"))
        }
        let capacity = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        let estimated =
            max(Double(media.size), media.duration * Double(plan.videoBitrate + 256_000) / 8) * 1.2 + 64 * 1024 * 1024
        if let capacity, Double(capacity) < estimated {
            throw DiskSpaceIssue(
                availableBytes: max(0, capacity),
                requiredBytes: Int64(min(estimated.rounded(.up), Double(Int64.max - 1024))))
        }
        let staging = folder.appendingPathComponent(".notchcompressor-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: staging) }
        let output = staging.appendingPathComponent("output." + source.pathExtension.lowercased())
        try await Self.recoverAfterSleep(control: CompressionControl.current) { retrying in
            guard try Fingerprint(source) == fingerprint else {
                throw CompressionError.localized(.init("error.changedRetry"))
            }
            if FileManager.default.fileExists(atPath: output.path) {
                try FileManager.default.removeItem(at: output)
            }
            let attemptNote = retrying ? L10n.text("note.sleepRetry") : plan.note
            update(.encoding, 0, attemptNote)
            _ = try await runner.run(executable: tools.ffmpeg, arguments: plan.arguments(input: source, output: output))
            {
                text in
                if let value = text.split(separator: "\n").last(where: { $0.hasPrefix("out_time_us=") })?.split(
                    separator: "="
                ).last,
                    let microseconds = Double(value), microseconds.isFinite
                {
                    update(.encoding, min(0.99, max(0, microseconds / 1_000_000 / media.duration)), attemptNote)
                }
            }
            try Task.checkCancellation()
            try await CompressionControl.current?.checkpoint()
            update(.validating, 0, attemptNote)
            let resultMedia = try await probe(output, tools: tools)
            try Self.validateOutput(original: media, output: resultMedia, mode: mode)
            _ = try await runner.run(
                executable: tools.ffmpeg,
                arguments: [
                    "-nostdin", "-v", "error", "-xerror", "-err_detect", "explode", "-protocol_whitelist", "file,pipe",
                    "-i", output.path, "-map", "0:v:0", "-map", "0:a?", "-f", "null", "-",
                ],
                timeout: max(300, min(86_400, media.duration * 10)))
        }
        try Task.checkCancellation()
        guard try Fingerprint(source) == fingerprint else {
            throw CompressionError.localized(.init("error.changedRetry"))
        }
        if let control = CompressionControl.current {
            while true {
                try await control.checkpoint()
                if let result = try control.commit({
                    try Self.finalizeVerifiedOutput(
                        output, original: source, expected: fingerprint, note: plan.note, noteMessage: plan.noteMessage)
                }) {
                    return result
                }
            }
        }
        return try Self.finalizeVerifiedOutput(
            output, original: source, expected: fingerprint, note: plan.note, noteMessage: plan.noteMessage)
    }

    /// Retry only the encode/validate stage, once, when it crossed a system sleep.
    /// Final replacement is deliberately outside this recovery boundary.
    static func recoverAfterSleep(
        control: CompressionControl?, operation: (Bool) async throws -> Void
    ) async throws {
        try await control?.checkpoint()
        let generation = control?.systemSleepGeneration
        do {
            try await operation(false)
        } catch {
            try Task.checkCancellation()
            guard let control, let generation,
                control.systemSleepGeneration != generation,
                let failure = error as? CompressionError,
                ["error.process", "error.validation", "error.timeout"].contains(failure.localizedMessage.key)
            else { throw error }
            // A user pause must survive recovery; cancellation must not start a new child.
            try await control.checkpoint()
            try await operation(true)
        }
    }

    /// Both outcomes pass the same cancellation and source-change checks under the commit lock.
    static func finalizeVerifiedOutput(
        _ staged: URL, original: URL, expected: Fingerprint,
        note: String?, noteMessage: LocalizedMessage? = nil
    ) throws -> CompressionResult {
        try Task.checkCancellation()
        guard try Fingerprint(original) == expected else {
            throw CompressionError.localized(.init("error.changed"))
        }
        let candidate = Int64(clamping: try Fingerprint(staged).size)
        let originalBytes = Int64(clamping: expected.size)
        let keep = candidate >= originalBytes
        if !keep { _ = try replaceOriginal(staged, original: original, expected: expected) }
        return CompressionResult(
            output: original, originalBytes: originalBytes,
            outputBytes: keep ? originalBytes : candidate, note: note,
            outcome: keep ? .originalKept : .replaced, candidateBytes: candidate, noteMessage: noteMessage)
    }

    static func validateOutput(original: MediaInfo, output: MediaInfo, mode: CompressionMode) throws {
        guard abs(original.duration - output.duration) <= max(0.25, 2 / min(original.video.fps, 30)),
            (original.audio == nil) == (output.audio == nil),
            original.video.width == output.video.width, original.video.height == output.video.height
        else {
            throw CompressionError.localized(.init("error.validation"))
        }
        if !mode.changesVideo && original.video.codecName != output.video.codecName {
            throw CompressionError.localized(.init("error.videoCopy"))
        }
        if !mode.changesAudio && original.audio?.codecName != output.audio?.codecName {
            throw CompressionError.localized(.init("error.audioCopy"))
        }
    }

    /// Validate immediately before the filesystem replacement. The original is never
    /// truncated or removed before the fully verified staged file is ready.
    static func replaceOriginal(_ staged: URL, original: URL, expected: Fingerprint) throws -> URL {
        try Task.checkCancellation()
        guard try Fingerprint(original) == expected else {
            throw CompressionError.localized(.init("error.changedReplace"))
        }
        do {
            _ = try FileManager.default.replaceItemAt(original, withItemAt: staged)
        } catch {
            throw CompressionError.localized(.init("error.replace"), details: error.localizedDescription)
        }
        return original
    }
}
