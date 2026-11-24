import AppKit
import SwiftUI
import NotchCompressorCore

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var report: String
    @State private var copied = false

    init(queue: JobQueue) {
        _report = State(
            initialValue: DiagnosticReport.make(
                version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                    ?? L10n.text("app.development"),
                build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                    ?? L10n.text("app.unknown"),
                os: ProcessInfo.processInfo.operatingSystemVersion,
                jobs: queue.jobs, persistenceFailed: queue.persistenceError != nil,
                engineAvailable: (try? Toolchain.discover(directory: queue.settings.toolsDirectory)) != nil))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(L10n.text("diagnostic.windowTitle"), systemImage: "stethoscope").font(.title2.weight(.semibold))
                Spacer()
                IconControl(title: L10n.text("diagnostic.close"), symbol: "xmark") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            Text(L10n.text("diagnostic.intro"))
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                Text(report).font(.system(.body, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
            }.background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Text(L10n.text("diagnostic.noUpload")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(report, forType: .string)
                } label: {
                    Label(
                        copied ? L10n.text("diagnostic.copied") : L10n.text("diagnostic.copy"),
                        systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .capsuleControl()
            }
        }.padding(24).frame(width: 560, height: 520)
    }
}
