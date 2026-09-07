import CoreGraphics
import Foundation

public struct FileDragState {
    private var changeCount: Int
    public private(set) var active = false
    public init(changeCount: Int) { self.changeCount = changeCount }
    public mutating func update(changeCount: Int, leftButtonDown: Bool, hasFiles: Bool) {
        if self.changeCount != changeCount {
            self.changeCount = changeCount
            active = leftButtonDown && hasFiles
        }
        if !leftButtonDown { active = false }
    }
    public mutating func end() { active = false }
}

public struct NotchGeometry {
    public let panel: CGRect
    public let trigger: CGRect
    public let topInset: CGFloat
    public init(screen: CGRect, topInset: CGFloat) {
        self.topInset = max(0, topInset)
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
