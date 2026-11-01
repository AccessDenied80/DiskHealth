import DiskHealthCore
import Foundation
import UserNotifications

enum Notifier {
    /// UNUserNotificationCenter падає поза `.app` (наприклад, при `swift run`).
    static var available: Bool { Bundle.main.bundleIdentifier != nil }

    private static let delegate = ForegroundPresenter()

    static func requestAuthorization() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            NSLog("DiskHealth: notification authorization granted=%@ error=%@",
                  String(granted), String(describing: error))
        }
    }

    static func post(_ alerts: [Alert]) {
        for a in alerts { NSLog("DiskHealth alert: %@ — %@", a.title, a.body) }
        guard available, !alerts.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        for a in alerts {
            let content = UNMutableNotificationContent()
            content.title = a.critical ? "⚠️ \(a.title)" : a.title
            content.body = a.body
            content.sound = a.critical ? .defaultCritical : .default
            content.interruptionLevel = a.critical ? .timeSensitive : .active
            let req = UNNotificationRequest(identifier: "\(a.key)|\(UUID().uuidString)", content: content, trigger: nil)
            center.add(req) { error in
                if let error { NSLog("DiskHealth: notification failed: %@", String(describing: error)) }
            }
        }
    }
}

/// Без делегата macOS не показує сповіщення, поки застосунок активний,
/// а DiskHealth активний якраз тоді, коли користувач відкрив його вікно чи налаштування.
private final class ForegroundPresenter: NSObject, @unchecked Sendable, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
