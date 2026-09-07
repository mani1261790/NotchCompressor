import Foundation

public enum CompressionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case video, both, audio
    public var id: String { rawValue }
    public var title: String {
        switch self { case .video: "画質のみ"; case .both: "画質＋音質"; case .audio: "音質のみ" }
    }
    public var symbol: String {
        switch self { case .video: "video"; case .both: "arrow.down.right.and.arrow.up.left"; case .audio: "waveform" }
    }
    public var changesVideo: Bool { self != .audio }
    public var changesAudio: Bool { self != .video }
}

public enum CompressionQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case gentle, balanced, compact
    public var id: String { rawValue }
    public var title: String {
        switch self { case .gentle: "画質優先"; case .balanced: "標準"; case .compact: "容量優先" }
    }
    public var audioBitrate: Int {
        switch self { case .gentle: 128_000; case .balanced: 96_000; case .compact: 64_000 }
    }
    var bitsPerPixel: Double {
        switch self { case .gentle: 0.09; case .balanced: 0.06; case .compact: 0.035 }
    }
    var sourceRatio: Double {
        switch self { case .gentle: 0.85; case .balanced: 0.65; case .compact: 0.45 }
    }
}

public struct CompressionSettings: Codable, Equatable, Sendable {
    public var quality: CompressionQuality
    public var toolsDirectory: String?
    public init(quality: CompressionQuality = .balanced, toolsDirectory: String? = nil) {
        self.quality = quality
        self.toolsDirectory = toolsDirectory
    }
}

public enum CompressionError: LocalizedError, Equatable {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

public struct CompressionPlan: Sendable {
    public let media: MediaInfo
    public let mode: CompressionMode
    public let quality: CompressionQuality
    public let videoBitrate: Int
    public var note: String? {
        mode == .both && media.audio == nil ? "音声がないため、映像のみ圧縮します。" : nil
    }

    public init(media: MediaInfo, mode: CompressionMode, quality: CompressionQuality) throws {
        if mode == .audio && media.audio == nil {
            throw CompressionError.message("音声のない動画です。「画質のみ」を選んでください。")
        }
        if mode.changesVideo && !media.video.isSupportedSDR {
            throw CompressionError.message("この映像の色・ビット深度・透過には未対応です。映像を保持する「音質のみ」は利用できます。")
        }
        if mode.changesAudio, let audio = media.audio, !(1...2).contains(audio.channels ?? 0) {
            throw CompressionError.message("音声の圧縮はモノラル／ステレオに対応しています。「画質のみ」では元の音声を保持できます。")
        }
        self.media = media
        self.mode = mode
        self.quality = quality
        let pixelRate = Double(media.video.width ?? 0) * Double(media.video.height ?? 0) * min(media.video.fps, 30)
        let target = pixelRate * quality.bitsPerPixel
        let sourceCap = media.video.bitRate.map { Double($0) * quality.sourceRatio } ?? 12_000_000
        self.videoBitrate = Int(max(150_000, min(target, sourceCap, 12_000_000)))
    }

    public func arguments(input: URL, output: URL) -> [String] {
        var args = ["-nostdin", "-hide_banner", "-loglevel", "error", "-xerror", "-n",
                    "-progress", "pipe:1", "-nostats", "-protocol_whitelist", "file,pipe",
                    "-noautorotate", "-i", input.path, "-map", "0:v:0", "-map", "0:a?", "-map_metadata", "0", "-map_chapters", "0"]
        if mode.changesVideo {
            args += ["-c:v", "hevc_videotoolbox", "-allow_sw", "0", "-tag:v", "hvc1",
                     "-pix_fmt", "yuv420p", "-b:v", String(videoBitrate)]
            if media.video.fps > 30.1 { args += ["-vf", "fps=30"] }
        } else {
            args += ["-c:v", "copy"]
        }
        if mode.changesAudio && media.audio != nil {
            let bitrate = min(quality.audioBitrate, media.audio?.bitRate ?? quality.audioBitrate)
            args += ["-c:a", "aac", "-b:a", String(max(32_000, bitrate))]
        } else {
            args += ["-c:a", "copy"]
        }
        args += ["-movflags", "+faststart", "-f", "mov", output.path]
        return args
    }
}
