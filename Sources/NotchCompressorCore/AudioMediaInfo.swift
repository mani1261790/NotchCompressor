import Foundation

struct AudioMediaInfo: Sendable {
    struct Stream: Decodable, Sendable {
        let index: Int
        let codec_type: String
        let codec_name: String?
        let sample_rate: String?
        let channels: Int?
        let channel_layout: String?
        let bit_rate: String?
        let start_time: String?
        let disposition: [String: Int]?
        let tags: [String: String]?
    }
    struct Format: Decodable, Sendable {
        let format_name: String?
        let duration: String?
        let start_time: String?
        let tags: [String: String]?
    }
    struct Chapter: Codable, Equatable, Sendable {
        let start_time: String
        let end_time: String
        let tags: [String: String]?
    }
    let audio: Stream
    let covers: [Stream]
    let duration: Double
    let sampleRate: Int
    let tags: [String: String]
    let chapters: [Chapter]
    var bitRate: Int? { audio.bit_rate.flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil } }

    static func decode(_ data: Data) throws -> Self {
        struct Report: Decodable { let streams: [Stream]; let format: Format; let chapters: [Chapter]? }
        guard let report = try? JSONDecoder().decode(Report.self, from: data),
            (report.format.format_name ?? "").split(separator: ",").contains("mov"),
            let duration = report.format.duration.flatMap(Double.init), duration.isFinite, duration > 0
        else { throw CompressionError.localized(.init("error.mediaMismatch")) }
        let audio = report.streams.filter { $0.codec_type == "audio" }
        let covers = report.streams.filter { $0.codec_type == "video" && $0.disposition?["attached_pic"] == 1 }
        guard audio.count == 1, let track = audio.first, track.codec_name == "aac",
            report.streams.count == audio.count + covers.count, covers.count <= 1,
            covers.allSatisfy({ ["mjpeg", "png"].contains($0.codec_name ?? "") }),
            let channels = track.channels, (1...2).contains(channels),
            let rate = track.sample_rate.flatMap(Int.init),
            [8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000, 64000, 88200, 96000].contains(rate),
            abs(Double(track.start_time ?? "0") ?? .infinity) <= 1 / Double(rate),
            abs(Double(report.format.start_time ?? "0") ?? .infinity) <= 1 / Double(rate)
        else { throw CompressionError.localized(.init("error.audioStructure")) }
        return .init(
            audio: track, covers: covers, duration: duration, sampleRate: rate,
            tags: report.format.tags ?? [:], chapters: report.chapters ?? [])
    }

    func validate(_ output: Self) throws {
        let generated = Set(["major_brand", "minor_version", "compatible_brands", "encoder"])
        let preserved = tags.filter { !generated.contains($0.key.lowercased()) }
        guard abs(duration - output.duration) <= max(0.05, 2048 / Double(sampleRate)),
            sampleRate == output.sampleRate, audio.channels == output.audio.channels,
            audio.channel_layout == output.audio.channel_layout,
            covers.count == output.covers.count, chapters == output.chapters,
            preserved.allSatisfy({ output.tags[$0.key] == $0.value })
        else { throw CompressionError.localized(.init("error.audioPreservation")) }
        for (key, value) in audio.tags ?? [:] where !["encoder", "vendor_id"].contains(key.lowercased()) {
            guard output.audio.tags?[key] == value else {
                throw CompressionError.localized(.init("error.audioPreservation"))
            }
        }
    }
}
