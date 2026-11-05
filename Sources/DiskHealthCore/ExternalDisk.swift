import Foundation

public struct ExternalVolume: Equatable, Hashable, Sendable {
    public var name: String
    public var mountPoint: String?

    public init(name: String, mountPoint: String?) {
        self.name = name
        self.mountPoint = mountPoint
    }
}

/// Зовнішній фізичний диск з точки зору `diskutil` (образи DMG сюди не входять).
public struct ExternalDisk: Equatable, Hashable, Sendable, Identifiable {
    /// BSD-ім'я цілого диска: `disk2`.
    public var id: String
    public var sizeBytes: Int64?
    /// Томи для показу користувачу, без системних.
    public var volumes: [ExternalVolume]
    /// Чи змонтовано хоч щось, включно з прихованими томами: лише `false` означає, що диск можна від'єднувати.
    public var isMounted: Bool
    /// Що передавати в `diskutil mountDisk`: для APFS це контейнер, бо документація не обіцяє,
    /// що команда на фізичному диску змонтує його «віртуальні» томи.
    public var mountTargets: [String]

    public init(id: String, sizeBytes: Int64?, volumes: [ExternalVolume], isMounted: Bool, mountTargets: [String]) {
        self.id = id
        self.sizeBytes = sizeBytes
        self.volumes = volumes
        self.isMounted = isMounted
        self.mountTargets = mountTargets
    }
}

public enum ExternalDiskParser {
    /// - Parameters:
    ///   - all: вивід `diskutil list -plist external` (містить і контейнери APFS, і образи DMG);
    ///   - physical: вивід `diskutil list -plist external physical` (лише справжні диски).
    public static func parse(all: Data, physical: Data) throws -> [ExternalDisk] {
        let entries = try plist(all)["AllDisksAndPartitions"] as? [[String: Any]] ?? []
        let wholeDisks = try plist(physical)["WholeDisks"] as? [String] ?? []

        return wholeDisks.compactMap { id in
            guard let entry = entries.first(where: { $0["DeviceIdentifier"] as? String == id }) else { return nil }
            let partitions = entry["Partitions"] as? [[String: Any]] ?? []
            let stores = Set(partitions.compactMap { $0["DeviceIdentifier"] as? String } + [id])

            let containers = entries.filter { candidate in
                let physicalStores = candidate["APFSPhysicalStores"] as? [[String: Any]] ?? []
                return physicalStores.contains { stores.contains($0["DeviceIdentifier"] as? String ?? "") }
            }
            let apfsVolumes = containers.flatMap { $0["APFSVolumes"] as? [[String: Any]] ?? [] }
            // Розділ-контейнер APFS, EFI та службові розділи самі по собі томами не є.
            let plain = ([entry] + partitions).filter(isPlainVolume)

            let everything = plain + partitions + apfsVolumes
            return ExternalDisk(
                id: id,
                sizeBytes: (entry["Size"] as? NSNumber)?.int64Value,
                volumes: (plain + apfsVolumes.filter { $0["OSInternal"] as? Bool != true }).map {
                    ExternalVolume(name: $0["VolumeName"] as? String ?? id, mountPoint: $0["MountPoint"] as? String)
                },
                isMounted: everything.contains { $0["MountPoint"] != nil },
                mountTargets: containers.compactMap { $0["DeviceIdentifier"] as? String } + (plain.isEmpty ? [] : [id])
            )
        }
    }

    private static func isPlainVolume(_ p: [String: Any]) -> Bool {
        let content = p["Content"] as? String ?? ""
        if content == "EFI" || content == "Apple_Boot" || content.hasPrefix("Apple_APFS") { return false }
        return p["MountPoint"] != nil || !(p["VolumeName"] as? String ?? "").isEmpty
    }

    private static func plist(_ data: Data) throws -> [String: Any] {
        guard let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw DiskutilError.failed(String(localized: "Invalid diskutil output"))
        }
        return dict
    }
}

public enum DiskutilError: Error, Equatable, Sendable {
    case failed(String)
}

extension DiskutilError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .failed(let message): message
        }
    }
}

/// Монтує й розмонтовує зовнішні диски через системний `diskutil`. Прав адміністратора не потребує.
public struct DiskutilRunner: Sendable {
    public let executable: URL

    public init(executable: URL = URL(fileURLWithPath: "/usr/sbin/diskutil")) {
        self.executable = executable
    }

    public func list() async throws -> [ExternalDisk] {
        let all = try await run(["list", "-plist", "external"])
        let physical = try await run(["list", "-plist", "external", "physical"])
        return try ExternalDiskParser.parse(all: all, physical: physical)
    }

    /// Без `force`: якщо диском користується якийсь застосунок, macOS відмовить, і дані не постраждають.
    /// `unmountDisk` сам розмонтовує й томи APFS, що лежать на цьому диску.
    public func unmount(_ disk: ExternalDisk) async throws {
        _ = try await run(["unmountDisk", "/dev/\(disk.id)"], mergeErrors: true)
    }

    public func mount(_ disk: ExternalDisk) async throws {
        for target in disk.mountTargets {
            _ = try await run(["mountDisk", "/dev/\(target)"], mergeErrors: true)
        }
    }

    private func run(_ args: [String], mergeErrors: Bool = false) async throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw DiskutilError.failed(String(localized: "diskutil not found: \(executable.path)"))
        }
        let executable = executable
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = executable
                p.arguments = args
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = mergeErrors ? pipe : FileHandle.nullDevice
                do {
                    try p.run()
                } catch {
                    cont.resume(throwing: DiskutilError.failed(error.localizedDescription))
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 120) { if p.isRunning { p.terminate() } }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                guard p.terminationStatus == 0 else {
                    // Найкорисніше — хто тримає диск: «Unmount was dissented by PID 2134 (Preview)».
                    // Наступний рядок про батьківський процес лише заплутує, тож шукаємо саме цей.
                    let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
                    let message = lines.first { $0.contains("dissented by") } ?? lines.last
                    cont.resume(throwing: DiskutilError.failed(message ?? "diskutil \(args[0]): \(p.terminationStatus)"))
                    return
                }
                cont.resume(returning: data)
            }
        }
    }
}
