import AppKit
import OSLog
import SwiftUI
import NotchCompressorCore

@MainActor
final class DropPresentation: ObservableObject {
    @Published var content = NotchDropContent.automatic
    @Published var receivedFiles = false
    @Published var mode: CompressionMode?
    @Published var topInset: CGFloat = 0
    @Published var visible = false
    @Published var showingWidgets = false
    @Published var compactWidgets = false
    @Published var compactWidth: CGFloat = 180
    @Published var compactHeight: CGFloat = 28
    @Published var cameraWidth: CGFloat = 0
}

@MainActor
private final class DropHostingView: NSHostingView<DropPanel> {
    var geometry: NotchGeometry?
    let presentation: DropPresentation
    var onEnd: (() -> Void)?
    var onAccepted: (() -> Void)?
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
        guard let mode = selectedMode(sender),
            let urls = sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty
        else { return false }
        AppState.shared.receiveFiles(urls, mode: mode)
        if (try? Toolchain.discover(directory: AppState.shared.queue.settings.toolsDirectory)) == nil {
            AppState.shared.presentQueue(settings: true)
        }
        onAccepted?()
        return true
    }
    private func selectedMode(_ sender: NSDraggingInfo) -> CompressionMode? {
        let point = convert(sender.draggingLocation, from: nil)
        // NSHostingView is flipped; the geometry contract uses a bottom-left origin.
        let local = CGPoint(x: point.x, y: isFlipped ? bounds.height - point.y : point.y)
        return presentation.content.mode(for: geometry?.mode(at: local))
    }
    private var contentGeneration: Int?
    func updateContent(_ pasteboard: NSPasteboard) {
        guard contentGeneration != pasteboard.changeCount else { return }
        let urls =
            pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return }
        contentGeneration = pasteboard.changeCount
        presentation.content = NotchDropContent(urls: urls)
    }
    private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard
            sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        else {
            presentation.mode = nil
            return []
        }
        updateContent(sender.draggingPasteboard)
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
    private var collapseTask: Task<Void, Never>?
    private var receiptTask: Task<Void, Never>?
    private let widgets = NotchWidgetsController.shared
    private var nativeDrop = NativeDropSession()
    private var hover = NotchHoverState()
    private var drag = FileDragState(changeCount: NSPasteboard(name: .drag).changeCount)

    init() {
        // Give GeometryReader a real, top-centered canvas on its first layout.
        // Starting at .zero lets the first spring interpolate from the window origin.
        let initialScreen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
        let initialFrame =
            initialScreen.map {
                NotchGeometry(screen: $0.frame, topInset: $0.safeAreaInsets.top).panel
            } ?? CGRect(x: 0, y: 0, width: 480, height: 148)
        panel = NSPanel(
            contentRect: initialFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        host = DropHostingView(rootView: DropPanel(presentation: presentation))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .canJoinAllApplications,
        ]
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        host.onEnd = { [weak self] in
            guard let self else { return }
            nativeDrop.ended(); drag.end()
            if receiptTask == nil { collapse() }
        }
        host.onAccepted = { [weak self] in
            guard let self else { return }
            nativeDrop.ended(); drag.end()
            presentation.mode = nil
            presentation.receivedFiles = true
            panel.ignoresMouseEvents = true
            receiptTask?.cancel()
            receiptTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(550)) } catch { return }
                guard let self else { return }
                receiptTask = nil
                collapse()
            }
        }
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
        return NotchGeometry(
            screen: screen.frame, topInset: screen.safeAreaInsets.top,
            notchWidth: notchWidth > 0 ? notchWidth : 180)
    }

    private func setFrame(_ frame: CGRect) {
        guard panel.frame != frame else { return }
        // AppKit must see the final drop surface immediately. Animating the actual
        // window makes its tracking rectangle move under an ongoing Finder drag.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            panel.setFrame(frame, display: false, animate: false)
            host.layoutSubtreeIfNeeded()
        }
    }

    private func prepareExpansionLayout(_ geometry: NotchGeometry) {
        // Commit the closed mask at the destination size before changing visible.
        // Also covers switching displays or expanding from compact widgets.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            host.geometry = geometry
            presentation.topInset = geometry.topInset
            presentation.compactWidth = geometry.collapsed.width
            presentation.compactHeight = geometry.collapsed.height
            presentation.compactWidgets = false
            setFrame(geometry.panel)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
        }
    }

    private func trace(_ phase: String) {
        guard lastPhase != phase else { return }
        lastPhase = phase
        log.notice("Panel state: \(phase, privacy: .public)")
    }

    private func collapse() {
        guard collapseTask == nil else { return }
        panel.ignoresMouseEvents = true
        if presentation.mode != nil { presentation.mode = nil }
        if presentation.visible {
            presentation.visible = false
            collapseTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(220)) } catch { return }
                guard let self else { return }
                collapseTask = nil
                finishCollapse()
            }
        } else {
            finishCollapse()
        }
    }

    private func finishCollapse() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first else {
            panel.orderOut(nil); return
        }
        let geometry = geometry(on: screen)
        if presentation.topInset != geometry.topInset { presentation.topInset = geometry.topInset }
        if presentation.compactWidth != geometry.collapsed.width {
            presentation.compactWidth = geometry.collapsed.width
        }
        if presentation.compactHeight != geometry.collapsed.height {
            presentation.compactHeight = geometry.collapsed.height
        }
        host.geometry = geometry
        if presentation.showingWidgets != (widgets.alwaysVisible && widgets.hasVisibleContent) {
            presentation.showingWidgets = widgets.alwaysVisible && widgets.hasVisibleContent
        }
        let compactWidgets = widgets.alwaysVisible && widgets.hasVisibleContent
        if presentation.compactWidgets != compactWidgets { presentation.compactWidgets = compactWidgets }
        if widgets.alwaysVisible && widgets.hasVisibleContent {
            let layout = NotchWidgetGeometry(
                screen: screen.frame, topInset: geometry.topInset, notchWidth: geometry.collapsed.width)
            if presentation.cameraWidth != layout.cameraWidth { presentation.cameraWidth = layout.cameraWidth }
            setFrame(layout.frame)
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else {
            // Keep the hidden canvas laid out, without intercepting the menu bar.
            setFrame(geometry.panel)
            host.layoutSubtreeIfNeeded()
            if panel.isVisible { panel.orderOut(nil) }
        }
    }

    private func expand(on screen: NSScreen, information: Bool = false) {
        collapseTask?.cancel(); collapseTask = nil
        receiptTask?.cancel(); receiptTask = nil
        if presentation.receivedFiles { presentation.receivedFiles = false }
        let geometry = geometry(on: screen)
        if !presentation.visible || panel.frame != geometry.panel {
            prepareExpansionLayout(geometry)
        }
        if presentation.showingWidgets != information { presentation.showingWidgets = information }
        panel.ignoresMouseEvents = false
        if !panel.isVisible { panel.orderFrontRegardless() }
        if !presentation.visible { presentation.visible = true }
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
        if hasFiles { host.updateContent(pasteboard) }
        drag.update(changeCount: pasteboard.changeCount, leftButtonDown: leftDown, hasFiles: hasFiles)
        if receiptTask != nil && !drag.active { return }
        // Do not resize away the drop target between mouse-up and performDragOperation.
        if nativeDrop.holdsPanelOpen(leftButtonDown: leftDown, now: ProcessInfo.processInfo.systemUptime) {
            trace("native destination"); return
        }
        let screens = NSScreen.screens
        guard let screenIndex = NotchGeometry.screenIndex(containing: pointer, frames: screens.map(\.frame))
        else { hover.reset(); collapse(); return }
        let screen = screens[screenIndex]
        let geometry = geometry(on: screen)
        if !drag.active {
            if leftDown {
                if presentation.visible && presentation.showingWidgets && panel.frame.contains(pointer) { return }
                hover.reset(); collapse(); return
            }
            let trigger = geometry.collapsed.insetBy(dx: -20, dy: 0)
            let inTrigger =
                pointer.x >= trigger.minX && pointer.x <= trigger.maxX
                && pointer.y >= trigger.minY && pointer.y <= trigger.maxY
            hover.update(
                insideTrigger: inTrigger,
                insidePanel: presentation.visible && presentation.showingWidgets
                    && panel.frame.insetBy(dx: -12, dy: -12).contains(pointer),
                now: ProcessInfo.processInfo.systemUptime)
            if hover.expanded { expand(on: screen, information: true) } else { collapse() }
            return
        }
        hover.reset()
        let insidePanel =
            presentation.visible && panel.frame == geometry.panel
            && panel.frame.insetBy(dx: -16, dy: -16).contains(pointer)
        guard geometry.isInTrigger(pointer) || insidePanel else {
            trace("compact: file outside trigger"); collapse(); return
        }
        trace("expanded: file inside trigger")
        expand(on: screen)
    }
}
