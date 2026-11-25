import Foundation
import CoreGraphics

/// Reserve the camera cutout between independent left/right information areas.
public struct NotchWidgetGeometry: Equatable {
    public let frame: CGRect
    public let cameraWidth: CGFloat
    public let sideWidth: CGFloat
    public init(screen: CGRect, topInset: CGFloat, notchWidth: CGFloat) {
        cameraWidth = topInset > 0 ? min(max(0, notchWidth), screen.width) : 0
        sideWidth = min(150, max(0, (screen.width - cameraWidth) / 2))
        let height = max(28, topInset)
        let gap: CGFloat = topInset > 0 ? 0 : 8
        frame = CGRect(
            x: screen.midX - (cameraWidth + 2 * sideWidth) / 2,
            y: screen.maxY - gap - height, width: cameraWidth + 2 * sideWidth, height: height)
    }
}

public struct NowPlayingTrack: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let playing: Bool
    public init(title: String, artist: String, playing: Bool) {
        self.title = title; self.artist = artist; self.playing = playing
    }
}

/// Debounce entry and tolerate briefly crossing the expanded panel boundary.
public struct NotchHoverState {
    public private(set) var expanded = false
    private var enteredAt: TimeInterval?
    private var exitedAt: TimeInterval?
    public init() {}
    public mutating func reset() { expanded = false; enteredAt = nil; exitedAt = nil }
    public mutating func update(insideTrigger: Bool, insidePanel: Bool, now: TimeInterval) {
        if expanded {
            if insideTrigger || insidePanel {
                exitedAt = nil
            } else {
                if exitedAt == nil { exitedAt = now }
                if now - (exitedAt ?? now) >= 0.25 { reset() }
            }
        } else if insideTrigger {
            if enteredAt == nil { enteredAt = now }
            if now - (enteredAt ?? now) >= 0.18 { expanded = true; exitedAt = nil }
        } else {
            enteredAt = nil
        }
    }
}
