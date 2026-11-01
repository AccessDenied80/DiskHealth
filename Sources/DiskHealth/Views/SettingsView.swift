import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Polling") {
                Picker("Interval", selection: $settings.pollMinutes) {
                    Text("5 min").tag(5)
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("1 hour").tag(60)
                    Text("3 hours").tag(180)
                }
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
            }
            Section("Warning thresholds") {
                Stepper("Wear — warning: \(settings.wearWarning)%", value: $settings.wearWarning, in: 10...100, step: 5)
                Stepper("Wear — critical: \(settings.wearCritical)%", value: $settings.wearCritical, in: 10...100, step: 5)
                Stepper("Temperature: \(settings.temperatureWarning) °C", value: $settings.temperatureWarning, in: 40...90, step: 5)
            }
            Section("Notifications") {
                Toggle("Show system notifications", isOn: $settings.notificationsEnabled)
            }
        }
        .formStyle(.grouped)
        // Згрупована Form не має власної висоти: без явного розміру вікно стискається до нуля.
        .frame(width: 460, height: 440)
    }
}
