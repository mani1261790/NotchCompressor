import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OSLog
import NotchCompressorCore

struct QueueView: View {
    @ObservedObject var queue: JobQueue
    @ObservedObject var app: AppState
    @State private var draggingJobID: UUID?
    @State private var showingQueueHelp = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.text("queue.title")).font(.title2.weight(.semibold))
                    if queue.pendingCount > 0 {
                        Text(
                            L10n.text(
                                "queue.counts", L10n.integer(queue.runningCount),
                                L10n.integer(queue.pausedIDs.count), L10n.integer(queue.waitingJobs.count))
                        )
                        .font(.callout).foregroundStyle(.secondary)
                    } else if queue.displayedJobs.isEmpty {
                        Text(L10n.text("queue.dragHint")).font(.callout).foregroundStyle(.secondary)
                    }
                    let attentionCount = queue.displayedJobs.filter { $0.phase.isFinished }.count
                    if attentionCount > 0 {
                        Label(
                            L10n.text("queue.needsAttention", L10n.integer(attentionCount)),
                            systemImage: "exclamationmark.circle"
                        )
                        .font(.caption).foregroundStyle(.orange)
                    }
                }
                Spacer()
                Menu {
                    ForEach(CompressionMode.allCases) { mode in
                        Button {
                            app.chooseVideos(mode: mode)
                        } label: {
                            Label(mode.selectionTitle, systemImage: mode.selectionSymbol)
                        }
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
                .help(L10n.text("queue.addHelp")).accessibilityLabel(L10n.text("queue.add"))
                IconControl(title: L10n.text("ui.settings"), symbol: "gearshape") { app.settingsPresented = true }
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Menu {
                        Picker(L10n.text("queue.execution"), selection: $queue.execution) {
                            ForEach(QueueExecution.allCases) { mode in Text(mode.title).tag(mode) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Label(queue.execution.title, systemImage: "slider.horizontal.3")
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                        }
                    }.capsuleMenu().accessibilityLabel(L10n.text("queue.executionValue", queue.execution.title))
                    Spacer()
                    IconControl(title: L10n.text("queue.help"), symbol: "info") {
                        showingQueueHelp.toggle()
                    }
                    .popover(isPresented: $showingQueueHelp) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.text("queue.help")).font(.headline)
                            Text(queue.schedulingDescription)
                            Text(L10n.text("queue.orderHelp"))
                            Text(L10n.text("queue.background"))
                            Text(L10n.text("queue.sleepHelp"))
                        }
                        .font(.callout).padding(20).frame(width: 320)
                    }
                }
                if !queue.pausedIDs.isEmpty || queue.systemSleeping {
                    Label(queue.schedulingDescription, systemImage: "pause.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 24).padding(.bottom, 12)
            Divider()
            if let notice = queue.completionNotice {
                HStack {
                    Label(notice.text, systemImage: "checkmark.circle")
                        .font(.callout).accessibilityLabel(notice.text)
                    Spacer()
                    IconControl(title: L10n.text("queue.dismissResult"), symbol: "xmark") { queue.dismissCompletion() }
                }.padding(.horizontal, 24).padding(.vertical, 12)
            }
            if app.importingCount > 0 {
                ProgressView(L10n.text("input.inspecting")).controlSize(.small).padding()
            }
            if !app.rejectedInputs.isEmpty {
                HStack(alignment: .top) {
                    DisclosureGroup(L10n.text("input.rejected", L10n.integer(app.rejectedInputs.count))) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(app.rejectedInputs.enumerated()), id: \.offset) { _, rejection in
                                    VStack(alignment: .leading) {
                                        Text(rejection.url.lastPathComponent).fontWeight(.medium)
                                        Text(rejection.reason.text).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }.font(.caption).textSelection(.enabled)
                        }.frame(maxHeight: 120)
                    }
                    IconControl(title: L10n.text("ui.close"), symbol: "xmark") { app.rejectedInputs = [] }
                }.padding(.horizontal, 24).padding(.vertical, 8)
            }
            if let error = app.dropError {
                HStack {
                    Text(error).font(.callout); Spacer();
                    IconControl(title: L10n.text("ui.close"), symbol: "xmark") { app.dropError = nil }
                }.padding()
            }
            if let error = queue.persistenceError {
                Text(error).font(.caption).foregroundStyle(.orange).padding()
                if let details = queue.persistenceDetails {
                    DisclosureGroup(L10n.text("details.technical")) {
                        Text(details).font(.caption).textSelection(.enabled)
                    }.padding(.horizontal)
                }
            }
            if (try? Toolchain.discover(directory: queue.settings.toolsDirectory)) == nil {
                HStack {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(L10n.text("queue.missingEngine"))
                    Spacer()
                }.padding()
            }
            if queue.displayedJobs.isEmpty {
                VStack(spacing: 18) {
                    Image(systemName: "arrow.up.document").font(.system(size: 38, weight: .light)).foregroundStyle(
                        .secondary)
                    Text(L10n.text("queue.dropChoice")).font(.headline)
                    HStack(spacing: 24) {
                        ForEach(CompressionMode.allCases) { mode in
                            Label(mode.selectionTitle, systemImage: mode.selectionSymbol).font(.callout)
                        }
                    }.foregroundStyle(.secondary)
                    Text(L10n.text("queue.zones")).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(queue.displayedJobs) { job in
                            if queue.canReorder(job.id) {
                                card(job)
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
                Text(L10n.text("queue.replaceHint"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if queue.displayedJobs.contains(where: { $0.phase.isFinished }) {
                    IconControl(title: L10n.text("queue.clear"), symbol: "clock.badge.xmark") { queue.clearFinished() }
                        .help(L10n.text("queue.clearHelp"))
                }
            }.padding(16)
        }
        .sheet(isPresented: $app.settingsPresented) { SettingsView(queue: queue) }
    }
    private func card(_ job: CompressionJob) -> some View {
        JobRow(job: job, queue: queue, draggingID: $draggingJobID)
            .padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.06)))
    }

}

private struct JobRow: View {
    let job: CompressionJob
    @ObservedObject var queue: JobQueue
    @Binding var draggingID: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: queue.canReorder(job.id) ? "line.3.horizontal" : "pin.fill")
                        .font(.caption).foregroundStyle(.tertiary)
                        .help(L10n.text(queue.canReorder(job.id) ? "queue.reorder" : "queue.pinned"))
                        .accessibilityLabel(L10n.text(queue.canReorder(job.id) ? "queue.reorder" : "queue.pinned"))
                    VideoThumbnail(urls: [job.result?.output, job.input].compactMap { $0 })
                    VStack(alignment: .leading, spacing: 5) {
                        Text(job.input.lastPathComponent).font(.headline).lineLimit(2)
                            .help(job.input.lastPathComponent)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 6) {
                                Label(job.modeTitle, systemImage: job.modeSymbol)
                                Text("·").accessibilityHidden(true)
                                InputFileSize(url: job.input)
                            }.fixedSize()
                            VStack(alignment: .leading, spacing: 3) {
                                Label(job.modeTitle, systemImage: job.modeSymbol)
                                InputFileSize(url: job.input)
                            }
                        }.font(.caption).foregroundStyle(.secondary)
                        Text(queue.cancelling.contains(job.id) ? L10n.text("queue.stopping") : job.phase.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(job.phase == .failed ? Color.orange : Color.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
                .accessibilityActions {
                    if let previous = reorderNeighbor(offset: -1) {
                        Button(L10n.text("queue.moveEarlier")) { queue.moveQueued(job.id, to: previous) }
                    }
                    if let next = reorderNeighbor(offset: 1) {
                        Button(L10n.text("queue.moveLater")) { queue.moveQueued(job.id, to: next) }
                    }
                }
                .modifier(
                    QueueDragSource(
                        jobID: job.id, enabled: queue.canReorder(job.id), draggingID: $draggingID))
                HStack(spacing: 4) {
                    if queue.pausedIDs.contains(job.id) {
                        IconControl(title: L10n.text("queue.resume"), symbol: "play.fill") { queue.resume(job.id) }
                            .disabled(queue.cancelling.contains(job.id))
                        IconControl(title: L10n.text("queue.removePaused"), symbol: "xmark") { queue.remove(job.id) }
                            .disabled(!queue.canRemove(job.id))
                    } else if queue.runningIDs.contains(job.id) {
                        IconControl(title: L10n.text("queue.pause"), symbol: "pause.fill") { queue.pause(job.id) }
                            .disabled(queue.cancelling.contains(job.id))
                    } else {
                        if job.phase.isFinished && job.phase != .completed {
                            IconControl(title: L10n.text("queue.retry"), symbol: "arrow.clockwise") {
                                queue.retry(job.id)
                            }
                        }
                        IconControl(title: L10n.text("queue.remove"), symbol: "xmark") { queue.remove(job.id) }
                            .disabled(!queue.canRemove(job.id))
                    }
                }.fixedSize()
            }
            if job.effectiveMediaKind == .image && job.phase == .encoding {
                ProgressView().controlSize(.small)
            } else if job.effectiveMediaKind != .image && (job.phase == .encoding || job.phase == .paused) {
                HStack(spacing: 12) {
                    ProgressView(value: job.progress)
                    Text(L10n.text("queue.percent", L10n.integer(Int(job.progress * 100))))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .fixedSize()
                }
            } else if [.probing, .validating].contains(job.phase) {
                ProgressView().controlSize(.small)
            }
            if let result = job.result {
                HStack {
                    Text("\(bytes(result.originalBytes)) → \(bytes(result.outputBytes))")
                    Text(
                        result.savedFraction >= 0
                            ? L10n.text("queue.saved", L10n.integer(Int(result.savedFraction * 100)))
                            : L10n.text("queue.grew", L10n.integer(Int(-result.savedFraction * 100)))
                    )
                    .foregroundStyle(result.savedFraction >= 0 ? Color.green : Color.orange)
                }.font(.callout)
                if result.effectiveOutcome == .originalKept {
                    Text(result.completionMessage ?? "").font(.caption).foregroundStyle(.secondary)
                }
                if result.savedFraction < 0 {
                    Text(L10n.text("queue.larger")).font(.caption).foregroundStyle(.secondary)
                }
            }
            if job.phase == .paused {
                Text(L10n.text("queue.pausedHint"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = job.displayMessage {
                Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if job.diskSpaceIssue != nil {
                Button {
                    NSWorkspace.shared.open(job.input.resolvingSymlinksInPath().deletingLastPathComponent())
                } label: {
                    Label(L10n.text("queue.openFolder"), systemImage: "externaldrive")
                }.capsuleControl()
            }
            DisclosureGroup(L10n.text("queue.compressionDetails")) {
                Text(job.settingsSummary)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([job.result?.output ?? job.input])
                } label: {
                    Label(L10n.text("queue.revealInput"), systemImage: "folder")
                }.capsuleControl()
            }.font(.caption)
            if let details = job.displayDetails, !details.isEmpty {
                DisclosureGroup(L10n.text("details.technical")) {
                    Text(details).font(.caption).textSelection(.enabled)
                }
            }

        }
    }
    private func reorderNeighbor(offset: Int) -> UUID? {
        let ids = queue.queuedJobs.map(\.id)
        guard let index = ids.firstIndex(of: job.id), ids.indices.contains(index + offset) else { return nil }
        return ids[index + offset]
    }
    private func bytes(_ count: Int64) -> String { L10n.bytes(count) }
}

private extension UTType {
    static let notchQueueJob = UTType(exportedAs: "com.mani.NotchCompressor.queue-job", conformingTo: .data)
}

/// Keep the draggable surface identical to the hand-cursor surface. Controls and
/// selectable details remain outside this modifier so they cannot start a reorder.
private struct QueueDragSource: ViewModifier {
    let jobID: UUID
    let enabled: Bool
    @Binding var draggingID: UUID?

    func body(content: Content) -> some View {
        if enabled {
            content
                .modifier(ReorderCursor(enabled: enabled))
                .onDrag {
                    draggingID = jobID
                    queueDragLog.info("queue drag began")
                    return NSItemProvider(
                        item: Data(jobID.uuidString.utf8) as NSData,
                        typeIdentifier: UTType.notchQueueJob.identifier)
                }
        } else {
            content
        }
    }
}

private struct QueueDropTarget: ViewModifier {
    @ObservedObject var queue: JobQueue
    let job: CompressionJob
    @Binding var draggingID: UUID?
    @State private var targeted = false
    private var movesDown: Bool {
        let ids = queue.queuedJobs.map(\.id)
        guard let source = draggingID.flatMap({ ids.firstIndex(of: $0) }), let target = ids.firstIndex(of: job.id)
        else { return false }
        return source < target
    }
    func body(content: Content) -> some View {
        content
            .overlay(alignment: movesDown ? .bottom : .top) {
                if targeted && draggingID != job.id {
                    Capsule().fill(Color.accentColor).frame(height: 3).padding(.horizontal, 8)
                }
            }
            .onDrop(
                of: [.notchQueueJob],
                delegate: QueueCardDrop(
                    queue: queue, destination: job.id,
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
        return source != destination && queue.canReorder(source) && queue.canReorder(destination)
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
        return withAnimation(.easeInOut(duration: 0.18)) { queue.moveQueued(source, to: destination) }
    }
}

private let queueDragLog = Logger(subsystem: "com.mani.NotchCompressor", category: "QueueReorder")

/// Apply only to reorderable rows; balance cursor ownership when a row starts
/// running or disappears after completion/removal while the pointer is over it.
private struct ReorderCursor: ViewModifier {
    let enabled: Bool
    @State private var ownsCursor = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside && enabled && !ownsCursor {
                    NSCursor.openHand.push()
                    ownsCursor = true
                } else if (!inside || !enabled) && ownsCursor {
                    NSCursor.pop()
                    ownsCursor = false
                }
            }
            .onChange(of: enabled) { _, enabled in
                if !enabled && ownsCursor {
                    NSCursor.pop()
                    ownsCursor = false
                }
            }
            .onDisappear {
                if ownsCursor {
                    NSCursor.pop()
                    ownsCursor = false
                }
            }
    }
}
