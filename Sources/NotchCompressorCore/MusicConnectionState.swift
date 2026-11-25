import Foundation

public enum MusicConnectionState: String, Equatable, Sendable {
    case checking, permissionNeeded, denied, closed, ready, playing, paused, unavailable
    public init(checking: Bool, playing: Bool?, statusKey: String?) {
        if checking { self = .checking; return }
        switch statusKey {
        case "widgets.openMusic": self = .closed
        case "widgets.permissionNeeded": self = .permissionNeeded
        case "widgets.musicPermission": self = .denied
        case "widgets.noTrack": self = .ready
        case "widgets.musicUnavailable": self = .unavailable
        default:
            if let playing { self = playing ? .playing : .paused } else { self = .checking }
        }
    }
    public var connected: Bool { [.ready, .playing, .paused].contains(self) }
    public var title: String {
        switch self {
        case .checking: L10n.text("music.checking")
        case .permissionNeeded: L10n.text("music.permissionNeeded")
        case .denied: L10n.text("music.denied")
        case .closed: L10n.text("music.closed")
        case .ready: L10n.text("music.ready")
        case .playing: L10n.text("music.playing")
        case .paused: L10n.text("music.paused")
        case .unavailable: L10n.text("widgets.musicUnavailable")
        }
    }
}
