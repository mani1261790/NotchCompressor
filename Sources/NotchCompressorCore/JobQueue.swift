import Foundation
import Combine

public struct CompressionJob: Identifiable, Codable, Sendable {
    public let id: UUID
    public let input: URL
    public let mode: CompressionMode
    public var mediaKind: MediaKind?
    public var effectiveMediaKind: MediaKind { mediaKind ?? .video }
    public var usesVisualEncoder: Bool { effectiveMediaKind != .audio && mode != .audio }
    public var modeTitle: String { effectiveMediaKind == .video ? mode.title : effectiveMediaKind.title }
    public var modeSymbol: String {
        effectiveMediaKind == .image ? "photo" : (effectiveMediaKind == .audio ? "waveform" : mode.symbol)
    }
    public var settingsSummary: String {
        if effectiveMediaKind == .image {
            return input.pathExtension.lowercased() == "png"
                ? L10n.text("image.pngLossless")
                : L10n.text("image.jpegQuality", L10n.integer(Int(settings.effectiveImageQuality)))
        }
        if effectiveMediaKind == .audio {
            return L10n.text("audio.settingsSummary", L10n.integer(settings.effectiveStandaloneAudioKbps))
        }
        return settings.summary(for: mode)
    }
    public let settings: CompressionSettings
    public let createdAt: Date
    public var phase: JobPhase
    public var progress: Double
    public var message: String?
    public var localizedMessage: LocalizedMessage?
    public var technicalDetails: String?
    public var displayMessage: String? {
        if let diskSpaceIssue { return diskSpaceIssue.errorDescription }
        if let localizedMessage { return localizedMessage.text }
        if let result { return result.completionMessage }
        return message == nil ? nil : L10n.text("history.legacy")
    }
    public var displayDetails: String? { technicalDetails ?? (localizedMessage == nil ? message ?? result?.note : nil) }

    public var result: CompressionResult?
    public var diskSpaceIssue: DiskSpaceIssue?
    public init(input: URL, mode: CompressionMode, settings: CompressionSettings, mediaKind: MediaKind? = nil) {
        self.mediaKind = mediaKind
        id = UUID(); self.input = input; self.mode = mode; self.settings = settings
        createdAt = Date(); phase = .waiting; progress = 0
    }
}

public struct QueueSnapshot: Codable {
    public var version = 1
    public var settings: CompressionSettings
    public var jobs: [CompressionJob]
    public var execution: QueueExecution?
    public init(settings: CompressionSettings, jobs: [CompressionJob], execution: QueueExecution? = nil) {
        self.settings = settings; self.jobs = jobs; self.execution = execution
    }
    public func recovered() -> [CompressionJob] {
        jobs.map { original in
            var job = original
            if !job.phase.isFinished {
                job.phase = .interrupted
                job.technicalDetails = job.technicalDetails ?? job.message
                job.message = nil
                job.localizedMessage = .init("history.interrupted")
                job.progress = 0
            }
            return job
        }
    }
}

@MainActor
public final class JobQueue: ObservableObject {
    public typealias Operation =
        @Sendable (URL, CompressionMode, CompressionSettings, @escaping @Sendable (JobPhase, Double, String?) -> Void)
        async throws -> CompressionResult
    @Published public private(set) var jobs: [CompressionJob] = []
    @Published public var settings: CompressionSettings = .init() { didSet { persist() } }
    @Published public private(set) var persistenceError: String?
    @Published public private(set) var persistenceDetails: String?
    @Published public private(set) var cancelling = Set<UUID>()
    @Published public private(set) var completionNotice: CompletionNotice?
    public let completionEvents = PassthroughSubject<CompressionResult, Never>()
    public let failureEvents = PassthroughSubject<FailureNotice, Never>()
    private var completionExpiry: Task<Void, Never>?
    private let feedbackDuration: Duration
    public var status: QueueStatus { QueueStatus(jobs: jobs, running: runningIDs, paused: pausedIDs) }

    public func dismissCompletion() {
        completionExpiry?.cancel()
        completionNotice = nil
    }

    private func recordCompletion(_ result: CompressionResult) {
        var notice = completionNotice ?? CompletionNotice()
        notice.include(result)
        completionNotice = notice
        completionEvents.send(result)
        completionExpiry?.cancel()
        completionExpiry = Task { [weak self, feedbackDuration] in
            do { try await Task.sleep(for: feedbackDuration) } catch { return }
            self?.completionNotice = nil
        }
    }

    private let storage: URL?
    private let operation: Operation
    @Published public var execution: QueueExecution = .automatic { didSet { persist(); startNext() } }
    @Published public private(set) var isPaused = false
    @Published public private(set) var environment: SchedulingEnvironment
    @Published public private(set) var runningIDs = Set<UUID>()
    private var workers: [UUID: Task<Void, Never>] = [:]
    private var activeOrder: [UUID] = []
    private var controls: [UUID: CompressionControl] = [:]
    private var resumedPhases: [UUID: JobPhase] = [:]
    @Published public private(set) var systemSleeping = false
    private var systemPausedIDs = Set<UUID>()
    private var userPausedIDs = Set<UUID>()
    private var recoveryChecks = Set<UUID>()
    private var recoveryFailures: [UUID: LocalizedMessage] = [:]
    private var removalRequests = Set<UUID>()
    @Published public private(set) var pausedIDs = Set<UUID>()
    private var activeResources: [UUID: String] = [:]
    private let readEnvironment: () -> SchedulingEnvironment
    private var resourceMonitor: AnyCancellable?
    private var accepting = true
    private var mayPersist = true

    public var pendingCount: Int { jobs.filter { !$0.phase.isFinished }.count }
    public var isBusy: Bool { pendingCount > 0 || !workers.isEmpty }
    public var runningCount: Int { runningIDs.subtracting(pausedIDs).count }
    public var waitingJobs: [CompressionJob] { jobs.filter { $0.phase == .waiting } }
    public func canReorder(_ id: UUID) -> Bool {
        guard !cancelling.contains(id),
            let job = jobs.first(where: { $0.id == id })
        else { return false }
        if pausedIDs.contains(id) { return true }
        guard workers[id] == nil, !runningIDs.contains(id) else { return false }
        return job.phase == .waiting || (job.phase.isFinished && job.phase != .completed)
    }
    public func canRemove(_ id: UUID) -> Bool { canReorder(id) }
    public var queuedJobs: [CompressionJob] { jobs.filter { canReorder($0.id) } }
    public var displayedJobs: [CompressionJob] {
        // Running cards retain start order; completed results remain only in bounded storage.
        activeOrder.compactMap { id in
            jobs.first { $0.id == id && $0.phase != .completed && (!pausedIDs.contains(id) || cancelling.contains(id)) }
        } + queuedJobs
    }
    public var schedulingDescription: String {
        if systemSleeping { return L10n.text("schedule.sleep") }
        if isPaused {
            if !pausedIDs.isEmpty { return L10n.text("schedule.pausedSession") }
            if !cancelling.isEmpty { return L10n.text("schedule.stopping") }
            return runningCount > 0 ? L10n.text("schedule.newPaused") : L10n.text("schedule.waitResume")
        }
        if !pausedIDs.isEmpty { return L10n.text("schedule.hold") }
        switch execution {
        case .serial: return L10n.text("schedule.serialDetail")
        case .parallel: return L10n.text("schedule.parallelDetail")
        case .automatic:
            return environment.conservesResources ? L10n.text("schedule.conserve") : L10n.text("schedule.autoDetail")
        }
    }

    public init(
        storage: URL? = nil,
        feedbackDuration: Duration = .seconds(8),
        environment: @escaping () -> SchedulingEnvironment = { .current },
        operation: @escaping Operation = { url, mode, settings, update in
            try await CompressionEngine().compress(input: url, mode: mode, settings: settings, update: update)
        }
    ) {
        self.feedbackDuration = feedbackDuration
        self.storage = storage
        self.operation = operation
        self.readEnvironment = environment
        self.environment = environment()
        if let storage, FileManager.default.fileExists(atPath: storage.path) {
            do {
                let snapshot = try JSONDecoder().decode(QueueSnapshot.self, from: Data(contentsOf: storage))
                guard snapshot.version == 1 else { throw CompressionError.localized(.init("error.historyVersion")) }
                settings = snapshot.settings
                execution = snapshot.execution ?? .automatic
                jobs = snapshot.recovered()
            } catch {
                mayPersist = false
                persistenceError = L10n.text("history.loadError")
                persistenceDetails = error.localizedDescription
            }
        }
        resourceMonitor = Timer.publish(every: 5, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.refreshEnvironment()
        }
        persist()
    }

    public func refreshEnvironment() {
        let current = readEnvironment()
        if current != environment { environment = current; startNext() }
    }

    public func togglePause() {
        isPaused.toggle()
        if !isPaused { startNext() }
    }

    /// Reorder only inactive cards. Running and stopping workers are immutable anchors.
    @discardableResult
    public func moveQueued(_ id: UUID, to destination: UUID) -> Bool {
        guard id != destination, canReorder(id), canReorder(destination),
            let source = jobs.firstIndex(where: { $0.id == id }),
            let target = jobs.firstIndex(where: { $0.id == destination })
        else { return false }
        let job = jobs.remove(at: source)
        jobs.insert(job, at: target)
        persist()
        startNext()
        return true
    }

    @discardableResult
    public func enqueue(
        _ urls: [URL], mode: CompressionMode, mediaKind: MediaKind? = nil, settings snapshot: CompressionSettings? = nil
    ) -> Int {
        guard accepting else { return 0 }
        var added = 0
        for url in urls {
            let source = url.standardizedFileURL.resolvingSymlinksInPath()
            guard !jobs.contains(where: { $0.input == source && $0.mode == mode && !$0.phase.isFinished }) else {
                continue
            }
            jobs.append(CompressionJob(input: source, mode: mode, settings: snapshot ?? settings, mediaKind: mediaKind))
            added += 1
        }
        trimHistory()
        persist()
        startNext()
        return added
    }

    public func pause(_ id: UUID) {
        guard !cancelling.contains(id), !userPausedIDs.contains(id),
            let index = jobs.firstIndex(where: { $0.id == id }),
            !jobs[index].phase.isFinished, let control = controls[id], control.pause()
        else { return }
        userPausedIDs.insert(id)
        if !pausedIDs.contains(id) { resumedPhases[id] = jobs[index].phase }
        jobs[index].phase = .paused
        pausedIDs.insert(id)
        let job = jobs.remove(at: index)
        jobs.insert(job, at: 0)
        persist()
    }

    public func resume(_ id: UUID) {
        guard userPausedIDs.contains(id), !cancelling.contains(id) else { return }
        if !systemSleeping, !checkRecovery(id) { return }
        guard controls[id]?.resume() == true else {
            failRecovery(id, message: .init("error.resume"))
            return
        }
        userPausedIDs.remove(id)
        restorePhaseIfRunning(id)
        persist()
    }

    private func restorePhaseIfRunning(_ id: UUID) {
        guard !userPausedIDs.contains(id), !systemPausedIDs.contains(id),
            let index = jobs.firstIndex(where: { $0.id == id })
        else { return }
        jobs[index].phase = resumedPhases.removeValue(forKey: id) ?? .encoding
        pausedIDs.remove(id)
    }

    public func prepareForSystemSleep() {
        guard !systemSleeping else { return }
        systemSleeping = true  // Close dispatch before suspending any worker.
        for id in activeOrder where !cancelling.contains(id) {
            guard let control = controls[id], !control.hasCommitted,
                let index = jobs.firstIndex(where: { $0.id == id })
            else { continue }
            guard control.pause(.systemSleep) else {
                if !control.hasCommitted {
                    failRecovery(id, message: .init("error.sleepPause"))
                }
                continue
            }
            if !pausedIDs.contains(id) { resumedPhases[id] = jobs[index].phase }
            systemPausedIDs.insert(id)
            recoveryChecks.insert(id)
            jobs[index].phase = .paused
            pausedIDs.insert(id)
        }
        persist()
    }

    public func resumeAfterSystemSleep() {
        guard systemSleeping else { return }
        // Keep dispatch closed until all existing workers have been handled.
        for id in Array(systemPausedIDs) where !cancelling.contains(id) {
            if !userPausedIDs.contains(id), !checkRecovery(id) { continue }
            guard controls[id]?.resume(.systemSleep) == true else {
                failRecovery(id, message: .init("error.wakeResume"))
                continue
            }
            systemPausedIDs.remove(id)
            restorePhaseIfRunning(id)
        }
        systemSleeping = false
        persist()
        startNext()
    }

    private func checkRecovery(_ id: UUID) -> Bool {
        guard recoveryChecks.contains(id), let job = jobs.first(where: { $0.id == id }) else { return true }
        let fm = FileManager.default
        guard fm.isReadableFile(atPath: job.input.path),
            fm.isWritableFile(atPath: job.input.deletingLastPathComponent().path)
        else {
            failRecovery(id, message: .init("error.wakeStorage"))
            return false
        }
        recoveryChecks.remove(id)
        return true
    }

    private func failRecovery(_ id: UUID, message: LocalizedMessage) {
        recoveryFailures[id] = message
        cancel(id)
    }

    public func pauseAll() {
        isPaused = true
        for id in activeOrder { pause(id) }
    }

    public func resumeAll() {
        for id in Array(pausedIDs) { resume(id) }
        isPaused = false
        startNext()
    }

    public func cancel(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), !jobs[index].phase.isFinished else { return }
        if let worker = workers[id] {
            cancelling.insert(id)
            worker.cancel()
        } else {
            jobs[index].phase = .cancelled
            jobs[index].localizedMessage = .init("queue.cancelledWaiting")
        }
        persist()
        startNext()
    }

    /// Removing a card never deletes its source or output file.
    @discardableResult
    public func remove(_ id: UUID) -> Bool {
        guard canRemove(id) else { return false }
        if workers[id] != nil {
            removalRequests.insert(id)
            cancel(id)
            return true
        }
        jobs.removeAll { $0.id == id }
        persist()
        startNext()
        return true
    }

    public func stopAll() {
        // Close the scheduling gate before cancelling any worker.
        isPaused = true
        for id in Array(workers.keys) { cancel(id) }
    }

    public func retry(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }), job.phase.isFinished else { return }
        enqueue([job.input], mode: job.mode, mediaKind: job.mediaKind)
    }

    public func clearFinished() {
        let removable = Set(
            jobs.filter { $0.phase.isFinished && workers[$0.id] == nil && !runningIDs.contains($0.id) }.map(\.id))
        jobs.removeAll { removable.contains($0.id) }
        persist()
    }

    public func stopForTermination() async {
        accepting = false
        for id in jobs.filter({ !$0.phase.isFinished }).map(\.id) { cancel(id) }
        await waitUntilIdle()
    }

    public func waitUntilIdle() async {
        while let task = workers.values.first { await task.value }
    }

    // Inode + volume also catches hard links; re-read at dispatch after earlier replacements.
    private func resourceKey(_ url: URL) -> String {
        if let values = try? FileManager.default.attributesOfItem(atPath: url.path),
            let inode = values[.systemFileNumber] as? NSNumber,
            let volume = values[.systemNumber] as? NSNumber
        {
            return "\(volume):\(inode)"
        }
        return url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func startNext() {
        guard accepting, !isPaused, !systemSleeping else { return }
        environment = readEnvironment()
        let limit = execution == .serial || (execution == .automatic && environment.conservesResources) ? 1 : 2
        while workers.count < limit {
            let activePaths = Set(jobs.filter { runningIDs.contains($0.id) }.map { $0.input.path })
            let videoActive = jobs.contains { runningIDs.contains($0.id) && $0.usesVisualEncoder }
            guard
                let job = waitingJobs.first(where: {
                    !activePaths.contains($0.input.path)
                        && !activeResources.values.contains(resourceKey($0.input))
                        && !(execution == .automatic && videoActive && $0.usesVisualEncoder)
                })
            else { break }
            launch(job)
        }
    }

    private func launch(_ job: CompressionJob) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs[index].phase = .probing
        activeOrder.append(job.id)
        runningIDs.insert(job.id)
        activeResources[job.id] = resourceKey(job.input)
        let control = CompressionControl()
        controls[job.id] = control
        workers[job.id] = Task { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                let result = try await CompressionControl.$current.withValue(control) {
                    try await MediaInputContext.$expectedKind.withValue(job.effectiveMediaKind) {
                        try await self.operation(job.input, job.mode, job.settings) {
                            [weak self] phase, progress, note in
                            Task { @MainActor in
                                guard let self, self.runningIDs.contains(job.id), !self.pausedIDs.contains(job.id),
                                    !self.cancelling.contains(job.id),
                                    let index = self.jobs.firstIndex(where: { $0.id == job.id }),
                                    !self.jobs[index].phase.isFinished
                                else { return }
                                let changedPhase = self.jobs[index].phase != phase
                                self.jobs[index].phase = phase
                                self.jobs[index].progress = progress
                                self.jobs[index].localizedMessage =
                                    ["note.silent", "note.sleepRetry"].first(where: { note == L10n.text($0) }).map {
                                        .init($0)
                                    }
                                self.jobs[index].message = self.jobs[index].localizedMessage == nil ? note : nil
                                if changedPhase { self.persist() }
                            }
                        }
                    }
                }
                try await control.checkpoint()
                if let index = jobs.firstIndex(where: { $0.id == job.id }) {
                    jobs[index].phase = .completed
                    jobs[index].progress = 1
                    jobs[index].result = result
                    jobs[index].localizedMessage =
                        result.effectiveOutcome == .originalKept ? .init("result.originalKept") : result.noteMessage
                    jobs[index].message = nil
                    recordCompletion(result)
                }
            } catch {
                let error: Error = recoveryFailures[job.id].map { CompressionError.localized($0) } ?? error
                if let index = jobs.firstIndex(where: { $0.id == job.id }) {
                    jobs[index].diskSpaceIssue = DiskSpaceIssue.classify(error)
                    jobs[index].phase = error is CancellationError ? .cancelled : .failed
                    jobs[index].localizedMessage =
                        error is CancellationError
                        ? .init("queue.cancelled")
                        : (error as? CompressionError)?.localizedMessage ?? .init("error.generic")
                    jobs[index].technicalDetails =
                        error is CancellationError
                        ? nil
                        : (error as? CompressionError)?.technicalDetails
                            ?? (error is CompressionError || error is DiskSpaceIssue ? nil : error.localizedDescription)
                    jobs[index].message = nil
                    if !(error is CancellationError) {
                        failureEvents.send(FailureNotice(diskSpaceIssue: jobs[index].diskSpaceIssue))
                    }
                    if error is CancellationError {
                        // Keep the stopped card visible above inactive cards instead of
                        // returning it to its old enqueue position below the viewport.
                        let stopped = jobs.remove(at: index)
                        jobs.insert(stopped, at: 0)
                    }
                }
            }
            systemPausedIDs.remove(job.id)
            userPausedIDs.remove(job.id)
            recoveryChecks.remove(job.id)
            recoveryFailures.removeValue(forKey: job.id)
            pausedIDs.remove(job.id)
            resumedPhases.removeValue(forKey: job.id)
            controls.removeValue(forKey: job.id)
            if removalRequests.remove(job.id) != nil { jobs.removeAll { $0.id == job.id } }
            cancelling.remove(job.id)
            activeResources.removeValue(forKey: job.id)
            activeOrder.removeAll { $0 == job.id }
            runningIDs.remove(job.id)
            workers.removeValue(forKey: job.id)
            trimHistory()
            persist()
            startNext()
        }
        persist()
    }

    private func trimHistory() {
        let finished = jobs.filter { $0.phase == .completed && workers[$0.id] == nil && !runningIDs.contains($0.id) }
        let remove = Set(finished.prefix(max(0, finished.count - 100)).map(\.id))
        jobs.removeAll { remove.contains($0.id) }
    }

    private func persist() {
        guard let storage, mayPersist else { return }
        do {
            try FileManager.default.createDirectory(
                at: storage.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(QueueSnapshot(settings: settings, jobs: jobs, execution: execution))
            try data.write(to: storage, options: .atomic)
            persistenceError = nil
            persistenceDetails = nil
        } catch {
            persistenceError = L10n.text("history.saveError")
            persistenceDetails = error.localizedDescription
        }
    }
}
