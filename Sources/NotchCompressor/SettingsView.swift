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
                    Picker("品質と容量", selection: $queue.settings.quality) {
                        ForEach(CompressionQuality.allCases) { quality in Text(quality.title).tag(quality) }
                    }.pickerStyle(.segmented)
                    Text(queue.settings.quality.explanation)
                        .font(.callout)
                    Text("どの圧縮方法にも適用します。「画質のみ」なら映像の設定だけ、「音質のみ」なら音声の設定だけを使います。")
                        .font(.caption).foregroundStyle(.secondary)
                    if queue.settings.quality != .custom {
                        LabeledContent { Text(queue.settings.quality.videoBudgetDescription) } label: {
                            Label("映像", systemImage: "video")
                        }
                        LabeledContent { Text("AAC・目標 \(queue.settings.quality.audioBitrate / 1000) kbps") } label: {
                            Label("音声", systemImage: "waveform")
                        }
                        Text("映像は解像度・fps・元のビットレートから自動調整します。上の割合まで必ず使うわけではなく、容量の削減率でもありません。")
                            .font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("映像の自動調整を詳しく") {
                            Text("解像度 × 最大30fps × 係数で計算した値と、元ビットレートの上限割合のうち、小さい方を目標にします。係数は品質優先0.09・標準0.06・容量優先0.035。目標の範囲は150 kbps〜12 Mbpsです。元ビットレートが不明な場合は、解像度とfpsから計算します。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if queue.settings.quality == .custom {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("映像のビットレート", value: "元の\(queue.settings.effectiveVideoPercent)%")
                                .monospacedDigit()
                            Slider(value: Binding(get: { Double(queue.settings.effectiveVideoPercent) },
                                                  set: { queue.settings.videoPercent = Int($0) }), in: 10...100, step: 1)
                                .accessibilityLabel("映像のビットレート割合")
                                .accessibilityValue("元の\(queue.settings.effectiveVideoPercent)%")
                            Text("小さいほど容量を抑え、画質が下がります。元の値が不明な場合は容量と長さから推定します。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("音声のビットレート", value: "\(queue.settings.effectiveAudioKbps) kbps")
                                .monospacedDigit()
                            Slider(value: Binding(get: { Double(queue.settings.effectiveAudioKbps) },
                                                  set: { queue.settings.audioKbps = Int($0) }), in: 32...256, step: 8)
                                .accessibilityLabel("音声のビットレート")
                                .accessibilityValue("\(queue.settings.effectiveAudioKbps) kbps")
                            Text("小さいほど容量を抑え、音質が下がります。元音声のビットレートを上限に調整します（最低32 kbps）。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("映像50%は、ファイル容量を必ず半分にする指定ではありません。実際の容量は内容や保持する音声・映像によって変わります。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("設定は自動保存し、次に追加する動画から適用します。追加済みの動画の設定は変わりません。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("音声の実際の目標は元のビットレートを上限に調整します（最低32 kbps）。ビットレートは1秒あたりのデータ量で、値が小さいほど容量を抑えられます。")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Label("圧縮", systemImage: "slider.horizontal.3") }
                Section {
                    LabeledContent("左・画質のみ", value: "映像を再圧縮／音声はそのまま")
                    LabeledContent("中央・画質＋音質", value: "映像と音声の両方を再圧縮")
                    LabeledContent("右・音質のみ", value: "音声を再圧縮／映像はそのまま")
                    Text("圧縮する対象は、ドロップする位置か追加メニューで選びます。変更しない映像・音声は再圧縮せずコピーするため、その部分の品質は変わりません。")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Label("何を圧縮するか", systemImage: "square.split.2x1") }
                Section {
                    LabeledContent("映像", value: "HEVC（H.265）・Macのハードウェアで変換")
                    Text("解像度は維持します。30fpsを超える動画は原則30fpsに下げるため、動きの滑らかさは変わります。")
                        .font(.caption).foregroundStyle(.secondary)
                    LabeledContent("音声", value: "AACに変換")
                    Text("品質優先・標準・容量優先・カスタムで変換方式は共通です。3つのプリセットは映像のデータ量を自動調整し、カスタムは元の映像ビットレートに対する割合を使います。どれも再圧縮する部分は非可逆で、失った品質は戻せません。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("ファイル名・場所・MOV／MP4／M4Vの拡張子は維持します。容量は内容によって変わり、圧縮前より増える場合もあります。")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Label("どの方式で変換するか", systemImage: "arrow.triangle.2.circlepath") }
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
