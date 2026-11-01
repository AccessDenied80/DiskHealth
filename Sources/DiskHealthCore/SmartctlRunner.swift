import Foundation

public enum SmartctlError: Error, Equatable, Sendable {
    case notFound(String)
    case noData(device: String, exitStatus: Int32)
    case badOutput(String)
}

extension SmartctlError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notFound(let path): "smartctl не знайдено: \(path)"
        case .noData(let device, let code): "\(device): smartctl не повернув даних (код \(code))"
        case .badOutput(let what): "Некоректна відповідь smartctl: \(what)"
        }
    }
}

/// Запускає `smartctl` і розбирає його JSON.
public struct SmartctlRunner: Sendable {
    public let executable: URL
    /// Скільки чекати на один виклик, перш ніж зупинити процес (сплячий USB-диск може зависнути).
    public var timeout: TimeInterval = 60

    public init(executable: URL) {
        self.executable = executable
    }

    /// `smartctl`, вбудований у `.app`; для запуску з `swift run` — встановлений через brew.
    public static func bundled() -> SmartctlRunner {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("smartctl").path,
            "/usr/local/bin/smartctl",
            "/opt/homebrew/bin/smartctl",
        ].compactMap { $0 }
        let path = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
        return SmartctlRunner(executable: URL(fileURLWithPath: path))
    }

    public func scan() async throws -> [ScannedDevice] {
        let (out, code) = try await run(["--scan-open", "--json=c"])
        do {
            return try SmartParser.parseScan(out)
        } catch {
            throw failure(device: "scan", exitStatus: code)
        }
    }

    public func read(_ dev: ScannedDevice) async throws -> DiskInfo {
        let info = try await read(dev, permissive: false)
        // USB-мости часто не заявляють підтримку SMART в IDENTIFY, хоча команди виконують.
        if !info.smartAvailable, ["ata", "sat"].contains(dev.type),
           let retry = try? await read(dev, permissive: true), retry.smartAvailable {
            return retry
        }
        return info
    }

    private func read(_ dev: ScannedDevice, permissive: Bool) async throws -> DiskInfo {
        var args = ["-x", "--json=c"]
        if permissive { args += ["-T", "permissive"] }
        if !dev.type.isEmpty, dev.type != "auto" { args += ["-d", dev.type] }
        args.append(dev.name)
        let (out, code) = try await run(args)
        // Код виходу smartctl — бітова маска: ненульовий код із валідним JSON — це нормальні дані.
        var info: DiskInfo
        do {
            info = try SmartParser.parseDisk(out)
        } catch {
            throw failure(device: dev.name, exitStatus: code)
        }
        if let media = IOKitLookup.wholeMedia(forServicePath: info.deviceName) {
            info.deviceName = "/dev/\(media.bsdName)"
            info.capacityBytes = info.capacityBytes ?? media.sizeBytes
        }
        return info
    }

    public func readAll() async -> (disks: [DiskInfo], errors: [String]) {
        let devices: [ScannedDevice]
        do {
            devices = try await scan()
        } catch {
            return ([], [error.localizedDescription])
        }
        var disks: [DiskInfo] = []
        var errors: [String] = []
        for dev in devices {
            do {
                disks.append(try await read(dev))
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        return (disks, errors)
    }

    private func failure(device: String, exitStatus: Int32) -> SmartctlError {
        exitStatus & 0b11 != 0
            ? .noData(device: device, exitStatus: exitStatus)
            : .badOutput(device)
    }

    private func run(_ args: [String]) async throws -> (Data, Int32) {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw SmartctlError.notFound(executable.path)
        }
        let executable = executable
        let timeout = timeout
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let p = Process()
                p.executableURL = executable
                p.arguments = args
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = FileHandle.nullDevice
                do {
                    try p.run()
                } catch {
                    cont.resume(throwing: SmartctlError.notFound(executable.path))
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if p.isRunning { p.terminate() }
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: (data, p.terminationStatus))
            }
        }
    }
}
