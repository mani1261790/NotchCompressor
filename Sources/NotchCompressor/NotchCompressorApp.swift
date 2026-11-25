import KeyboardShortcuts
import AppKit
import CoreServices
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import NotchCompressorCore

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    let queue: JobQueue
    let isNewInstallation: Bool
    private let activity: QueueActivity
    private let sleepMonitor: QueueSleepMonitor
    @Published var settingsPresented = false {
        didSet {
            if settingsPresented { presentSettings() } else { settingsWindow?.close() }
        }
    }
    @Published var dropError: String?
    @Published private(set) var importingCount = 0
    private var importTask: Task<Void, Never>?
    private var importTasks: [UUID: Task<Void, Never>] = [:]
    private var acceptingImports = true
    @Published var rejectedInputs: [InputRejection] = []
    var isBusy: Bool { queue.isBusy || importingCount > 0 }
    func stopImports() async {
        acceptingImports = false
        let tasks = Array(importTasks.values)
        tasks.forEach { $0.cancel() }
        for task in tasks { await task.value }
    }
    private var window: NSWindow?
    private var settingsWindow: NSWindow?

    private init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.mani.NotchCompressor", isDirectory: true)
        isNewInstallation =
            !FileManager.default.fileExists(atPath: folder.appendingPathComponent("queue.json").path)
            && UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") == nil
        let queue = JobQueue(storage: folder.appendingPathComponent("queue.json"))
        self.queue = queue
        activity = QueueActivity(queue: queue)
        sleepMonitor = QueueSleepMonitor(queue: queue)
    }

    private func presentSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 840, height: 650),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = L10n.text("ui.settings")
            window.minSize = NSSize(width: 780, height: 580)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: SettingsView(queue: queue) { [weak self] in
                    self?.settingsPresented = false
                })
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func presentQueue(settings: Bool = false) {
        if settings { settingsPresented = true; return }
        if window == nil {
            let view = QueueView(queue: queue, app: self)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "NotchCompressor"
            window.minSize = NSSize(width: 540, height: 380)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: view)
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func receiveFiles(_ urls: [URL], mode: CompressionMode) {
        guard acceptingImports else { return }
        let settings = queue.settings
        let previous = importTask
        let importID = UUID()
        importingCount += urls.count
        importTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            defer { importingCount -= urls.count; importTasks.removeValue(forKey: importID) }
            do {
                let batch = try await InputBatch.inspect(
                    urls, mode: mode, toolsDirectory: settings.toolsDirectory, enabledKinds: [.video, .image, .audio]
                ) { [self] input in
                    await MainActor.run {
                        guard self.acceptingImports else { return }
                        self.queue.enqueue([input.url], mode: mode, mediaKind: input.kind, settings: settings)
                    }
                }
                try Task.checkCancellation()
                guard acceptingImports else { return }
                if !batch.rejected.isEmpty {
                    rejectedInputs.append(contentsOf: batch.rejected)
                    presentQueue()
                }
            } catch is CancellationError {
                return
            } catch {
                dropError = (error as? CompressionError)?.localizedDescription ?? L10n.text("error.read")
                presentQueue()
            }
        }
        importTasks[importID] = importTask
    }

    func chooseVideos(mode: CompressionMode) {
        let panel = NSOpenPanel()
        panel.title = L10n.text("app.choose", mode.selectionTitle)
        panel.allowedContentTypes = ["mov", "mp4", "m4v", "jpg", "jpeg", "png", "m4a"].compactMap {
            UTType(filenameExtension: $0)
        }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        receiveFiles(panel.urls, mode: mode)
        if (try? Toolchain.discover(directory: queue.settings.toolsDirectory)) == nil { settingsPresented = true }
    }

}

@main
struct NotchCompressorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var queue = AppState.shared.queue
    @ObservedObject private var updates = UpdateController.shared

    var body: some Scene {
        MenuBarExtra {
            Text(queue.status.title)
            if let notice = queue.completionNotice { Text(notice.text) }
            Divider()
            Button(
                queue.pendingCount > 0
                    ? L10n.text("app.openQueueCount", L10n.integer(queue.pendingCount + AppState.shared.importingCount))
                    : L10n.text("app.openQueue")
            ) {
                AppState.shared.presentQueue()
            }
            Button(L10n.text("app.settings")) { AppState.shared.presentQueue(settings: true) }
                .keyboardShortcut(",")
            Button(L10n.text("app.checkUpdates")) { updates.check() }
                .disabled(!updates.canCheck || queue.isBusy)
            Divider()
            Text(L10n.text("app.zones"))
            Text(L10n.text("app.replace"))
            Divider()
            Button(L10n.text("app.quit")) { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(
                systemName: queue.completionNotice != nil && !queue.isBusy && queue.status.count == 0
                    ? "checkmark.circle" : queue.status.symbol
            )
            .accessibilityLabel(queue.status.title)
            if queue.status.count > 0 { Text("\(queue.status.count)") }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchPanelController?
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if Bundle.main.bundleIdentifier == "com.mani.NotchCompressor",
            AppState.shared.isNewInstallation,
            !UserDefaults.standard.bool(forKey: "initialLoginSetupAttempted")
        {
            UserDefaults.standard.set(true, forKey: "initialLoginSetupAttempted")
            // Existing installations and explicit system choices are never overwritten.
            if SMAppService.mainApp.status == .notRegistered {
                try? SMAppService.mainApp.register()
            }
        }
        controller = NotchPanelController()
        UpdateController.shared.start()
        TaskNotifications.shared.start(queue: AppState.shared.queue)
        KeyboardShortcuts.onKeyUp(for: .showCompressionQueue) {
            AppState.shared.presentQueue()
        }
        let launch = NSAppleEventManager.shared().currentAppleEvent
        let loginLaunch =
            launch?.eventID == kAEOpenApplication
            && launch?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !loginLaunch { AppState.shared.presentQueue() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppState.shared.presentQueue()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let queue = AppState.shared.queue
        guard AppState.shared.isBusy else { return .terminateNow }
        // An updater must never turn a running or paused compression into cancellation.
        if UpdateController.shared.installing { return .terminateCancel }
        guard !terminating else { return .terminateLater }
        let alert = NSAlert()
        alert.messageText = L10n.text("app.quitTitle")
        alert.informativeText =
            L10n.text("app.quitBody", L10n.integer(queue.pendingCount + AppState.shared.importingCount))
        alert.addButton(withTitle: L10n.text("app.keepRunning"))
        alert.addButton(withTitle: L10n.text("app.cancelQuit"))
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        terminating = true
        Task {
            await AppState.shared.stopImports()
            await queue.stopForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

struct DropPanel: View {
    @ObservedObject var presentation: DropPresentation
    @ObservedObject private var widgets = NotchWidgetsController.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                if presentation.compactWidgets {
                    NotchWidgetsView(widgets: widgets, cameraWidth: presentation.cameraWidth)
                } else {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: presentation.topInset)
                        ZStack {
                            if presentation.receivedFiles {
                                VStack(spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 30, weight: .medium)).foregroundStyle(.blue)
                                    Text(L10n.text("notch.received")).font(.callout.weight(.medium))
                                }
                                .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.92)))
                            } else if presentation.showingWidgets {
                                NotchDashboardView(widgets: widgets).transition(.opacity)
                            } else {
                                VStack(spacing: 12) {
                                    HStack(spacing: 8) {
                                        ForEach(presentation.content.modes) { mode in
                                            DropZone(
                                                mode: mode, content: presentation.content,
                                                targeted: presentation.mode == mode, selection: selection)
                                        }
                                    }
                                    Text(L10n.text("notch.dropHint"))
                                        .font(.caption2).foregroundStyle(.white.opacity(0.65))
                                }.transition(.opacity)
                            }
                        }.padding(14).frame(height: 148)
                            .opacity(presentation.visible ? 1 : 0)
                            .offset(y: reduceMotion || presentation.visible ? 0 : -8)
                            .scaleEffect(reduceMotion || presentation.visible ? 1 : 0.97, anchor: .top)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .background(.black)
            .mask(alignment: .top) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: presentation.visible ? 26 : 10,
                    bottomTrailingRadius: presentation.visible ? 26 : 10,
                    topTrailingRadius: 0
                )
                .frame(
                    width: presentation.visible || presentation.compactWidgets
                        ? proxy.size.width : presentation.compactWidth,
                    height: presentation.visible || presentation.compactWidgets
                        ? proxy.size.height : presentation.compactHeight)
            }
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.88), value: presentation.visible)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: presentation.showingWidgets)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: presentation.receivedFiles)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82), value: presentation.mode)
        }
        .clipped()
        .environment(\.colorScheme, .dark)
    }
}

struct DropZone: View {
    let mode: CompressionMode
    let content: NotchDropContent
    private var title: String { content == .video ? mode.title : content.title }
    let targeted: Bool
    let selection: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: content == .video ? mode.symbol : content.symbol).font(.title2)
                .scaleEffect(targeted && !reduceMotion ? 1.12 : 1)
            Text(title).font(.callout.weight(.semibold))
            Text(
                content != .video
                    ? content.hint
                    : mode == .video
                        ? L10n.text("notch.keepAudio")
                        : mode == .audio ? L10n.text("notch.keepVideo") : L10n.text("notch.both")
            )
            .font(.system(size: 10))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity).frame(height: 88)
        .background {
            RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.08))
            if targeted {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.blue.gradient)
                    .matchedGeometryEffect(id: "drop-selection", in: selection)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(targeted ? 0.28 : 0.08), lineWidth: 1)
        }
        .accessibilityLabel(L10n.text("notch.accessibility", title))
    }
}
