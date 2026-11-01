import DiskHealthCore
import SwiftUI

enum Format {
    static func bytes(_ b: Int64?) -> String {
        guard let b else { return "—" }
        let f = ByteCountFormatter()
        f.countStyle = .decimal
        return f.string(fromByteCount: b)
    }

    static func hours(_ h: Int?) -> String {
        guard let h else { return "—" }
        return String(localized: "\(h) h (≈ \(h / 24) days)")
    }

    static func number(_ n: Int?) -> String { n.map(String.init) ?? "—" }

    static func temperature(_ t: Int?) -> String { t.map { "\($0) °C" } ?? "—" }

    static func percent(_ p: Int?) -> String { p.map { "\($0)%" } ?? "—" }
}

extension HealthLevel {
    var color: Color {
        switch self {
        case .unknown: .gray
        case .ok: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    var title: String {
        switch self {
        case .unknown: String(localized: "Unknown")
        case .ok: String(localized: "All good")
        case .warning: String(localized: "Needs attention")
        case .critical: String(localized: "Critical")
        }
    }

    var menuBarSymbol: String {
        switch self {
        case .unknown, .ok: "internaldrive"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        }
    }
}
