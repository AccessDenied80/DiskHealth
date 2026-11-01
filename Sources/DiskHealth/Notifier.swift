import DiskHealthCore
import Foundation
import UserNotifications

enum Notifier {
    /// UNUserNotificationCenter падає поза `.app` (наприклад, при `swift run`).
    static var available: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            if let error { NSLog("DiskHealth: notification auth failed: \(error)") }
        }
    }

    static func post(_ alerts: [Alert]) {
        guard available else {
            alerts.forEach { NSLog("DiskHealth alert: \($0.title) — \($0.body)") }
            return
        }
        for a in alerts {
            let content = UNMutableNotificationContent()
            content.title = a.critical ? "⚠️ \(a.title)" : a.title
            content.body = a.body
            content.sound = a.critical ? .defaultCritical : .default
            content.interruptionLevel = a.critical ? .timeSensitive : .active
            let req = UNNotificationRequest(identifier: "\(a.key)|\(UUID().uuidString)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(req)
        }
    }
}
