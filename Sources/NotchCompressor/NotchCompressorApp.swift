import NotchCompressorCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var lastDrop = "まだファイルを受け取っていません"

    func receive(_ providers: [NSItemProvider], mode: CompressionMode) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !files.isEmpty else { return false }
        for provider in files {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                Task { @MainActor in
                    guard error == nil, let url, url.isFileURL else {
                        self.lastDrop = "ファイルを読み取れませんでした"
                        return
                    }
                    self.lastDrop = "\(url.lastPathComponent) — \(mode.title)（受け取り確認のみ）"
                }
            }
        }
        return true
    }
}

@main
struct NotchCompressorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra("NotchCompressor", systemImage: "arrow.down.right.and.arrow.up.left") {
            Text("NotchCompressor・操作プロトタイプ")
            Text("ファイルを画面上端の中央へドラッグ")
            Divider()
            Text(state.lastDrop)
            Text("圧縮処理は未接続です。元ファイルは変更しません。")
            Divider()
            Button("終了") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = NotchPanelController()
    }
}

struct DropPanel: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(CompressionMode.allCases) { mode in
                    DropZone(mode: mode)
                }
            }
            Text("操作プレビュー・圧縮はまだ行いません")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(14)
        .background(.black.opacity(0.96), in: UnevenRoundedRectangle(
            bottomLeadingRadius: 24, bottomTrailingRadius: 24
        ))
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
        .frame(maxWidth: .infinity)
        .frame(height: 82)
        .background(targeted ? Color.mint : Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(targeted ? Color.mint : .clear, lineWidth: 2))
        .animation(.easeOut(duration: 0.12), value: targeted)
        .accessibilityLabel("\(mode.title)のドロップ領域")
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { providers in
            AppState.shared.receive(providers, mode: mode)
        }
    }
}
