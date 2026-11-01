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
            return HealthReport(level: .unknown, reasons: [String(localized: "SMART unavailable")], healthPercent: nil)
        }

        var level = HealthLevel.ok
        var reasons: [String] = []
        func flag(_ l: HealthLevel, _ reason: String) {
            level = max(level, l)
            reasons.append(reason)
        }

        if d.smartPassed == false { flag(.critical, String(localized: "SMART: FAILED")) }
        if let cw = d.criticalWarning, cw != 0 { flag(.critical, String(localized: "NVMe critical warning: \(cw)")) }
        if let me = d.mediaErrors, me > 0 { flag(.critical, String(localized: "Media errors: \(me)")) }
        if let w = d.wearPercent {
            if w >= t.wearCritical { flag(.critical, String(localized: "Wear \(w)%")) }
            else if w >= t.wearWarning { flag(.warning, String(localized: "Wear \(w)%")) }
        }
        if let temp = d.temperatureC, temp >= t.temperatureWarning { flag(.warning, String(localized: "Temperature \(temp) °C")) }
        if let r = d.reallocatedSectors, r > 0 { flag(.warning, String(localized: "Reallocated sectors: \(r)")) }
        if let p = d.pendingSectors, p > 0 { flag(.warning, String(localized: "Pending sectors: \(p)")) }
        if let c = d.crcErrors, c > 0 { flag(.warning, String(localized: "CRC errors: \(c)")) }

        return HealthReport(
            level: level,
            reasons: reasons,
            healthPercent: d.wearPercent.map { max(0, 100 - $0) }
        )
    }
}
