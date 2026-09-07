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
    public init(settings: CompressionSettings, jobs: [CompressionJob]) { self.settings = settings; self.jobs = jobs }
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
    private var worker: Task<Void, Never>?
    private var activeID: UUID?
    private var accepting = true
    private var mayPersist = true

    public var pendingCount: Int { jobs.filter { !$0.phase.isFinished }.count }
    public var isBusy: Bool { pendingCount > 0 || worker != nil }

    public init(storage: URL? = nil, operation: @escaping Operation = { url, mode, settings, update in
        try await CompressionEngine().compress(input: url, mode: mode, settings: settings, update: update)
    }) {
        self.storage = storage
        self.operation = operation
        if let storage, FileManager.default.fileExists(atPath: storage.path) {
            do {
                let snapshot = try JSONDecoder().decode(QueueSnapshot.self, from: Data(contentsOf: storage))
                guard snapshot.version == 1 else { throw CompressionError.message("未対応の履歴形式です。") }
                settings = snapshot.settings
                jobs = snapshot.recovered()
            } catch {
                mayPersist = false
                persistenceError = "履歴を読み込めませんでした。既存の履歴ファイルは保持しています。この起動中の変更は保存されません。\n\(error.localizedDescription)"
            }
        }
        persist()
    }

    @discardableResult
    public func enqueue(_ urls: [URL], mode: CompressionMode) -> Int {
        guard accepting else { return 0 }
        var added = 0
        for url in urls {
            let source = url.standardizedFileURL
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
        if id == activeID {
            cancelling.insert(id)
            worker?.cancel()
        } else {
            jobs[index].phase = .cancelled
            jobs[index].message = "待機中にキャンセルしました。"
        }
        persist()
    }

    public func retry(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }), job.phase.isFinished else { return }
        enqueue([job.input], mode: job.mode)
    }

    public func clearFinished() { jobs.removeAll { $0.phase.isFinished }; persist() }

    public func stopForTermination() async {
        accepting = false
        for id in jobs.filter({ !$0.phase.isFinished }).map(\.id) { cancel(id) }
        await waitUntilIdle()
    }

    public func waitUntilIdle() async {
        while let task = worker { await task.value }
    }

    private func startNext() {
        guard worker == nil, let job = jobs.first(where: { $0.phase == .waiting }) else { return }
        activeID = job.id
        worker = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await operation(job.input, job.mode, job.settings) { [weak self] phase, progress, note in
                    Task { @MainActor in
                        guard let self, self.activeID == job.id,
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
                }
            }
            cancelling.remove(job.id)
            activeID = nil
            worker = nil
            persist()
            startNext()
        }
    }

    private func trimHistory() {
        let finished = jobs.filter { $0.phase.isFinished }
        let remove = Set(finished.prefix(max(0, finished.count - 100)).map(\.id))
        jobs.removeAll { remove.contains($0.id) }
    }

    private func persist() {
        guard let storage, mayPersist else { return }
        do {
            try FileManager.default.createDirectory(at: storage.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(QueueSnapshot(settings: settings, jobs: jobs))
            try data.write(to: storage, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = "履歴を保存できませんでした。\n\(error.localizedDescription)"
        }
    }
}
