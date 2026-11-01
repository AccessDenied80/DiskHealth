public struct Alert: Equatable, Sendable {
    public var key: String
    public var diskID: String
    public var title: String
    public var body: String
    public var critical: Bool
}

/// Пам'ять між опитуваннями: які умови вже повідомлені і останні значення лічильників.
public struct AlertState: Codable, Equatable, Sendable {
    public var active: Set<String> = []
    public var lastCounters: [String: [String: Int]] = [:]

    public init() {}
}

/// Порівнює нові дані з попереднім станом і повертає лише нові події.
public enum AlertEngine {
    public static func diff(disks: [DiskInfo], thresholds t: Thresholds, state: inout AlertState) -> [Alert] {
        var alerts: [Alert] = []

        for d in disks where d.smartAvailable {
            let name = "\(d.model) (\(d.deviceName))"

            // Умови-стани: сповіщаємо при вході в стан, забуваємо при виході.
            let conditions: [(key: String, on: Bool, critical: Bool, body: String)] = [
                ("smartFailed", d.smartPassed == false, true, "SMART-статус: FAILED. Терміново зробіть резервну копію."),
                ("criticalWarning", (d.criticalWarning ?? 0) != 0, true, "NVMe critical warning: \(d.criticalWarning ?? 0)."),
                ("wear\(t.wearWarning)", (d.wearPercent ?? 0) >= t.wearWarning, false, "Знос досяг \(d.wearPercent ?? 0)% (поріг \(t.wearWarning)%)."),
                ("wear\(t.wearCritical)", (d.wearPercent ?? 0) >= t.wearCritical, true, "Знос досяг \(d.wearPercent ?? 0)% (критичний поріг \(t.wearCritical)%)."),
                ("temp", (d.temperatureC ?? 0) >= t.temperatureWarning, false, "Температура \(d.temperatureC ?? 0) °C (поріг \(t.temperatureWarning) °C)."),
            ]
            for c in conditions {
                let key = "\(d.id)|\(c.key)"
                if c.on {
                    if state.active.insert(key).inserted {
                        alerts.append(Alert(key: key, diskID: d.id, title: name, body: c.body, critical: c.critical))
                    }
                } else {
                    state.active.remove(key)
                }
            }

            // Лічильники: сповіщаємо, коли значення зросло.
            let counters: [(name: String, value: Int?, label: String, firstSightAlerts: Bool, critical: Bool)] = [
                ("mediaErrors", d.mediaErrors, "Помилки носія", true, true),
                ("reallocatedSectors", d.reallocatedSectors, "Перепризначені сектори", true, false),
                ("pendingSectors", d.pendingSectors, "Нестабільні сектори", true, false),
                ("crcErrors", d.crcErrors, "Помилки CRC", false, false),
            ]
            var stored = state.lastCounters[d.id] ?? [:]
            for c in counters {
                guard let value = c.value else { continue }
                let previous = stored[c.name]
                let grew = previous.map { value > $0 } ?? (c.firstSightAlerts && value > 0)
                if grew {
                    let body = previous.map { "\(c.label): \($0) → \(value)." } ?? "\(c.label): \(value)."
                    alerts.append(Alert(key: "\(d.id)|\(c.name)", diskID: d.id, title: name, body: body, critical: c.critical))
                }
                stored[c.name] = value
            }
            state.lastCounters[d.id] = stored
        }

        return alerts
    }
}
