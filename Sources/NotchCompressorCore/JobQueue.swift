import Foundation
import Combine

public struct CompressionJob: Identifiable, Codable, Sendable {
    public let id: UUID
    public let input: URL
    public let mode: CompressionMode
    public let settings: CompressionSettings
    public let createdAt: Date
    public var phase: JobPhase
    public var progress: Double
    public var message: String?
    public var result: CompressionResult?
    public init(input: URL, mode: CompressionMode, settings: CompressionSettings) {
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
                job.message = "前回の処理は完了していません。元ファイルは保持されています。必要なら再試行してください。一時出力が元のフォルダに残っている場合があります。"
                job.progress = 0
            }
            return job
        }
    }
}

@MainActor
public final class JobQueue: ObservableObject {
    public typealias Operation = @Sendable (URL, CompressionMode, CompressionSettings, @escaping @Sendable (JobPhase, Double, String?) -> Void) async throws -> CompressionResult
    @Published public private(set) var jobs: [CompressionJob] = []
    @Published public var settings: CompressionSettings = .init() { didSet { persist() } }
    @Published public private(set) var persistenceError: String?
    @Published public private(set) var cancelling = Set<UUID>()
    private let storage: URL?
    private let operation: Operation
    @Published public var execution: QueueExecution = .automatic { didSet { persist(); startNext() } }
    @Published public private(set) var isPaused = false
    @Published public private(set) var environment: SchedulingEnvironment
    @Published public private(set) var runningIDs = Set<UUID>()
    private var workers: [UUID: Task<Void, Never>] = [:]
    private var activeOrder: [UUID] = []
    private var activeResources: [UUID: String] = [:]
    private let readEnvironment: () -> SchedulingEnvironment
    private var resourceMonitor: AnyCancellable?
    private var accepting = true
    private var mayPersist = true

    public var pendingCount: Int { jobs.filter { !$0.phase.isFinished }.count }
    public var isBusy: Bool { pendingCount > 0 || !workers.isEmpty }
    public var runningCount: Int { runningIDs.count }
    public var waitingJobs: [CompressionJob] { jobs.filter { $0.phase == .waiting } }
    public func canReorder(_ id: UUID) -> Bool {
        guard workers[id] == nil, !runningIDs.contains(id), !cancelling.contains(id),
              let job = jobs.first(where: { $0.id == id }) else { return false }
        return job.phase == .waiting || (job.phase.isFinished && job.phase != .completed)
    }
    public func canRemove(_ id: UUID) -> Bool { canReorder(id) }
    public var queuedJobs: [CompressionJob] { jobs.filter { canReorder($0.id) } }
    public var displayedJobs: [CompressionJob] {
        // Running cards retain start order; completed results remain only in bounded storage.
        activeOrder.compactMap { id in jobs.first { $0.id == id && $0.phase != .completed } } + queuedJobs
    }
    public var schedulingDescription: String {
        if isPaused {
            if !cancelling.isEmpty { return "圧縮を停止しています。次の処理は開始しません" }
            return runningCount > 0 ? "新しい処理を一時停止中・実行中の動画は続行します" : "待機中の動画は再開すると処理を開始します"
        }
        switch execution {
        case .serial: return "キューの上から1件ずつ処理"
        case .parallel: return "最大2件を並列処理・同じ元動画は順番に処理"
        case .automatic:
            return environment.conservesResources ? "省電力・発熱・構成に合わせ、新しい処理は1件まで" : "最大2件・映像圧縮は1件まで、音質のみは併走可能"
        }
    }

    public init(storage: URL? = nil,
                environment: @escaping () -> SchedulingEnvironment = { .current },
                operation: @escaping Operation = { url, mode, settings, update in
        try await CompressionEngine().compress(input: url, mode: mode, settings: settings, update: update)
    }) {
        self.storage = storage
        self.operation = operation
        self.readEnvironment = environment
        self.environment = environment()
        if let storage, FileManager.default.fileExists(atPath: storage.path) {
            do {
                let snapshot = try JSONDecoder().decode(QueueSnapshot.self, from: Data(contentsOf: storage))
                guard snapshot.version == 1 else { throw CompressionError.message("未対応の履歴形式です。") }
                settings = snapshot.settings
                execution = snapshot.execution ?? .automatic
                jobs = snapshot.recovered()
            } catch {
                mayPersist = false
                persistenceError = "履歴を読み込めませんでした。既存の履歴ファイルは保持しています。この起動中の変更は保存されません。\n\(error.localizedDescription)"
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
              let target = jobs.firstIndex(where: { $0.id == destination }) else { return false }
        let job = jobs.remove(at: source)
        jobs.insert(job, at: target)
        persist()
        startNext()
        return true
    }

    @discardableResult
    public func enqueue(_ urls: [URL], mode: CompressionMode) -> Int {
        guard accepting else { return 0 }
        var added = 0
        for url in urls {
            let source = url.standardizedFileURL.resolvingSymlinksInPath()
            guard !jobs.contains(where: { $0.input == source && $0.mode == mode && !$0.phase.isFinished }) else { continue }
            jobs.append(CompressionJob(input: source, mode: mode, settings: settings))
            added += 1
        }
        trimHistory()
        persist()
        startNext()
        return added
    }

    public func cancel(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), !jobs[index].phase.isFinished else { return }
        if let worker = workers[id] {
            cancelling.insert(id)
            worker.cancel()
        } else {
            jobs[index].phase = .cancelled
            jobs[index].message = "待機中にキャンセルしました。"
        }
        persist()
        startNext()
    }

    /// Removing a card never deletes its source or output file.
    @discardableResult
    public func remove(_ id: UUID) -> Bool {
        guard canRemove(id) else { return false }
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
        enqueue([job.input], mode: job.mode)
    }

    public func clearFinished() {
        let removable = Set(jobs.filter { $0.phase.isFinished && workers[$0.id] == nil && !runningIDs.contains($0.id) }.map(\.id))
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
           let volume = values[.systemNumber] as? NSNumber {
            return "\(volume):\(inode)"
        }
        return url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func startNext() {
        guard accepting, !isPaused else { return }
        environment = readEnvironment()
        let limit = execution == .serial || (execution == .automatic && environment.conservesResources) ? 1 : 2
        while workers.count < limit {
            let activePaths = Set(jobs.filter { runningIDs.contains($0.id) }.map { $0.input.path })
            let videoActive = jobs.contains { runningIDs.contains($0.id) && $0.mode != .audio }
            guard let job = waitingJobs.first(where: {
                !activePaths.contains($0.input.path)
                && !activeResources.values.contains(resourceKey($0.input))
                && !(execution == .automatic && videoActive && $0.mode != .audio)
            }) else { break }
            launch(job)
        }
    }

    private func launch(_ job: CompressionJob) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs[index].phase = .probing
        activeOrder.append(job.id)
        runningIDs.insert(job.id)
        activeResources[job.id] = resourceKey(job.input)
        workers[job.id] = Task { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                let result = try await operation(job.input, job.mode, job.settings) { [weak self] phase, progress, note in
                    Task { @MainActor in
                        guard let self, self.runningIDs.contains(job.id),
                              let index = self.jobs.firstIndex(where: { $0.id == job.id }), !self.jobs[index].phase.isFinished else { return }
                        let changedPhase = self.jobs[index].phase != phase
                        self.jobs[index].phase = phase
                        self.jobs[index].progress = progress
                        self.jobs[index].message = note
                        if changedPhase { self.persist() }
                    }
                }
                if let index = jobs.firstIndex(where: { $0.id == job.id }) {
                    jobs[index].phase = .completed
                    jobs[index].progress = 1
                    jobs[index].result = result
                    jobs[index].message = result.note
                }
            } catch {
                if let index = jobs.firstIndex(where: { $0.id == job.id }) {
                    jobs[index].phase = error is CancellationError ? .cancelled : .failed
                    jobs[index].message = error is CancellationError ? "処理を停止しました。元ファイルは保持しています。" : error.localizedDescription
                    if error is CancellationError {
                        // Keep the stopped card visible above inactive cards instead of
                        // returning it to its old enqueue position below the viewport.
                        let stopped = jobs.remove(at: index)
                        jobs.insert(stopped, at: 0)
                    }
                }
            }
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
            try FileManager.default.createDirectory(at: storage.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(QueueSnapshot(settings: settings, jobs: jobs, execution: execution))
            try data.write(to: storage, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = "履歴を保存できませんでした。\n\(error.localizedDescription)"
        }
    }
}
