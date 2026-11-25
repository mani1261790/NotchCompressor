import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum MediaKind: String, Codable, Sendable, CaseIterable {
    case video, image, audio

    public func accepts(_ mode: CompressionMode) -> Bool {
        switch self {
        case .video: true
        case .image: mode != .audio
        case .audio: mode != .video
        }
    }

    public var title: String {
        switch self {
        case .video: L10n.text("media.video")
        case .image: L10n.text("media.image")
        case .audio: L10n.text("media.audio")
        }
    }
}

/// This context pins the inspected kind during execution without changing the
/// injected operation interface used by queue clients and tests.
public enum MediaInputContext {
    @TaskLocal public static var expectedKind: MediaKind?
}

public struct InspectedInput: Sendable {
    public let url: URL
    public let kind: MediaKind
    public let bytes: Int64
}

public struct InputRejection: Sendable {
    public let url: URL
    public let reason: LocalizedMessage
}

public struct InputBatch: Sendable {
    public var accepted: [InspectedInput] = []
    public var rejected: [InputRejection] = []

    /// Preserve drop order, avoid blocking the UI, and report each unsupported
    /// input independently. Callers can enqueue each accepted input immediately
    /// without waiting for the rest of a large batch.
    public static func inspect(
        _ urls: [URL], mode: CompressionMode, toolsDirectory: String? = nil,
        enabledKinds: Set<MediaKind> = [.video],
        onAccepted: (@Sendable (InspectedInput) async -> Void)? = nil
    ) async throws -> Self {
        var batch = Self()
        var seen = Set<URL>()
        for url in urls {
            try Task.checkCancellation()
            do {
                let input = try await MediaInputInspector.inspect(url, toolsDirectory: toolsDirectory)
                guard seen.insert(input.url).inserted else { continue }
                guard input.kind.accepts(mode) else {
                    throw CompressionError.localized(.init("error.mediaMode", input.kind.title))
                }
                guard enabledKinds.contains(input.kind) else {
                    throw CompressionError.localized(.init("error.mediaUnavailable", input.kind.title))
                }
                if input.kind == .image, !["jpg", "jpeg", "png"].contains(input.url.pathExtension.lowercased()) {
                    throw CompressionError.localized(.init("error.imageFormat"))
                }
                batch.accepted.append(input)
                await onAccepted?(input)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                batch.rejected.append(
                    .init(
                        url: url, reason: (error as? CompressionError)?.localizedMessage ?? .init("error.read")))
            }
        }
        return batch
    }
}

public enum MediaInputInspector {
    public static let candidateExtensions = ["mov", "mp4", "m4v", "jpg", "jpeg", "png", "heic", "heif", "m4a"]

    public static func inspect(_ url: URL, toolsDirectory: String? = nil) async throws -> InspectedInput {
        // Validate cloud availability before opening any bytes or resolving input.
        let size = try InputFile.validate(url, extensions: candidateExtensions)
        let source = url.standardizedFileURL.resolvingSymlinksInPath()
        let ext = source.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "heic", "heif"].contains(ext) {
            guard size <= 128 * 1024 * 1024 else { throw CompressionError.localized(.init("error.imageTooLarge")) }
            return try await Task.detached(priority: .utility) {
                guard let image = CGImageSourceCreateWithURL(source as CFURL, nil),
                    let type = CGImageSourceGetType(image) as String?,
                    let expected = UTType(filenameExtension: ext), type == expected.identifier,
                    CGImageSourceGetCount(image) > 0
                else { throw CompressionError.localized(.init("error.mediaMismatch")) }
                return InspectedInput(url: source, kind: .image, bytes: size)
            }.value
        }
        let tools = try Toolchain.discover(directory: toolsDirectory)
        let data = try await ProcessRunner().run(
            executable: tools.ffprobe,
            arguments: [
                "-v", "error", "-protocol_whitelist", "file,pipe", "-show_streams", "-show_format", "-of", "json",
                source.path,
            ],
            timeout: 30)
        let kind = try classifyProbe(data, extension: ext)
        return InspectedInput(url: source, kind: kind, bytes: size)
    }

    static func classifyProbe(_ data: Data, extension ext: String) throws -> MediaKind {
        struct Report: Decodable {
            struct Format: Decodable { let format_name: String?; let duration: String? }
            let streams: [MediaStream]
            let format: Format
        }
        guard let report = try? JSONDecoder().decode(Report.self, from: data),
            (report.format.format_name ?? "").split(separator: ",").contains("mov"),
            let duration = report.format.duration.flatMap(Double.init), duration.isFinite, duration > 0
        else { throw CompressionError.localized(.init("error.mediaMismatch")) }
        let movingVideo = report.streams.contains { $0.codecType == "video" && $0.disposition?["attached_pic"] != 1 }
        if movingVideo {
            guard ["mov", "mp4", "m4v"].contains(ext) else {
                throw CompressionError.localized(.init("error.mediaMismatch"))
            }
            // Retain the existing strict track/color-independent video contract.
            _ = try MediaInfo.decode(data, fileSize: 1)
            return .video
        }
        guard ext == "m4a", report.streams.contains(where: { $0.codecType == "audio" }) else {
            throw CompressionError.localized(.init("error.mediaMismatch"))
        }
        _ = try AudioMediaInfo.decode(data)
        return .audio
    }
}
