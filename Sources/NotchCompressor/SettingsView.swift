import AppKit
import SwiftUI
import ServiceManagement
import NotchCompressorCore

struct SettingsView: View {
    @ObservedObject var queue: JobQueue
    @Environment(\.dismiss) private var dismiss
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("設定", systemImage: "slider.horizontal.3").font(.title2.weight(.semibold))
                Spacer()
                IconControl(title: "設定を閉じる", symbol: "checkmark", prominent: true) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }.padding(24)
            Form {
                Section {
                    Picker("圧縮の強度", selection: $queue.settings.quality) {
                        ForEach(CompressionQuality.allCases) { quality in Text(quality.title).tag(quality) }
                    }.pickerStyle(.segmented)
                    Text("画質の変更は解像度を維持し、最大30fpsに。音質のみの場合は映像をそのまま保持します。")
                        .font(.callout).foregroundStyle(.secondary)
                } header: { Label("圧縮", systemImage: "slider.horizontal.3") }
                Section {
                    if let tools = try? Toolchain.discover(directory: queue.settings.toolsDirectory) {
                        Label("圧縮ツールを検出しました", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(tools.ffmpeg.deletingLastPathComponent().path)
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    } else {
                        Label("圧縮ツールを設定してください", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("ffmpegとffprobeを同じMacにインストールしてください。Homebrewでは brew install ffmpeg で導入できます。")
                            .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    HStack {
                        Button(action: chooseTools) { Label("フォルダを選択", systemImage: "folder") }.capsuleControl()
                        Spacer()
                        IconControl(title: "自動検出に戻す", symbol: "arrow.counterclockwise") {
                            queue.settings.toolsDirectory = nil; message = nil
                        }
                    }
                } header: { Label("圧縮ツール", systemImage: "wrench.and.screwdriver") }
                Section {
                    Toggle("ログイン時に起動", isOn: Binding(get: { loginEnabled }, set: updateLogin))
                        .toggleStyle(.switch)
                    if SMAppService.mainApp.status == .requiresApproval {
                        Button { SMAppService.openSystemSettingsLoginItems() } label: {
                            Label("ログイン項目を確認", systemImage: "arrow.up.forward.app")
                        }.capsuleControl()
                    }
                    if let message { Text(message).font(.callout).foregroundStyle(.orange) }
                } header: { Label("起動", systemImage: "power") }
                Section {
                    Label("元動画はそのまま残ります", systemImage: "checkmark.shield")
                    Text("同じフォルダにMOV形式で別名保存します。元動画を自動で削除することはありません。")
                        .font(.callout).foregroundStyle(.secondary)
                } header: { Text("保存") }
            }.formStyle(.grouped)
        }.frame(width: 560, height: 620)
    }

    private func chooseTools() {
        let panel = NSOpenPanel()
        panel.title = "ffmpegとffprobeが入ったフォルダを選択"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try Toolchain(directory: url)
            queue.settings.toolsDirectory = url.path
            message = nil
        } catch { message = error.localizedDescription }
    }

    private func updateLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            message = nil
        } catch {
            loginEnabled = SMAppService.mainApp.status == .enabled
            message = "ログイン項目を変更できませんでした。\(error.localizedDescription)"
        }
    }
}
