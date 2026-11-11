import AppKit
import Combine
import Sparkle
import NotchCompressorCore

@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdateController()
    @Published private(set) var canCheck = false
    @Published private(set) var installing = false
    @Published private(set) var status: String?
    private var controller: SPUStandardUpdaterController!
    private var observation: NSKeyValueObservation?
    private var deferredInstall: Task<Void, Never>?

    override private init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            Task { @MainActor in self?.canCheck = updater.canCheckForUpdates }
        }
    }

    func start() {
        do { try controller.updater.start() }
        catch { status = "更新を確認できません: \(error.localizedDescription)" }
    }
    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            controller.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }
    func check() { controller.checkForUpdates(nil) }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard !AppState.shared.queue.isBusy else {
            throw NSError(domain: "NotchCompressor.Updates", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "キューが空になってから更新を確認してください。一時停止中の動画は再開するか、キューから外してください。"])
        }
    }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        installing = true
        guard AppState.shared.queue.isBusy else { return false }
        status = "圧縮キューが空になるまで更新の再起動を待っています。"
        deferredInstall = Task { @MainActor [weak self] in
            while AppState.shared.queue.isBusy {
                do { try await Task.sleep(for: .milliseconds(500)) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            self?.status = nil
            installHandler()
        }
        return true
    }
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) { installing = true }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        deferredInstall?.cancel()
        installing = false
        status = error.localizedDescription
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if error != nil { deferredInstall?.cancel() }
        installing = false
    }
}
