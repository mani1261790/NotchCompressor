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
    var onFileEntered: (() -> Void)?
    var onFileExited: (() -> Void)?
    required init(rootView: DropPanel) {
        self.presentation = rootView.presentation
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { presentation.mode = nil; onFileExited?() }
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
        onFileEntered?()
        presentation.mode = selectedMode(sender)
        return presentation.mode == nil ? [] : .copy
    }
}

@MainActor
final class NotchPanelController {
    private let log = Logger(subsystem: "com.mani.NotchCompressor", category: "Drag")
    private var lastPhase = ""
    private var lastLoggedPasteboard = NSPasteboard(name: .drag).changeCount
    private let panel: NSPanel
    private let presentation = DropPresentation()
    private let host: DropHostingView
    private var timer: Timer?
    private var nativeDrop = NativeDropSession()
    private var drag = FileDragState(changeCount: NSPasteboard(name: .drag).changeCount)

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        host = DropHostingView(rootView: DropPanel(presentation: presentation))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .canJoinAllApplications]
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        host.onEnd = { [weak self] in self?.nativeDrop.ended(); self?.drag.end(); self?.collapse() }
        host.onFileExited = { [weak self] in self?.nativeDrop.ended() }
        host.onFileEntered = { [weak self] in
            guard let self, let screen = self.panel.screen else { return }
            self.nativeDrop.entered()
            self.expand(on: screen)
        }
        collapse()
        timer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    deinit { timer?.invalidate() }

    private func geometry(on screen: NSScreen) -> NotchGeometry {
        let notchWidth = (screen.auxiliaryTopRightArea?.minX ?? 0) - (screen.auxiliaryTopLeftArea?.maxX ?? 0)
        return NotchGeometry(screen: screen.frame, topInset: screen.safeAreaInsets.top,
                             notchWidth: notchWidth > 0 ? notchWidth : 180)
    }

    private func setFrame(_ frame: CGRect) {
        guard panel.frame != frame else { return }
        // AppKit must see the final drop surface immediately. Animating the actual
        // window makes its tracking rectangle move under an ongoing Finder drag.
        panel.setFrame(frame, display: true, animate: false)
    }

    private func trace(_ phase: String) {
        guard lastPhase != phase else { return }
        lastPhase = phase
        log.notice("Panel state: \(phase, privacy: .public)")
    }

    private func collapse() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first else { return }
        let geometry = geometry(on: screen)
        presentation.visible = false
        presentation.mode = nil
        presentation.topInset = geometry.topInset
        host.geometry = geometry
        setFrame(geometry.collapsed)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func expand(on screen: NSScreen) {
        let geometry = geometry(on: screen)
        host.geometry = geometry
        presentation.topInset = geometry.topInset
        presentation.visible = true
        setFrame(geometry.panel)
        if !panel.isVisible { panel.orderFrontRegardless() }
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
        // Do not resize away the drop target between mouse-up and performDragOperation.
        if nativeDrop.holdsPanelOpen(leftButtonDown: leftDown, now: ProcessInfo.processInfo.systemUptime) { trace("native destination"); return }
        let screens = NSScreen.screens
        guard drag.active, let screenIndex = NotchGeometry.screenIndex(containing: pointer, frames: screens.map(\.frame)) else { trace("compact: no active file drag"); collapse(); return }
        let screen = screens[screenIndex]
        let geometry = geometry(on: screen)
        let insidePanel = presentation.visible && panel.frame == geometry.panel && panel.frame.insetBy(dx: -16, dy: -16).contains(pointer)
        guard geometry.isInTrigger(pointer) || insidePanel else { trace("compact: file outside trigger"); collapse(); return }
        trace("expanded: file inside trigger")
        expand(on: screen)
    }
}
