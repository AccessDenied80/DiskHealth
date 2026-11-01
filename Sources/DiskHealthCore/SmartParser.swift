import Foundation

/// Перетворює JSON-вивід `smartctl --json` у моделі застосунку.
public enum SmartParser {
    /// Одиниця даних NVMe: 1000 секторів по 512 байт.
    static let nvmeDataUnit: Int64 = 512_000

    public static func parseScan(_ data: Data) throws -> [ScannedDevice] {
        let raw = try JSONDecoder().decode(RawScan.self, from: data)
        return (raw.devices ?? []).map {
            ScannedDevice(name: $0.name, type: $0.type ?? "auto", proto: $0.protocol ?? "")
        }
    }

    public static func parseDisk(_ data: Data) throws -> DiskInfo {
        let r = try JSONDecoder().decode(RawDisk.self, from: data)
        let name = r.device?.name ?? "?"
        let nvme = r.nvme_smart_health_information_log
        let attrs = Dictionary(
            (r.ata_smart_attributes?.table ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let hasSmart = r.smart_status != nil
            || nvme != nil
            || (r.smart_support?.available ?? false)

        var info = DiskInfo(
            id: r.serial_number ?? name,
            deviceName: name,
            deviceType: r.device?.type ?? "unknown",
            model: r.model_name ?? r.model_family ?? r.product ?? "Невідомий диск",
            serial: r.serial_number,
            firmware: r.firmware_version,
            capacityBytes: r.user_capacity?.bytes
                ?? r.nvme_total_capacity
                ?? r.nvme_namespaces?.first?.capacity?.bytes,
            smartAvailable: hasSmart,
            smartPassed: r.smart_status?.passed,
            temperatureC: r.temperature?.current ?? nvme?.temperature,
            powerOnHours: r.power_on_time?.hours ?? nvme?.power_on_hours,
            powerCycles: r.power_cycle_count ?? nvme?.power_cycles,
            messages: r.smartctl?.messages?.compactMap(\.string) ?? []
        )

        if let nvme {
            info.criticalWarning = nvme.critical_warning
            info.wearPercent = nvme.percentage_used
            info.availableSpare = nvme.available_spare
            info.unsafeShutdowns = nvme.unsafe_shutdowns
            info.mediaErrors = nvme.media_errors
            info.bytesWritten = nvme.data_units_written.map { $0 * nvmeDataUnit }
            info.bytesRead = nvme.data_units_read.map { $0 * nvmeDataUnit }
        }

        if !attrs.isEmpty {
            info.reallocatedSectors = attrs[5]?.raw?.value.map(Int.init)
            info.pendingSectors = attrs[197]?.raw?.value.map(Int.init)
            info.crcErrors = attrs[199]?.raw?.value.map(Int.init)
            // Залишок ресурсу SSD у різних виробників — перший наявний атрибут.
            if info.wearPercent == nil,
               let life = [231, 233, 177, 202].lazy.compactMap({ attrs[$0]?.value }).first {
                info.wearPercent = max(0, 100 - life)
            }
            if let lbas = attrs[241], lbas.name?.contains("LBAs") == true, let raw = lbas.raw?.value {
                info.bytesWritten = raw * 512
            }
            if let lbas = attrs[242], lbas.name?.contains("LBAs") == true, let raw = lbas.raw?.value {
                info.bytesRead = raw * 512
            }
        }

        return info
    }
}

// MARK: - Дзеркало JSON smartctl (усі поля необов'язкові)

private struct RawScan: Decodable {
    struct Device: Decodable {
        let name: String
        let type: String?
        let `protocol`: String?
    }
    let devices: [Device]?
}

private struct RawDisk: Decodable {
    struct Smartctl: Decodable {
        struct Message: Decodable { let string: String? }
        let messages: [Message]?
        let exit_status: Int?
    }
    struct Device: Decodable {
        let name: String?
        let type: String?
    }
    struct Capacity: Decodable { let bytes: Int64? }
    struct Namespace: Decodable { let capacity: Capacity? }
    struct Support: Decodable { let available: Bool? }
    struct Status: Decodable { let passed: Bool? }
    struct Temperature: Decodable { let current: Int? }
    struct PowerOn: Decodable { let hours: Int? }
    struct NVMeLog: Decodable {
        let critical_warning: Int?
        let temperature: Int?
        let available_spare: Int?
        let percentage_used: Int?
        let data_units_read: Int64?
        let data_units_written: Int64?
        let power_cycles: Int?
        let power_on_hours: Int?
        let unsafe_shutdowns: Int?
        let media_errors: Int?
    }
    struct Attributes: Decodable {
        struct Entry: Decodable {
            struct Raw: Decodable { let value: Int64? }
            let id: Int
            let name: String?
            let value: Int?
            let raw: Raw?
        }
        let table: [Entry]?
    }

    let smartctl: Smartctl?
    let device: Device?
    let model_name: String?
    let model_family: String?
    let product: String?
    let serial_number: String?
    let firmware_version: String?
    let user_capacity: Capacity?
    let nvme_total_capacity: Int64?
    let nvme_namespaces: [Namespace]?
    let smart_support: Support?
    let smart_status: Status?
    let temperature: Temperature?
    let power_on_time: PowerOn?
    let power_cycle_count: Int?
    let nvme_smart_health_information_log: NVMeLog?
    let ata_smart_attributes: Attributes?
}
