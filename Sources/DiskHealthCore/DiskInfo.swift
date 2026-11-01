import Foundation

/// Пристрій, знайдений `smartctl --scan-open`.
public struct ScannedDevice: Codable, Hashable, Sendable {
    public var name: String
    public var type: String
    public var proto: String

    public init(name: String, type: String, proto: String) {
        self.name = name
        self.type = type
        self.proto = proto
    }
}

/// Нормалізований знімок SMART-даних одного диска.
public struct DiskInfo: Codable, Hashable, Sendable, Identifiable {
    /// Серійний номер, якщо є, інакше ім'я пристрою.
    public var id: String
    public var deviceName: String
    public var deviceType: String
    public var model: String
    public var serial: String?
    public var firmware: String?
    public var capacityBytes: Int64?
    public var smartAvailable: Bool
    public var smartPassed: Bool?
    public var criticalWarning: Int?
    /// Знос у відсотках (NVMe `percentage_used` або 100 − залишок ресурсу для ATA SSD).
    public var wearPercent: Int?
    public var availableSpare: Int?
    public var temperatureC: Int?
    public var powerOnHours: Int?
    public var powerCycles: Int?
    public var unsafeShutdowns: Int?
    public var bytesWritten: Int64?
    public var bytesRead: Int64?
    public var mediaErrors: Int?
    public var reallocatedSectors: Int?
    public var pendingSectors: Int?
    public var crcErrors: Int?
    public var messages: [String]

    public init(
        id: String, deviceName: String, deviceType: String, model: String,
        serial: String? = nil, firmware: String? = nil, capacityBytes: Int64? = nil,
        smartAvailable: Bool, smartPassed: Bool? = nil, criticalWarning: Int? = nil,
        wearPercent: Int? = nil, availableSpare: Int? = nil, temperatureC: Int? = nil,
        powerOnHours: Int? = nil, powerCycles: Int? = nil, unsafeShutdowns: Int? = nil,
        bytesWritten: Int64? = nil, bytesRead: Int64? = nil, mediaErrors: Int? = nil,
        reallocatedSectors: Int? = nil, pendingSectors: Int? = nil, crcErrors: Int? = nil,
        messages: [String] = []
    ) {
        self.id = id
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.model = model
        self.serial = serial
        self.firmware = firmware
        self.capacityBytes = capacityBytes
        self.smartAvailable = smartAvailable
        self.smartPassed = smartPassed
        self.criticalWarning = criticalWarning
        self.wearPercent = wearPercent
        self.availableSpare = availableSpare
        self.temperatureC = temperatureC
        self.powerOnHours = powerOnHours
        self.powerCycles = powerCycles
        self.unsafeShutdowns = unsafeShutdowns
        self.bytesWritten = bytesWritten
        self.bytesRead = bytesRead
        self.mediaErrors = mediaErrors
        self.reallocatedSectors = reallocatedSectors
        self.pendingSectors = pendingSectors
        self.crcErrors = crcErrors
        self.messages = messages
    }
}
