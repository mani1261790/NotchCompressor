import AppKit
import OSLog
import SwiftUI
import NotchCompressorCore

@MainActor
final class DropPresentation: ObservableObject {
    @Published var mode: CompressionMode?
    @Published var topInset: CGFloat = 0
    @Published var visible = false
}

@MainActor
private final class DropHostingView: NSHostingView<DropPanel> {
    var geometry: NotchGeometry?
    let presentation: DropPresentation
    var onEnd: (() -> Void)?
    required init(rootView: DropPanel) {
        self.presentation = rootView.presentation
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { presentation.mode = nil }
    override func draggingEnded(_ sender: NSDraggingInfo) { presentation.mode = nil; onEnd?() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { update(sender) == .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let mode = selectedMode(sender), let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        AppState.shared.queue.enqueue(urls, mode: mode)
        if (try? Toolchain.discover(directory: AppState.shared.queue.settings.toolsDirectory)) == nil {
            AppState.shared.presentQueue(settings: true)
        }
        onEnd?()
        return true
    }
    private func selectedMode(_ sender: NSDraggingInfo) -> CompressionMode? {
        let point = convert(sender.draggingLocation, from: nil)
        // NSHostingView is flipped; the geometry contract uses a bottom-left origin.
        let local = CGPoint(x: point.x, y: isFlipped ? bounds.height - point.y : point.y)
        return geometry?.mode(at: local)
    }
    private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else {
            presentation.mode = nil
            return []
        }
        presentation.mode = selectedMode(sender)
        return presentation.mode == nil ? [] : .copy
    }
}

@MainActor
final class NotchPanelController {
    private let log = Logger(subsystem: "com.mani.NotchCompressor", category: "Drag")
    private var lastLoggedPasteboard = NSPasteboard(name: .drag).changeCount
    private let panel: NSPanel
    private let presentation = DropPresentation()
    private let host: DropHostingView
    private var timer: Timer?
    private var drag = FileDragState(changeCount: NSPasteboard(name: .drag).changeCount)

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        host = DropHostingView(rootView: DropPanel(presentation: presentation))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        host.onEnd = { [weak self] in self?.drag.end(); self?.hide() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    deinit { timer?.invalidate() }

    private func hide() {
        guard panel.isVisible else { return }
        presentation.visible = false
        presentation.mode = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, !self.presentation.visible else { return }
            self.panel.orderOut(nil)
        }
    }

    private func update() {
        let pointer = NSEvent.mouseLocation
        let pasteboard = NSPasteboard(name: .drag)
        let leftDown = NSEvent.pressedMouseButtons & 1 != 0
        let hasFiles = pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        if lastLoggedPasteboard != pasteboard.changeCount {
            lastLoggedPasteboard = pasteboard.changeCount
            log.notice("Drag pasteboard changed; leftDown=\(leftDown), files=\(hasFiles)")
        }
        drag.update(changeCount: pasteboard.changeCount, leftButtonDown: leftDown, hasFiles: hasFiles)
        guard drag.active, let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) else { hide(); return }
        let geometry = NotchGeometry(screen: screen.frame, topInset: screen.safeAreaInsets.top)
        let insidePanel = presentation.visible && panel.frame == geometry.panel && panel.frame.insetBy(dx: -16, dy: -16).contains(pointer)
        guard geometry.trigger.contains(pointer) || insidePanel else { hide(); return }
        host.geometry = geometry
        presentation.topInset = geometry.topInset
        if panel.frame != geometry.panel { panel.setFrame(geometry.panel, display: true) }
        if !panel.isVisible { log.notice("Showing drop panel"); panel.orderFrontRegardless() }
        presentation.visible = true
    }
}
