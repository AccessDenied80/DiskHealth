import Foundation
import Testing
@testable import DiskHealthCore

@Suite struct RunnerTests {
    /// Тимчасовий «smartctl», що друкує фікстуру та виходить із заданим кодом.
    func fakeSmartctl(printing fixtureName: String?, exit code: Int32) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var script = "#!/bin/sh\n"
        if let fixtureName {
            let src = try #require(Bundle.module.url(forResource: fixtureName, withExtension: "json", subdirectory: "Fixtures"))
            script += "cat '\(src.path)'\n"
        }
        script += "exit \(code)\n"
        let url = dir.appendingPathComponent("smartctl")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    let dev = ScannedDevice(name: "/dev/disk0", type: "nvme", proto: "NVMe")

    @Test func missingExecutableThrowsNotFound() async {
        let r = SmartctlRunner(executable: URL(fileURLWithPath: "/nonexistent/smartctl"))
        await #expect(throws: SmartctlError.notFound("/nonexistent/smartctl")) { try await r.scan() }
    }

    @Test func fakeExecutableNonZeroExitStillParses() async throws {
        let r = SmartctlRunner(executable: try fakeSmartctl(printing: "nvme_apple", exit: 4))
        let d = try await r.read(dev)
        #expect(d.model == "APPLE SSD AP0512M")
    }

    @Test func fakeExecutableExit2NoJSON() async throws {
        let r = SmartctlRunner(executable: try fakeSmartctl(printing: nil, exit: 2))
        await #expect(throws: SmartctlError.noData(device: "/dev/disk0", exitStatus: 2)) { try await r.read(dev) }
    }

    @Test func readAllCollectsDisksAndErrors() async throws {
        let r = SmartctlRunner(executable: try fakeSmartctl(printing: "scan", exit: 0))
        // Скрипт друкує scan.json на будь-який виклик: сканування вдасться, читання дисків — ні.
        let result = await r.readAll()
        #expect(result.disks.count == 0)
        #expect(result.errors.count == 2)
    }

    @Test func readAllMissingExecutableReportsError() async {
        let r = SmartctlRunner(executable: URL(fileURLWithPath: "/nonexistent/smartctl"))
        let result = await r.readAll()
        #expect(result.disks.isEmpty)
        #expect(result.errors.count == 1)
    }
}
