import DiskHealthCore
import ServiceManagement
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("pollMinutes") var pollMinutes = 30
    @AppStorage("wearWarning") var wearWarning = 80
    @AppStorage("wearCritical") var wearCritical = 90
    @AppStorage("temperatureWarning") var temperatureWarning = 60
    @AppStorage("notificationsEnabled") var notificationsEnabled = true

    var thresholds: Thresholds {
        var t = Thresholds()
        t.wearWarning = wearWarning
        t.wearCritical = wearCritical
        t.temperatureWarning = temperatureWarning
        return t
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("DiskHealth: launch at login change failed: \(error)")
            }
        }
    }
}
