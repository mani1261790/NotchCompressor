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
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("設定").font(.title2.weight(.semibold)); Spacer(); Button("完了") { dismiss() }.keyboardShortcut(.defaultAction) }
            Form {
                Picker("圧縮の強度", selection: $queue.settings.quality) {
                    ForEach(CompressionQuality.allCases) { quality in Text(quality.title).tag(quality) }
                }
                Text("画質を変える場合は解像度を維持し、最大30fpsにします。音質のみでは映像をそのまま保持します。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text("圧縮ツール").font(.headline)
            if let tools = try? Toolchain.discover(directory: queue.settings.toolsDirectory) {
                Label("ffmpeg / ffprobe 検出済み", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text(tools.ffmpeg.deletingLastPathComponent().path).font(.caption).textSelection(.enabled)
            } else {
                Label("ffmpeg / ffprobe が必要です", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Text("両方を同じMacへインストールし、そのフォルダを選択してください。Homebrewを利用する場合は brew install ffmpeg で導入できます。")
                    .font(.caption).textSelection(.enabled)
            }
            HStack {
                Button("ツールのフォルダを選択…", action: chooseTools)
                Button("自動検出に戻す") { queue.settings.toolsDirectory = nil; message = nil }
            }
            Divider()
            Toggle("ログイン時に起動", isOn: Binding(get: { loginEnabled }, set: updateLogin))
            if SMAppService.mainApp.status == .requiresApproval {
                Button("システム設定でログイン項目を確認") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let message { Text(message).font(.caption).foregroundStyle(.orange) }
            Text("出力は元動画と同じフォルダにMOV形式で別名保存します。元動画を自動で削除することはありません。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 500)
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
