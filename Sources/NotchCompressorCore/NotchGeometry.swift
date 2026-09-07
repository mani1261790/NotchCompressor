import CoreGraphics
import Foundation

public struct FileDragState {
    private var changeCount: Int
    private var pendingDrag = false
    public private(set) var active = false
    public init(changeCount: Int) { self.changeCount = changeCount }
    public mutating func update(changeCount: Int, leftButtonDown: Bool, hasFiles: Bool) {
        if self.changeCount != changeCount {
            self.changeCount = changeCount
            // Providers may publish their file URLs after declaring a new drag.
            // Keep that generation eligible only until this mouse press ends.
            pendingDrag = leftButtonDown
            active = false
        }
        if !leftButtonDown { end() }
        else if pendingDrag && hasFiles { active = true }
    }
    public mutating func end() { active = false; pendingDrag = false }
}

/// Keeps the destination stable while AppKit delivers the mouse-up/drop callbacks.
public struct NativeDropSession {
    private var inside = false
    private var releasedAt: TimeInterval?
    public init() {}
    public mutating func entered() { inside = true; releasedAt = nil }
    public mutating func ended() { inside = false; releasedAt = nil }
    public mutating func holdsPanelOpen(leftButtonDown: Bool, now: TimeInterval) -> Bool {
        guard inside else { return false }
        if leftButtonDown { releasedAt = nil; return true }
        if releasedAt == nil { releasedAt = now }
        // A missing callback (e.g. cancellation) must not leave the panel expanded.
        if now - (releasedAt ?? now) < 0.35 { return true }
        ended()
        return false
    }
}

public struct NotchGeometry {
    public let collapsed: CGRect
    public let panel: CGRect
    public let trigger: CGRect
    public let topInset: CGFloat
    public init(screen: CGRect, topInset: CGFloat, notchWidth: CGFloat = 180) {
        self.topInset = max(0, topInset)
        let compactWidth = min(max(1, notchWidth), screen.width)
        let compactHeight = self.topInset > 0 ? self.topInset : 28
        collapsed = CGRect(x: screen.midX - compactWidth / 2, y: screen.maxY - compactHeight,
                           width: compactWidth, height: compactHeight)
        let width = min(480, screen.width)
        let height = self.topInset + 148
        panel = CGRect(x: screen.midX - width / 2, y: screen.maxY - height, width: width, height: height)
        let triggerHeight = max(76, self.topInset + 44)
        trigger = CGRect(x: screen.midX - 180, y: screen.maxY - triggerHeight, width: 360, height: triggerHeight)
    }
    public func mode(at local: CGPoint) -> CompressionMode? {
        guard local.y >= 28, local.y <= panel.height - topInset,
              local.x >= 0, local.x <= panel.width else { return nil }
        if local.x < panel.width / 3 { return .video }
        if local.x < panel.width * 2 / 3 { return .both }
        return .audio
    }
}
