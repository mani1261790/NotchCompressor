import AppKit
import CoreServices
import SwiftUI
import UniformTypeIdentifiers
import NotchCompressorCore

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    let queue: JobQueue
    @Published var settingsPresented = false
    @Published var dropError: String?
    private var window: NSWindow?

    private init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.mani.NotchCompressor", isDirectory: true)
        queue = JobQueue(storage: folder.appendingPathComponent("queue.json"))
    }

    func presentQueue(settings: Bool = false) {
        if window == nil {
            let view = QueueView(queue: queue, app: self)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
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

    func chooseVideos(mode: CompressionMode) {
        let panel = NSOpenPanel()
        panel.title = "圧縮する動画を選択 — \(mode.title)"
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        queue.enqueue(panel.urls, mode: mode)
        if (try? Toolchain.discover(directory: queue.settings.toolsDirectory)) == nil { settingsPresented = true }
    }


}

@main
struct NotchCompressorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var queue = AppState.shared.queue

    var body: some Scene {
        MenuBarExtra {
            Button("圧縮キューを開く\(queue.pendingCount > 0 ? "（\(queue.pendingCount)件）" : "")") { AppState.shared.presentQueue() }
            Button("設定…") { AppState.shared.presentQueue(settings: true) }
                .keyboardShortcut(",")
            Divider()
            Text("左：画質　中央：両方　右：音質")
            Text("検証後に元動画を置き換えます")
            Divider()
            Button("NotchCompressorを終了") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
            if queue.pendingCount > 0 { Text("\(queue.pendingCount)") }
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
        let launch = NSAppleEventManager.shared().currentAppleEvent
        let loginLaunch = launch?.eventID == kAEOpenApplication &&
            launch?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !loginLaunch { AppState.shared.presentQueue() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppState.shared.presentQueue()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let queue = AppState.shared.queue
        guard queue.isBusy else { return .terminateNow }
        guard !terminating else { return .terminateLater }
        let alert = NSAlert()
        alert.messageText = "圧縮を中止して終了しますか？"
        alert.informativeText = "実行中・一時停止中・待機中の\(queue.pendingCount)件を中止します。途中データは破棄され、次回は最初からの再試行になります。元ファイルと完了済みの出力は残ります。"
        alert.addButton(withTitle: "処理を続ける")
        alert.addButton(withTitle: "中止して終了")
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        terminating = true
        Task {
            await queue.stopForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

struct DropPanel: View {
    @ObservedObject var presentation: DropPresentation
    var body: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: presentation.visible ? 26 : 10,
                                   bottomTrailingRadius: presentation.visible ? 26 : 10)
                .fill(.black)
            if presentation.visible {
                VStack(spacing: 0) {
                    Color.clear.frame(height: presentation.topInset)
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            ForEach(CompressionMode.allCases) { mode in
                                DropZone(mode: mode, targeted: presentation.mode == mode)
                            }
                        }
                        Text("ドロップして圧縮・検証後に元動画を置き換え")
                            .font(.caption2).foregroundStyle(.white.opacity(0.65))
                    }.padding(14).frame(height: 148)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .environment(\.colorScheme, .dark)
    }
}

struct DropZone: View {
    let mode: CompressionMode
    let targeted: Bool
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: mode.symbol).font(.title2)
            Text(mode.title).font(.callout.weight(.semibold))
            Text(mode == .video ? "音声はそのまま" : mode == .audio ? "映像はそのまま" : "映像と音声を圧縮")
                .font(.system(size: 10))
        }
        .foregroundStyle(targeted ? .black : .white)
        .frame(maxWidth: .infinity).frame(height: 88)
        .background(targeted ? Color.mint : Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .animation(.easeOut(duration: 0.1), value: targeted)
        .accessibilityLabel("\(mode.title)のドロップ領域")
    }
}
