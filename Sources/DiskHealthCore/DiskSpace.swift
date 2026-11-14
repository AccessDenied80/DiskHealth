import Foundation

/// Скільки місця на диску зайнято. «Вільно» — як у Finder: разом із місцем, яке macOS звільнить сама.
public struct DiskSpace: Equatable, Hashable, Sendable {
    public var totalBytes: Int64
    public var availableBytes: Int64

    public init(totalBytes: Int64, availableBytes: Int64) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
    }

    public var usedBytes: Int64 { max(0, totalBytes - availableBytes) }

    public var usedPercent: Int {
        guard totalBytes > 0 else { return 0 }
        return Int((Double(usedBytes) * 100 / Double(totalBytes)).rounded())
    }
}

/// Місткість і вільне місце одного змонтованого тому.
public struct VolumeCapacity: Equatable, Sendable {
    public var totalBytes: Int64
    public var availableBytes: Int64

    public init(totalBytes: Int64, availableBytes: Int64) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
    }
}

public enum DiskSpaceCalculator {
    /// Точки монтування диска, згруповані за спільним місцем: усі томи одного контейнера APFS ділять
    /// одне місце (рахуємо його один раз), а кожен звичайний розділ — окрема група.
    /// - Parameter diskutilList: вивід `diskutil list -plist`.
    public static func mountGroups(diskutilList: Data, wholeDisk id: String) throws -> [[String]] {
        guard let root = try PropertyListSerialization.propertyList(from: diskutilList, format: nil) as? [String: Any] else {
            throw DiskutilError.failed(String(localized: "Invalid diskutil output"))
        }
        let entries = root["AllDisksAndPartitions"] as? [[String: Any]] ?? []
        guard let entry = entries.first(where: { $0["DeviceIdentifier"] as? String == id }) else { return [] }
        let partitions = entry["Partitions"] as? [[String: Any]] ?? []
        let stores = Set(partitions.compactMap { $0["DeviceIdentifier"] as? String } + [id])

        let containerGroups: [[String]] = entries
            .filter { e in
                (e["APFSPhysicalStores"] as? [[String: Any]] ?? []).contains { stores.contains($0["DeviceIdentifier"] as? String ?? "") }
            }
            .map { container in
                (container["APFSVolumes"] as? [[String: Any]] ?? []).flatMap { volume in
                    // Системний том macOS змонтований як знімок: його точка «/» лежить у MountedSnapshots.
                    let snapshots = (volume["MountedSnapshots"] as? [[String: Any]] ?? []).compactMap { $0["SnapshotMountPoint"] as? String }
                    return [volume["MountPoint"] as? String].compactMap { $0 } + snapshots
                }
            }

        let plainGroups: [[String]] = ([entry] + partitions)
            .filter { ($0["Content"] as? String) != "EFI" }
            .compactMap { ($0["MountPoint"] as? String).map { [$0] } }

        return (containerGroups + plainGroups).filter { !$0.isEmpty }
    }

    /// У межах групи беремо найкращі значення (деякі службові томи, як-от VM, повертають «вільно 0»),
    /// а групи підсумовуємо.
    public static func combine(_ groups: [[VolumeCapacity]]) -> DiskSpace? {
        let perGroup = groups.compactMap { group -> DiskSpace? in
            guard let total = group.map(\.totalBytes).max(), total > 0 else { return nil }
            return DiskSpace(totalBytes: total, availableBytes: min(total, group.map(\.availableBytes).max() ?? 0))
        }
        guard !perGroup.isEmpty else { return nil }
        return DiskSpace(
            totalBytes: perGroup.map(\.totalBytes).reduce(0, +),
            availableBytes: perGroup.map(\.availableBytes).reduce(0, +)
        )
    }
}

/// Диск, заповненість якого перевіряє `AlertEngine.diffSpace`.
public struct SpaceAlertItem: Sendable {
    /// Стабільний ідентифікатор (серійний номер, якщо є), а не BSD-ім'я, яке змінюється після перепідключення.
    public var id: String
    public var name: String
    public var space: DiskSpace

    public init(id: String, name: String, space: DiskSpace) {
        self.id = id
        self.name = name
        self.space = space
    }
}

extension AlertEngine {
    /// Сповіщає, коли диск заповнився до порогу. Повторно — лише після того, як заповнення впаде
    /// на `fullRearmMargin` нижче порогу: інакше диск, що коливається біля межі, засипав би сповіщеннями.
    public static func diffSpace(_ items: [SpaceAlertItem], thresholds t: Thresholds, state: inout AlertState) -> [Alert] {
        var alerts: [Alert] = []
        for item in items {
            let key = "\(item.id)|full\(t.fullWarning)"
            state.active = state.active.filter { !$0.hasPrefix("\(item.id)|full") || $0 == key }
            let pct = item.space.usedPercent
            if pct >= t.fullWarning {
                if state.active.insert(key).inserted {
                    let free = ByteCountFormatter.string(fromByteCount: item.space.availableBytes, countStyle: .decimal)
                    alerts.append(Alert(
                        key: key, diskID: item.id, title: item.name,
                        body: String(localized: "Disk is \(pct)% full (threshold \(t.fullWarning)%). \(free) available."),
                        critical: false
                    ))
                }
            } else if pct < t.fullWarning - t.fullRearmMargin {
                state.active.remove(key)
            }
        }
        return alerts
    }
}
