import AppKit
import Combine
import NotchCompressorCore
import UserNotifications

@MainActor
final class TaskNotifications: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = TaskNotifications()
    @Published private(set) var enabled =
        (UserDefaults.standard.object(forKey: "taskNotificationsEnabled") as? Bool) ?? true
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var changing = false
    @Published private(set) var status = ""
    private var subscriptions = Set<AnyCancellable>()
    private weak var queue: JobQueue?
    private let center = UNUserNotificationCenter.current()

    func start(queue: JobQueue) {
        guard subscriptions.isEmpty else { return }
        self.queue = queue
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: "low-space",
                actions: [
                    UNNotificationAction(
                        identifier: "external-workspace", title: L10n.text("lowSpace.title"), options: [.foreground])
                ],
                intentIdentifiers: [])
        ])
        queue.completionEvents.sink { [weak self] result in
            var notice = CompletionNotice()
            notice.include(result)
            Task { await self?.send(title: L10n.text("notify.complete"), body: notice.text) }
        }.store(in: &subscriptions)
        queue.failureEvents.sink { [weak self] notice in
            Task {
                await self?.send(
                    title: notice.title, body: notice.body,
                    workspaceJobID: notice.diskSpaceIssue == nil ? nil : notice.jobID)
            }
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
            enabled = true
            UserDefaults.standard.set(true, forKey: "taskNotificationsEnabled")
            _ = try await center.requestAuthorization(options: [.alert])
            await refresh()
        } catch {
            status = L10n.text("notify.setupError")
        }
    }

    func refresh() async {
        let settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
        if settings.authorizationStatus == .notDetermined {
            status = L10n.text("notify.notRequested")
        } else if settings.authorizationStatus == .denied {
            status = L10n.text("notify.denied")
        } else if enabled {
            status = L10n.text("notify.enabled")
        } else {
            status = L10n.text("notify.disabled")
        }
    }

    func openSettings() {
        // Open Notifications, not a privacy pane which accepts dropped app icons.
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }

    private func send(title: String, body: String, workspaceJobID: UUID? = nil) async {
        guard enabled else { return }
        let settings = await center.notificationSettings()
        guard enabled, settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "compression-tasks"
        if let workspaceJobID {
            content.categoryIdentifier = "low-space"
            content.userInfo = ["jobID": workspaceJobID.uuidString]
        }
        do {
            try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        } catch {
            status = L10n.text("notify.sendError")
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
            if response.actionIdentifier == UNNotificationDefaultActionIdentifier
                || response.actionIdentifier == "external-workspace"
            {
                if let id = response.notification.request.content.userInfo["jobID"] as? String {
                    self.queue?.requestedWorkspaceJobID = UUID(uuidString: id)
                }
                AppState.shared.presentQueue()
            }
            completionHandler()
        }
    }
}
