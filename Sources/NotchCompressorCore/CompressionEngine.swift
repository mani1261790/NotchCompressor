import Foundation
import Darwin

public enum JobPhase: String, Codable, Sendable {
    case waiting, probing, encoding, validating, completed, failed, cancelled, interrupted
    public var title: String {
        switch self {
        case .waiting: "待機中"; case .probing: "動画を確認中"; case .encoding: "圧縮中"; case .validating: "出力を検証中"
        case .completed: "完了"; case .failed: "失敗"; case .cancelled: "キャンセル済み"; case .interrupted: "前回の処理が中断"
        }
    }
    public var isFinished: Bool { [.completed, .failed, .cancelled, .interrupted].contains(self) }
}

public struct CompressionResult: Codable, Sendable {
    public let output: URL
    public let originalBytes: Int64
    public let outputBytes: Int64
    public let note: String?
    public var savedFraction: Double { 1 - Double(outputBytes) / Double(max(1, originalBytes)) }
}

private struct Fingerprint: Equatable {
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
        let data = try await runner.run(executable: tools.ffprobe,
            arguments: ["-v", "error", "-protocol_whitelist", "file,pipe", "-show_streams", "-show_format", "-of", "json", input.path], timeout: 30)
        return try MediaInfo.decode(data, fileSize: size)
    }

    public func compress(input: URL, mode: CompressionMode, settings: CompressionSettings,
                         update: @escaping @Sendable (JobPhase, Double, String?) -> Void = { _, _, _ in }) async throws -> CompressionResult {
        try Task.checkCancellation()
        update(.probing, 0, nil)
        let source = input.resolvingSymlinksInPath()
        let tools = try Toolchain.discover(directory: settings.toolsDirectory)
        _ = try InputFile.validate(source)
        let fingerprint = try Fingerprint(source)
        let media = try await probe(source, tools: tools)
        let plan = try CompressionPlan(media: media, mode: mode, quality: settings.quality)
        let folder = source.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            throw CompressionError.message("元ファイルのフォルダに書き込めません。書き込み可能なフォルダに動画を置いてください。")
        }
        let capacity = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        let estimated = max(Double(media.size), media.duration * Double(plan.videoBitrate + 256_000) / 8) * 1.2 + 64 * 1024 * 1024
        if let capacity, Double(capacity) < estimated {
            throw CompressionError.message("出力用の空き容量が不足しています。元ファイルを残したまま保存できる空きを確保してください。")
        }
        let staging = folder.appendingPathComponent(".notchcompressor-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: staging) }
        let output = staging.appendingPathComponent("output.mov")
        update(.encoding, 0, plan.note)
        _ = try await runner.run(executable: tools.ffmpeg, arguments: plan.arguments(input: source, output: output)) { text in
            if let value = text.split(separator: "\n").last(where: { $0.hasPrefix("out_time_us=") })?.split(separator: "=").last,
               let microseconds = Double(value), microseconds.isFinite {
                update(.encoding, min(0.99, max(0, microseconds / 1_000_000 / media.duration)), plan.note)
            }
        }
        try Task.checkCancellation()
        update(.validating, 0, plan.note)
        let resultMedia = try await probe(output, tools: tools)
        try Self.validateOutput(original: media, output: resultMedia, mode: mode)
        _ = try await runner.run(executable: tools.ffmpeg,
            arguments: ["-nostdin", "-v", "error", "-xerror", "-err_detect", "explode", "-protocol_whitelist", "file,pipe",
                        "-i", output.path, "-map", "0:v:0", "-map", "0:a?", "-f", "null", "-"],
            timeout: max(300, min(86_400, media.duration * 10)))
        try Task.checkCancellation()
        guard try Fingerprint(source) == fingerprint else {
            throw CompressionError.message("処理中に元ファイルが変更されたため、出力を確定しませんでした。もう一度お試しください。")
        }
        let destination = try Self.publish(output, beside: source, mode: mode)
        return CompressionResult(output: destination, originalBytes: media.size, outputBytes: resultMedia.size, note: plan.note)
    }

    static func validateOutput(original: MediaInfo, output: MediaInfo, mode: CompressionMode) throws {
        guard abs(original.duration - output.duration) <= max(0.25, 2 / min(original.video.fps, 30)),
              (original.audio == nil) == (output.audio == nil),
              original.video.width == output.video.width, original.video.height == output.video.height else {
            throw CompressionError.message("出力の長さ・映像サイズ・音声の検証に失敗しました。元ファイルは保持しています。")
        }
        if !mode.changesVideo && original.video.codecName != output.video.codecName {
            throw CompressionError.message("映像を保持できていないため、出力を確定しませんでした。")
        }
        if !mode.changesAudio && original.audio?.codecName != output.audio?.codecName {
            throw CompressionError.message("音声を保持できていないため、出力を確定しませんでした。")
        }
    }

    /// Exclusive rename on the same volume publishes atomically without replacing an existing name.
    static func publish(_ staged: URL, beside input: URL, mode: CompressionMode) throws -> URL {
        let folder = input.deletingLastPathComponent()
        var sourceStem = input.deletingPathExtension().lastPathComponent
        while sourceStem.utf8.count > 180 { sourceStem.removeLast() }
        let stem = sourceStem + "-compressed-" + mode.rawValue
        for number in 0..<10_000 {
            let suffix = number == 0 ? "" : "-\(number)"
            let target = folder.appendingPathComponent(stem + suffix + ".mov")
            let result = staged.path.withCString { source in target.path.withCString { destination in renamex_np(source, destination, UInt32(RENAME_EXCL)) } }
            if result == 0 { return target }
            if errno != EEXIST { throw CompressionError.message("出力を保存できませんでした: \(String(cString: strerror(errno)))") }
        }
        throw CompressionError.message("同名の出力が多すぎます。保存先を整理してください。")
    }
}
