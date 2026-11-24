import AppKit
import Combine
import NotchCompressorCore
import UserNotifications

@MainActor
final class TaskNotifications: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = TaskNotifications()
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "taskNotificationsEnabled")
    @Published private(set) var changing = false
    @Published private(set) var status = ""
    private var subscriptions = Set<AnyCancellable>()
    private let center = UNUserNotificationCenter.current()

    func start(queue: JobQueue) {
        guard subscriptions.isEmpty else { return }
        center.delegate = self
        queue.completionEvents.sink { [weak self] result in
            var notice = CompletionNotice()
            notice.include(result)
            Task { await self?.send(title: "圧縮が完了しました", body: notice.text) }
        }.store(in: &subscriptions)
        queue.failureEvents.sink { [weak self] notice in
            Task { await self?.send(title: notice.title, body: notice.body) }
        }.store(in: &subscriptions)
    }

    func setEnabled(_ value: Bool) async {
        guard !changing else { return }
        changing = true
        defer { changing = false }
        if !value {
            enabled = false
            UserDefaults.standard.set(false, forKey: "taskNotificationsEnabled")
            center.removeAllPendingNotificationRequests()
            await refresh()
            return
        }
        do {
            enabled = try await center.requestAuthorization(options: [.alert])
            UserDefaults.standard.set(enabled, forKey: "taskNotificationsEnabled")
            await refresh()
        } catch {
            status = "通知を設定できませんでした。システム設定の「通知」でNotchCompressorを確認してください。"
        }
    }

    func refresh() async {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .denied {
            status = "macOSで通知が許可されていません。システム設定 → 通知 → NotchCompressorで許可してください。"
        } else if enabled {
            status = "完了時は圧縮前後のサイズ、失敗時は対処方法を通知します。集中モードなどで表示されない場合があります。"
        } else {
            status = "オンにするとmacOSに通知の許可を求めます。動画名やパスは通知に表示しません。"
        }
    }

    private func send(title: String, body: String) async {
        guard enabled else { return }
        let settings = await center.notificationSettings()
        guard enabled, settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "compression-tasks"
        do {
            try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        } catch {
            status = "通知を送れませんでした。処理結果は圧縮キューで確認できます。"
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            if response.actionIdentifier == UNNotificationDefaultActionIdentifier { AppState.shared.presentQueue() }
            completionHandler()
        }
    }
}
