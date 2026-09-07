import AppKit
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

    func receive(_ providers: [NSItemProvider], mode: CompressionMode) -> Bool {
        let providers = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !providers.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            var failed = 0
            // Preserve the source order; each provider is resolved independently.
            for provider in providers {
                let url: URL? = await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        let url: URL?
                        if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                        else { url = item as? URL }
                        continuation.resume(returning: url?.isFileURL == true ? url : nil)
                    }
                }
                if let url { urls.append(url) } else { failed += 1 }
            }
            if failed > 0 { dropError = "\(failed)件のファイルを読み取れませんでした。Finderから再度ドロップしてください。" }
            queue.enqueue(urls, mode: mode)
            if failed > 0 { presentQueue() }
            if (try? Toolchain.discover(directory: queue.settings.toolsDirectory)) == nil { presentQueue(settings: true) }
        }
        return true
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
            Text("元ファイルを残して別名保存します")
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
        if !UserDefaults.standard.bool(forKey: "hasShownWelcome") {
            AppState.shared.presentQueue()
            UserDefaults.standard.set(true, forKey: "hasShownWelcome")
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let queue = AppState.shared.queue
        guard queue.isBusy else { return .terminateNow }
        guard !terminating else { return .terminateLater }
        let alert = NSAlert()
        alert.messageText = "圧縮を中止して終了しますか？"
        alert.informativeText = "処理中・待機中の\(queue.pendingCount)件をキャンセルします。元ファイルと完了済みの出力は残ります。"
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
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(CompressionMode.allCases) { mode in DropZone(mode: mode) }
            }
            Text("ドロップして圧縮・元ファイルは残ります")
                .font(.caption2).foregroundStyle(.white.opacity(0.65))
        }
        .padding(14)
        .background(.black.opacity(0.96), in: UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
        .environment(\.colorScheme, .dark)
    }
}

struct DropZone: View {
    let mode: CompressionMode
    @State private var targeted = false
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: mode.symbol).font(.title2)
            Text(mode.title).font(.callout.weight(.semibold))
        }
        .foregroundStyle(targeted ? .black : .white)
        .frame(maxWidth: .infinity).frame(height: 82)
        .background(targeted ? Color.mint : Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .animation(.easeOut(duration: 0.12), value: targeted)
        .accessibilityLabel("\(mode.title)のドロップ領域")
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { providers in
            AppState.shared.receive(providers, mode: mode)
        }
    }
}
