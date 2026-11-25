import KeyboardShortcuts
import AppKit
import CoreServices
import SwiftUI
import UniformTypeIdentifiers
import NotchCompressorCore

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    let queue: JobQueue
    private let activity: QueueActivity
    private let sleepMonitor: QueueSleepMonitor
    @Published var settingsPresented = false
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

    private init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.mani.NotchCompressor", isDirectory: true)
        let queue = JobQueue(storage: folder.appendingPathComponent("queue.json"))
        self.queue = queue
        activity = QueueActivity(queue: queue)
        sleepMonitor = QueueSleepMonitor(queue: queue)
    }

    func presentQueue(settings: Bool = false) {
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
        settingsPresented = settings
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
                    urls, mode: mode, toolsDirectory: settings.toolsDirectory, enabledKinds: [.video, .image, .audio])
                try Task.checkCancellation()
                guard acceptingImports else { return }
                for input in batch.accepted {
                    queue.enqueue([input.url], mode: mode, mediaKind: input.kind, settings: settings)
                }
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
    var body: some View {
        GeometryReader { proxy in
            if presentation.showingWidgets {
                NotchWidgetsView(widgets: widgets, cameraWidth: presentation.cameraWidth)
            } else {
                VStack(spacing: 0) {
                    Color.clear.frame(height: presentation.topInset)
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            ForEach(CompressionMode.allCases) { mode in
                                DropZone(mode: mode, targeted: presentation.mode == mode)
                            }
                        }
                        Text(L10n.text("notch.dropHint"))
                            .font(.caption2).foregroundStyle(.white.opacity(0.65))
                    }.padding(14).frame(height: 148)
                        .opacity(presentation.visible ? 1 : 0)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .background(.black)
                .mask(alignment: .top) {
                    UnevenRoundedRectangle(
                        topLeadingRadius: presentation.topInset > 0 ? 0 : 16,
                        bottomLeadingRadius: presentation.visible ? 26 : 10,
                        bottomTrailingRadius: presentation.visible ? 26 : 10,
                        topTrailingRadius: presentation.topInset > 0 ? 0 : 16
                    )
                    .frame(
                        width: presentation.visible ? proxy.size.width : presentation.compactWidth,
                        height: presentation.visible ? proxy.size.height : presentation.compactHeight)
                }
                .animation(
                    reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86), value: presentation.visible)
            }
        }
        .clipped()
        .environment(\.colorScheme, .dark)
    }
}

struct DropZone: View {
    let mode: CompressionMode
    let targeted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: mode.selectionSymbol).font(.title2)
            Text(mode.selectionTitle).font(.callout.weight(.semibold))
            Text(
                mode == .video
                    ? L10n.text("notch.keepAudio")
                    : mode == .audio ? L10n.text("notch.keepVideo") : L10n.text("notch.both")
            )
            .font(.system(size: 10))
        }
        .foregroundStyle(targeted ? .black : .white)
        .frame(maxWidth: .infinity).frame(height: 88)
        .background(targeted ? Color.mint : Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: targeted)
        .accessibilityLabel(L10n.text("notch.accessibility", mode.selectionTitle))
    }
}
