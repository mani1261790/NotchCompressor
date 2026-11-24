import AppKit
import Combine

/// Only system sleep/wake affects compression; display sleep and locking do not.
@MainActor
public final class QueueSleepMonitor {
    private var observations = Set<AnyCancellable>()

    public init(queue: JobQueue, center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        center.publisher(for: NSWorkspace.willSleepNotification).sink { [weak queue] _ in
            // Workspace notifications are handled synchronously on the main thread
            // so suspending children finishes before the sleep callback returns.
            if Thread.isMainThread {
                MainActor.assumeIsolated { queue?.prepareForSystemSleep() }
            } else {
                DispatchQueue.main.sync { queue?.prepareForSystemSleep() }
            }
        }.store(in: &observations)
        center.publisher(for: NSWorkspace.didWakeNotification).sink { [weak queue] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { queue?.resumeAfterSystemSleep() }
            } else {
                DispatchQueue.main.sync { queue?.resumeAfterSystemSleep() }
            }
        }.store(in: &observations)
    }
}
