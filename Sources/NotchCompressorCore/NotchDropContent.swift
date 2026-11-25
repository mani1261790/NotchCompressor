import Foundation

/// Presentation hints only. InputBatch still validates the actual file contents.
public enum NotchDropContent: String, Equatable, Sendable {
    case video, image, audio, automatic

    public init(urls: [URL]) {
        let kinds = Set(
            urls.map { url -> String in
                switch url.pathExtension.lowercased() {
                case "mov", "mp4", "m4v": return "video"
                case "jpg", "jpeg", "png": return "image"
                case "m4a": return "audio"
                default: return "automatic"
                }
            })
        self = kinds.count == 1 ? Self(rawValue: kinds.first!) ?? .automatic : .automatic
    }
    public var modes: [CompressionMode] { self == .video ? CompressionMode.allCases : [singleMode] }
    public var singleMode: CompressionMode { self == .image ? .video : self == .audio ? .audio : .both }
    public func mode(for geometricMode: CompressionMode?) -> CompressionMode? {
        guard let geometricMode else { return nil }
        return self == .video ? geometricMode : singleMode
    }
    public var title: String {
        switch self {
        case .video: return ""
        case .image: return L10n.text("notch.drop.image")
        case .audio: return L10n.text("notch.drop.audio")
        case .automatic: return L10n.text("notch.drop.automatic")
        }
    }
    public var hint: String {
        switch self {
        case .video: return ""
        case .image: return L10n.text("notch.drop.image.hint")
        case .audio: return L10n.text("notch.drop.audio.hint")
        case .automatic: return L10n.text("notch.drop.automatic.hint")
        }
    }
    public var symbol: String {
        switch self {
        case .video: return "video"
        case .image: return "photo"
        case .audio: return "waveform"
        case .automatic: return "square.stack"
        }
    }
}
