import AppKit
import SwiftUI
import NotchCompressorCore

struct QueueView: View {
    @ObservedObject var queue: JobQueue
    @ObservedObject var app: AppState
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("収録を、軽く。").font(.title2.weight(.semibold))
                    Text(queue.pendingCount > 0 ? "\(queue.pendingCount)件を順番に処理します" : "動画を画面上端の中央へドラッグ")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { app.settingsPresented = true } label: { Image(systemName: "gearshape") }
                    .help("設定").accessibilityLabel("設定")
            }
            .padding(24)
            Divider()
            if let error = app.dropError {
                HStack { Text(error).font(.callout); Spacer(); Button("閉じる") { app.dropError = nil } }.padding()
            }
            if let error = queue.persistenceError { Text(error).font(.caption).foregroundStyle(.orange).padding() }
            if (try? Toolchain.discover(directory: queue.settings.toolsDirectory)) == nil {
                HStack {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text("圧縮ツールの設定が必要です")
                    Spacer()
                    Button("設定を開く") { app.settingsPresented = true }
                }.padding()
            }
            if queue.jobs.isEmpty {
                VStack(spacing: 18) {
                    Image(systemName: "arrow.up.document").font(.system(size: 38, weight: .light)).foregroundStyle(.secondary)
                    Text("ドロップする場所で、圧縮方法を選べます").font(.headline)
                    HStack(spacing: 24) {
                        ForEach(CompressionMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbol).font(.callout)
                        }
                    }.foregroundStyle(.secondary)
                    Text("左：画質のみ　中央：画質＋音質　右：音質のみ").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(queue.jobs.reversed()) { job in
                            JobRow(job: job, queue: queue).padding(.horizontal, 24).padding(.vertical, 16)
                            Divider().padding(.horizontal, 24)
                        }
                    }
                }
            }
            Divider()
            HStack {
                Text("元ファイルは残ります。確認後にFinderで整理できます。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("完了履歴を消す") { queue.clearFinished() }
                    .disabled(!queue.jobs.contains { $0.phase.isFinished })
                    .help("履歴だけを消します。動画ファイルは削除しません。")
            }.padding(16)
        }
        .sheet(isPresented: $app.settingsPresented) { SettingsView(queue: queue) }
    }
}

private struct JobRow: View {
    let job: CompressionJob
    @ObservedObject var queue: JobQueue
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                Image(systemName: job.mode.symbol).font(.title3).frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.input.lastPathComponent).font(.headline).lineLimit(2).textSelection(.enabled)
                    Text("\(job.mode.title)・\(job.settings.quality.title)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(queue.cancelling.contains(job.id) ? "停止中…" : job.phase.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(job.phase == .failed ? Color.orange : job.phase == .completed ? Color.green : Color.secondary)
            }
            if job.phase == .encoding {
                ProgressView(value: job.progress)
                Text("\(Int(job.progress * 100))%・圧縮後に出力を検証します").font(.caption).foregroundStyle(.secondary)
            } else if [.probing, .validating].contains(job.phase) {
                ProgressView().controlSize(.small)
            }
            if let result = job.result {
                HStack {
                    Text("\(bytes(result.originalBytes)) → \(bytes(result.outputBytes))")
                    Text(result.savedFraction >= 0 ? "\(Int(result.savedFraction * 100))%削減" : "\(Int(-result.savedFraction * 100))%増加")
                        .foregroundStyle(result.savedFraction >= 0 ? Color.green : Color.orange)
                }.font(.callout)
                if result.savedFraction < 0 { Text("この動画は元の方が小さい結果でした。").font(.caption).foregroundStyle(.secondary) }
            }
            if let message = job.message { Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                Button("元ファイルを表示") { NSWorkspace.shared.activateFileViewerSelecting([job.input]) }
                if let result = job.result {
                    Button("圧縮した動画を表示") { NSWorkspace.shared.activateFileViewerSelecting([result.output]) }
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
                if !job.phase.isFinished {
                    Button("キャンセル") { queue.cancel(job.id) }.disabled(queue.cancelling.contains(job.id))
                } else if job.phase != .completed {
                    Button("再試行") { queue.retry(job.id) }
                }
            }.controlSize(.small)
        }
    }
    private func bytes(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
}
