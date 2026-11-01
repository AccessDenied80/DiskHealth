public enum HealthLevel: Int, Codable, Comparable, Sendable {
    case unknown = 0, ok, warning, critical

    public static func < (a: HealthLevel, b: HealthLevel) -> Bool { a.rawValue < b.rawValue }

    /// Найгірший стан серед дисків; `.unknown` не перекриває `.ok`.
    public static func overall(_ levels: [HealthLevel]) -> HealthLevel {
        levels.max() ?? .unknown
    }
}

public struct HealthReport: Equatable, Sendable {
    public var level: HealthLevel
    public var reasons: [String]
    public var healthPercent: Int?

    public init(level: HealthLevel, reasons: [String], healthPercent: Int?) {
        self.level = level
        self.reasons = reasons
        self.healthPercent = healthPercent
    }
}

public enum HealthEvaluator {
    public static func evaluate(_ d: DiskInfo, _ t: Thresholds) -> HealthReport {
        guard d.smartAvailable else {
            return HealthReport(level: .unknown, reasons: ["SMART недоступний"], healthPercent: nil)
        }

        var level = HealthLevel.ok
        var reasons: [String] = []
        func flag(_ l: HealthLevel, _ reason: String) {
            level = max(level, l)
            reasons.append(reason)
        }

        if d.smartPassed == false { flag(.critical, "SMART: FAILED") }
        if let cw = d.criticalWarning, cw != 0 { flag(.critical, "NVMe critical warning: \(cw)") }
        if let me = d.mediaErrors, me > 0 { flag(.critical, "Помилки носія: \(me)") }
        if let w = d.wearPercent {
            if w >= t.wearCritical { flag(.critical, "Знос \(w)%") }
            else if w >= t.wearWarning { flag(.warning, "Знос \(w)%") }
        }
        if let temp = d.temperatureC, temp >= t.temperatureWarning { flag(.warning, "Температура \(temp) °C") }
        if let r = d.reallocatedSectors, r > 0 { flag(.warning, "Перепризначені сектори: \(r)") }
        if let p = d.pendingSectors, p > 0 { flag(.warning, "Нестабільні сектори: \(p)") }
        if let c = d.crcErrors, c > 0 { flag(.warning, "Помилки CRC: \(c)") }

        return HealthReport(
            level: level,
            reasons: reasons,
            healthPercent: d.wearPercent.map { max(0, 100 - $0) }
        )
    }
}
