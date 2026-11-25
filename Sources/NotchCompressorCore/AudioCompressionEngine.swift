import Foundation

struct AudioCompressionEngine {
    private let runner = ProcessRunner()
    func probe(_ url: URL, tools: Toolchain) async throws -> AudioMediaInfo {
        let data = try await runner.run(
            executable: tools.ffprobe,
            arguments: [
                "-v", "error", "-protocol_whitelist", "file,pipe", "-show_streams", "-show_format", "-show_chapters",
                "-of", "json", url.path,
            ], timeout: 30)
        return try AudioMediaInfo.decode(data)
    }

    func compress(
        input: URL, mode: CompressionMode, settings: CompressionSettings,
        update: @escaping @Sendable (JobPhase, Double, String?) -> Void
    ) async throws -> CompressionResult {
        guard MediaKind.audio.accepts(mode) else {
            throw CompressionError.localized(.init("error.mediaMode", MediaKind.audio.title))
        }
        let size = try InputFile.validate(input, extensions: ["m4a"])
        let fingerprint = try Fingerprint(input)
        let tools = try Toolchain.discover(directory: settings.toolsDirectory)
        let media = try await probe(input, tools: tools)
        try await CompressionControl.current?.checkpoint()
        let requested = settings.effectiveStandaloneAudioKbps * 1000 * (media.audio.channels == 1 ? 1 : 2) / 2
        let bitrate = min(requested, media.bitRate ?? requested)
        let estimate = max(Double(size), media.duration * Double(bitrate) / 8) * 1.2 + 64 * 1024 * 1024
        let transaction = try OutputTransaction(source: input, estimatedBytes: estimate, expected: fingerprint)
        defer { transaction.cleanUp() }
        try await CompressionEngine.recoverAfterSleep(control: CompressionControl.current) { retrying in
            guard try Fingerprint(input) == fingerprint else {
                throw CompressionError.localized(.init("error.changedRetry"))
            }
            if FileManager.default.fileExists(atPath: transaction.output.path) {
                try FileManager.default.removeItem(at: transaction.output)
            }
            let note = retrying ? L10n.text("note.sleepRetry") : nil
            update(.encoding, 0, note)
            let args = [
                "-nostdin", "-v", "error", "-xerror", "-protocol_whitelist", "file,pipe", "-i", input.path,
                "-map", "0", "-map_metadata", "0", "-map_chapters", "0", "-c", "copy", "-c:a", "aac",
                "-b:a", String(bitrate), "-ar", String(media.sampleRate), "-movflags", "+faststart",
                "-progress", "pipe:1", "-nostats", "-n", transaction.output.path,
            ]
            _ = try await runner.run(executable: tools.ffmpeg, arguments: args) { text in
                if let value = text.split(separator: "\n").last(where: { $0.hasPrefix("out_time_us=") })?.split(
                    separator: "="
                ).last,
                    let microseconds = Double(value), microseconds.isFinite
                {
                    update(.encoding, min(0.99, max(0, microseconds / 1_000_000 / media.duration)), note)
                }
            }
            try await CompressionControl.current?.checkpoint()
            update(.validating, 0, note)
            let output = try await probe(transaction.output, tools: tools)
            try media.validate(output)
            if !media.covers.isEmpty {
                let original = try await coverHashes(input, tools: tools)
                let candidate = try await coverHashes(transaction.output, tools: tools)
                guard !original.isEmpty, original == candidate else {
                    throw CompressionError.localized(.init("error.audioPreservation"))
                }
            }
            _ = try await runner.run(
                executable: tools.ffmpeg,
                arguments: [
                    "-nostdin", "-v", "error", "-xerror", "-err_detect", "explode", "-protocol_whitelist", "file,pipe",
                    "-i", transaction.output.path,
                    "-map", "0:a:0", "-f", "null", "-",
                ], timeout: max(300, min(86_400, media.duration * 10)))
        }
        return try await transaction.commit()
    }

    private func coverHashes(_ url: URL, tools: Toolchain) async throws -> [String] {
        struct Packets: Decodable { struct Packet: Decodable { let data_hash: String }; let packets: [Packet] }
        let data = try await runner.run(
            executable: tools.ffprobe,
            arguments: [
                "-v", "error", "-protocol_whitelist", "file,pipe", "-select_streams", "v", "-show_packets",
                "-show_data_hash", "sha256", "-show_entries", "packet=data_hash", "-of", "json", url.path,
            ], timeout: 30)
        return try JSONDecoder().decode(Packets.self, from: data).packets.map(\.data_hash)
    }
}
