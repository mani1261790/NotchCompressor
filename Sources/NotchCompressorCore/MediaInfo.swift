import Foundation

public struct MediaStream: Decodable, Sendable {
    public let index: Int
    public let codecType: String
    public let codecName: String?
    public let width: Int?
    public let height: Int?
    public let channels: Int?
    public let pixelFormat: String?
    public let colorTransfer: String?
    public let colorPrimaries: String?
    public let rawBits: String?
    public let averageFrameRate: String?
    private let bitRateString: String?
    public let disposition: [String: Int]?
    enum CodingKeys: String, CodingKey {
        case index, width, height, channels, disposition
        case codecType = "codec_type", codecName = "codec_name", pixelFormat = "pix_fmt"
        case colorTransfer = "color_transfer", colorPrimaries = "color_primaries"
        case rawBits = "bits_per_raw_sample", averageFrameRate = "avg_frame_rate", bitRateString = "bit_rate"
    }
    public var bitRate: Int? { bitRateString.flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil } }
    public var fps: Double {
        let parts = (averageFrameRate ?? "").split(separator: "/").compactMap { Double($0) }
        if parts.count == 2, parts[1] > 0, (parts[0] / parts[1]).isFinite, parts[0] > 0 { return parts[0] / parts[1] }
        return 30
    }
    public var isSupportedSDR: Bool {
        let accepted = ["yuv420p", "yuvj420p", "nv12", "yuv422p", "yuvj422p", "yuv444p", "yuvj444p"]
        let transferOK = colorTransfer == nil || ["unknown", "bt709", "smpte170m", "bt470m", "bt470bg", "gamma22", "gamma28", "iec61966-2-1"].contains(colorTransfer!)
        return accepted.contains(pixelFormat ?? "") && transferOK && colorPrimaries != "bt2020" && (Int(rawBits ?? "8") ?? 8) <= 8
    }
}

public struct MediaInfo: Sendable {
    public let video: MediaStream
    public let audio: MediaStream?
    public let duration: Double
    public let size: Int64

    public static func decode(_ data: Data, fileSize: Int64) throws -> MediaInfo {
        struct Report: Decodable {
            struct Format: Decodable { let duration: String?; let format_name: String? }
            let streams: [MediaStream]
            let format: Format
        }
        let report: Report
        do { report = try JSONDecoder().decode(Report.self, from: data) }
        catch { throw CompressionError.message("動画情報を読み取れませんでした。ファイルが破損していないか確認してください。") }
        guard let duration = report.format.duration.flatMap(Double.init), duration.isFinite, duration > 0,
              fileSize > 0, (report.format.format_name ?? "").split(separator: ",").contains("mov") else {
            throw CompressionError.message("有効なMOV／MP4動画として読み取れませんでした。")
        }
        let videos = report.streams.filter { $0.codecType == "video" }
        let audios = report.streams.filter { $0.codecType == "audio" }
        guard videos.count == 1, audios.count <= 1,
              !report.streams.contains(where: { !["video", "audio"].contains($0.codecType) }),
              let video = videos.first, video.disposition?["attached_pic"] != 1 else {
            throw CompressionError.message("動画1トラック・音声0〜1トラックに対応しています。字幕や追加トラックを含む動画は処理できません。")
        }
        guard let width = video.width, let height = video.height, width > 0, height > 0,
              width <= 32_768, height <= 32_768 else {
            throw CompressionError.message("映像サイズを正しく読み取れませんでした。")
        }
        return MediaInfo(video: video, audio: audios.first, duration: duration, size: fileSize)
    }
}

public struct Toolchain: Equatable, Sendable {
    public let ffmpeg: URL
    public let ffprobe: URL
    public init(directory: URL) throws {
        ffmpeg = directory.appendingPathComponent("ffmpeg")
        ffprobe = directory.appendingPathComponent("ffprobe")
        guard FileManager.default.isExecutableFile(atPath: ffmpeg.path), FileManager.default.isExecutableFile(atPath: ffprobe.path) else {
            throw CompressionError.message("ffmpegとffprobeが必要です。設定で両方が入ったフォルダを選択してください。")
        }
    }
    public static func discover(directory: String? = nil) throws -> Toolchain {
        if let directory, !directory.isEmpty { return try Toolchain(directory: URL(fileURLWithPath: directory)) }
        for path in ["/opt/homebrew/bin", "/usr/local/bin"] {
            if let tools = try? Toolchain(directory: URL(fileURLWithPath: path)) { return tools }
        }
        throw CompressionError.message("ffmpegとffprobeが見つかりません。設定で保存場所を指定してください。")
    }
}

public enum InputFile {
    public static func validate(_ url: URL) throws -> Int64 {
        guard url.isFileURL, ["mov", "mp4", "m4v"].contains(url.pathExtension.lowercased()) else {
            throw CompressionError.message("MOV／MP4／M4Vファイルを選択してください。")
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        guard values.isRegularFile == true else { throw CompressionError.message("通常の動画ファイルを選択してください。フォルダには対応していません。") }
        if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus != .current {
            throw CompressionError.message("iCloud上の動画です。Finderで「今すぐダウンロード」してから再度ドロップしてください。")
        }
        guard FileManager.default.isReadableFile(atPath: url.path), let size = values.fileSize, size > 0 else {
            throw CompressionError.message("動画を読み取れません。権限とダウンロード状態を確認してください。")
        }
        return Int64(size)
    }
}
