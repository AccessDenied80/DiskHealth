import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Опитування") {
                Picker("Інтервал", selection: $settings.pollMinutes) {
                    Text("5 хв").tag(5)
                    Text("15 хв").tag(15)
                    Text("30 хв").tag(30)
                    Text("1 год").tag(60)
                    Text("3 год").tag(180)
                }
                Toggle("Запускати при вході в систему", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
            }
            Section("Пороги попереджень") {
                Stepper("Знос — увага: \(settings.wearWarning)%", value: $settings.wearWarning, in: 10...100, step: 5)
                Stepper("Знос — критично: \(settings.wearCritical)%", value: $settings.wearCritical, in: 10...100, step: 5)
                Stepper("Температура: \(settings.temperatureWarning) °C", value: $settings.temperatureWarning, in: 40...90, step: 5)
            }
            Section("Сповіщення") {
                Toggle("Показувати системні сповіщення", isOn: $settings.notificationsEnabled)
            }
        }
        .formStyle(.grouped)
        // Згрупована Form не має власної висоти: без явного розміру вікно стискається до нуля.
        .frame(width: 460, height: 440)
    }
}
