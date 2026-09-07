import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OSLog
import NotchCompressorCore

struct QueueView: View {
    @ObservedObject var queue: JobQueue
    @ObservedObject var app: AppState
    @State private var draggingJobID: UUID?
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("圧縮キュー").font(.title2.weight(.semibold))
                    Text(queue.pendingCount > 0 ? "実行中 \(queue.runningCount)件 · 待機 \(queue.waitingJobs.count)件" : "動画を画面上端の中央へドラッグ")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    ForEach(CompressionMode.allCases) { mode in
                        Button { app.chooseVideos(mode: mode) } label: { Label(mode.title, systemImage: mode.symbol) }
                    }
                } label: {
                    Color.clear.frame(width: 36, height: 36)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .frame(width: 44, height: 44).modifier(GlassCircleSurface())
                // Center against the visible circle, independent of NSMenu's label insets.
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 44, height: 44, alignment: .center)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .help("動画を追加して圧縮方法を選ぶ").accessibilityLabel("動画を追加")
                IconControl(title: "設定", symbol: "gearshape") { app.settingsPresented = true }
            }
            .padding(24)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Menu {
                        Picker("実行方式", selection: $queue.execution) {
                            ForEach(QueueExecution.allCases) { mode in Text(mode.title).tag(mode) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Label(queue.execution.title, systemImage: "slider.horizontal.3")
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                        }
                    }.capsuleMenu().accessibilityLabel("実行方式：\(queue.execution.title)")
                    Spacer()
                    Text(queue.isPaused ? "待機を一時停止" : "ドラッグで待機順を変更")
                        .font(.caption).foregroundStyle(.secondary)
                    IconControl(title: queue.isPaused ? "待機中の処理を再開" : "新しい処理を一時停止",
                                symbol: queue.isPaused ? "play.fill" : "pause.fill") { queue.togglePause() }
                }
                Text(queue.schedulingDescription).font(.caption).foregroundStyle(.secondary)
                .help("空き枠で実行できる動画から開始します。待機中のカードをドラッグして順番を変更できます。")
            }.padding(.horizontal, 24).padding(.bottom, 14)
            Divider()
            if let error = app.dropError {
                HStack { Text(error).font(.callout); Spacer(); IconControl(title: "閉じる", symbol: "xmark") { app.dropError = nil } }.padding()
            }
            if let error = queue.persistenceError { Text(error).font(.caption).foregroundStyle(.orange).padding() }
            if (try? Toolchain.discover(directory: queue.settings.toolsDirectory)) == nil {
                HStack {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text("圧縮エンジンが不足しています。アプリを再インストールしてください。")
                    Spacer()
                }.padding()
            }
            if queue.displayedJobs.isEmpty {
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
                    LazyVStack(spacing: 12) {
                        ForEach(queue.displayedJobs) { job in
                            if job.phase == .waiting {
                                card(job)
                                    .onDrag {
                                        draggingJobID = job.id
                                        queueDragLog.info("queue drag began")
                                        return NSItemProvider(item: Data(job.id.uuidString.utf8) as NSData,
                                                              typeIdentifier: UTType.notchQueueJob.identifier)
                                    }
                                    .modifier(QueueDropTarget(queue: queue, job: job, draggingID: $draggingJobID))
                            } else {
                                card(job)
                            }
                        }
                    }.padding(20)
                }.background(.quaternary.opacity(0.35))
            }
            Divider()
            HStack {
                Text("圧縮結果を検証してから、元動画を置き換えます。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                IconControl(title: "終了した項目を消す（動画は残ります）", symbol: "clock.badge.xmark") { queue.clearFinished() }
                    .disabled(!queue.displayedJobs.contains { $0.phase.isFinished })
                    .help("履歴だけを消します。動画ファイルは削除しません。")
            }.padding(16)
        }
        .sheet(isPresented: $app.settingsPresented) { SettingsView(queue: queue) }
    }
    private func card(_ job: CompressionJob) -> some View {
        JobRow(job: job, queue: queue)
            .padding(18)
            .background(.background, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.06)))
    }

}

private struct JobRow: View {
    let job: CompressionJob
    @ObservedObject var queue: JobQueue
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                VideoThumbnail(urls: [job.result?.output, job.input].compactMap { $0 })
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.input.lastPathComponent).font(.headline).lineLimit(2)
                    Label("\(job.mode.title)・\(job.settings.quality.title)", systemImage: job.mode.symbol)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(queue.cancelling.contains(job.id) ? "停止中…" : job.phase.title)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
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
                if result.savedFraction < 0 { Text("圧縮前よりファイル容量が増えました。").font(.caption).foregroundStyle(.secondary) }
            }
            if let message = job.message { Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                if job.result?.output != job.input.resolvingSymlinksInPath() {
                    IconControl(title: "入力ファイルをFinderに表示", symbol: "doc") { NSWorkspace.shared.activateFileViewerSelecting([job.input]) }
                }
                if let result = job.result {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([result.output]) } label: {
                        Label("圧縮した動画", systemImage: "folder")
                    }.capsuleControl(prominent: true).controlSize(.large)
                }
                Spacer()
                if job.phase == .waiting {
                    Label("ドラッグで並べ替え", systemImage: "line.3.horizontal")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !job.phase.isFinished {
                    IconControl(title: "圧縮をキャンセル", symbol: "xmark") { queue.cancel(job.id) }.disabled(queue.cancelling.contains(job.id))
                } else if job.phase != .completed {
                    IconControl(title: "再試行", symbol: "arrow.clockwise") { queue.retry(job.id) }
                }
            }.controlSize(.small)
        }
    }
    private func bytes(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
}

private extension UTType {
    static let notchQueueJob = UTType(exportedAs: "com.mani.NotchCompressor.queue-job", conformingTo: .data)
}

private struct QueueDropTarget: ViewModifier {
    @ObservedObject var queue: JobQueue
    let job: CompressionJob
    @Binding var draggingID: UUID?
    @State private var targeted = false
    private var movesDown: Bool {
        let ids = queue.waitingJobs.map(\.id)
        guard let source = draggingID.flatMap({ ids.firstIndex(of: $0) }), let target = ids.firstIndex(of: job.id) else { return false }
        return source < target
    }
    func body(content: Content) -> some View {
        content
            .overlay(alignment: movesDown ? .bottom : .top) {
                if targeted && draggingID != job.id {
                    Capsule().fill(Color.accentColor).frame(height: 3).padding(.horizontal, 8)
                }
            }
            .onDrop(of: [.notchQueueJob], delegate: QueueCardDrop(queue: queue, destination: job.id,
                                                               draggingID: $draggingID, targeted: $targeted))
    }
}

private struct QueueCardDrop: DropDelegate {
    let queue: JobQueue
    let destination: UUID
    @Binding var draggingID: UUID?
    @Binding var targeted: Bool
    func validateDrop(info: DropInfo) -> Bool {
        let supported = info.hasItemsConforming(to: [.notchQueueJob])
        guard supported, let source = draggingID else { return false }
        let waiting = queue.waitingJobs.map(\.id)
        return source != destination && waiting.contains(source) && waiting.contains(destination)
    }
    func dropEntered(info: DropInfo) {
        targeted = validateDrop(info: info)
        queueDragLog.info("queue drop entered accepted=\(targeted)")
    }
    func dropExited(info: DropInfo) { targeted = false }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: validateDrop(info: info) ? .move : .forbidden)
    }
    func performDrop(info: DropInfo) -> Bool {
        defer { targeted = false; draggingID = nil }
        guard validateDrop(info: info), let source = draggingID else { return false }
        queueDragLog.info("queue drop committed")
        return withAnimation(.easeInOut(duration: 0.18)) { queue.moveWaiting(source, to: destination) }
    }
}

private let queueDragLog = Logger(subsystem: "com.mani.NotchCompressor", category: "QueueReorder")
