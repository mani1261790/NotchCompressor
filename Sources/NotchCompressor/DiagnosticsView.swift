import AppKit
import SwiftUI
import NotchCompressorCore

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var report: String
    @State private var copied = false

    init(queue: JobQueue) {
        _report = State(initialValue: DiagnosticReport.make(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "開発版",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "不明",
            os: ProcessInfo.processInfo.operatingSystemVersion,
            jobs: queue.jobs, persistenceFailed: queue.persistenceError != nil,
            engineAvailable: (try? Toolchain.discover(directory: queue.settings.toolsDirectory)) != nil))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("診断情報", systemImage: "stethoscope").font(.title2.weight(.semibold))
                Spacer()
                IconControl(title: "診断情報を閉じる", symbol: "xmark") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            Text("以下はこの画面を開いた時点の情報です。内容を確認して、不具合の報告に貼り付けられます。")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                Text(report).font(.system(.body, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
            }.background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Text("外部への自動送信はありません").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(report, forType: .string)
                } label: { Label(copied ? "コピーしました" : "診断情報をコピー", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .capsuleControl()
            }
        }.padding(24).frame(width: 560, height: 520)
    }
}
