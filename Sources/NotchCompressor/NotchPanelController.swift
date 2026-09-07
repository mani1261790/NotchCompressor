import AppKit
import SwiftUI

/// File-drag detection is polled without a global input monitor or Accessibility permission.
/// The panel is absent during normal pointer movement, keeping menu items available.
@MainActor
final class NotchPanelController {
    private let panel: NSPanel
    private var timer: Timer?
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var fileDragActive = false

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: DropPanel())
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    deinit { timer?.invalidate() }

    private func update() {
        let pointer = NSEvent.mouseLocation
        let isDragging = NSEvent.pressedMouseButtons & 1 != 0
        let pasteboard = NSPasteboard(name: .drag)
        if pasteboard.changeCount != dragChangeCount {
            dragChangeCount = pasteboard.changeCount
            fileDragActive = isDragging && pasteboard.canReadObject(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
            )
        }
        if !isDragging { fileDragActive = false }
        guard fileDragActive,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) else {
            // Let SwiftUI finish dispatching an in-flight drop before hiding.
            if panel.isVisible {
                DispatchQueue.main.async { [weak self] in self?.panel.orderOut(nil) }
            }
            return
        }

        let frame = screen.frame
        let trigger = NSRect(x: frame.midX - 170, y: frame.maxY - max(64, screen.safeAreaInsets.top + 24), width: 340, height: max(64, screen.safeAreaInsets.top + 24))
        let insidePanel = panel.isVisible && panel.frame.insetBy(dx: -20, dy: -20).contains(pointer)
        guard trigger.contains(pointer) || insidePanel else {
            panel.orderOut(nil)
            return
        }

        // Place controls below the camera housing; the housing itself is not a display surface.
        let topInset = screen.safeAreaInsets.top
        let rect = NSRect(x: frame.midX - 240, y: frame.maxY - topInset - 136, width: 480, height: 136)
        panel.setFrame(rect, display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
}
