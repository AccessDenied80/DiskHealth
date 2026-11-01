import Foundation

public struct HistorySample: Codable, Equatable, Sendable {
    public var date: Date
    public var wearPercent: Int?
    public var temperatureC: Int?
    public var bytesWritten: Int64?
}

/// Історія показників по дисках у JSON-файлі; зберігає останні 365 днів.
public final class HistoryStore: @unchecked Sendable {
    static let retention: TimeInterval = 365 * 86_400

    public let fileURL: URL
    private var byDisk: [String: [HistorySample]] = [:]
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func append(_ disks: [DiskInfo], at date: Date) {
        lock.lock(); defer { lock.unlock() }
        let cutoff = date.addingTimeInterval(-Self.retention)
        for d in disks where d.smartAvailable {
            var list = byDisk[d.id] ?? []
            list.append(HistorySample(date: date, wearPercent: d.wearPercent,
                                      temperatureC: d.temperatureC, bytesWritten: d.bytesWritten))
            byDisk[d.id] = list.filter { $0.date >= cutoff }
        }
    }

    public func samples(for diskID: String) -> [HistorySample] {
        lock.lock(); defer { lock.unlock() }
        return byDisk[diskID] ?? []
    }

    public func save() throws {
        lock.lock(); let snapshot = byDisk; lock.unlock()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
    }

    /// Відсутній або пошкоджений файл означає порожню історію.
    public func load() {
        let loaded = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([String: [HistorySample]].self, from: $0) } ?? [:]
        lock.lock(); byDisk = loaded; lock.unlock()
    }
}
