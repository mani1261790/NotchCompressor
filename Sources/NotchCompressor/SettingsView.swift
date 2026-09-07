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
                    Label("検証後に元動画を置き換えます", systemImage: "checkmark.shield")
                    Text("同じファイル名・場所・拡張子で保存します。失敗・キャンセル時は元動画を保持します。置き換え後、圧縮前の動画は残りません。")
                        .font(.callout).foregroundStyle(.secondary)
                } header: { Text("保存") }
                Section {
                    LabeledContent("バージョン", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "開発版")
                    Text("NotchCompressor · Apache 2.0\nFFmpeg 9.0.1 · LGPL 2.1 or later")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        if let url = Bundle.main.resourceURL?.appendingPathComponent("Licenses") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: { Label("ライセンス", systemImage: "doc.text") }.capsuleControl()
                } header: { Text("このアプリについて") }
            }.formStyle(.grouped)
        }.frame(width: 560, height: 620)
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
