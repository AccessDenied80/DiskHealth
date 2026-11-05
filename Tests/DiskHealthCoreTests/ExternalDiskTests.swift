import Foundation
import Testing
@testable import DiskHealthCore

@Suite struct ExternalDiskParserTests {
    func realDisks() throws -> [ExternalDisk] {
        try ExternalDiskParser.parse(all: plistFixture("diskutil_external"), physical: plistFixture("diskutil_physical"))
    }

    func plist(_ o: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: o, format: .xml, options: 0)
    }

    @Test func apfsDiskOnRealData() throws {
        let disks = try realDisks()
        #expect(disks.map(\.id) == ["disk2"]) // disk4 — це образ DMG, а disk3 — контейнер диска disk2
        let d = try #require(disks.first)
        #expect(d.sizeBytes == 960_197_124_096)
        #expect(d.volumes == [ExternalVolume(name: "960", mountPoint: "/Volumes/960")])
        #expect(d.isMounted)
        #expect(d.mountTargets == ["disk3"])
    }

    @Test func unmountedVolumeStaysListed() throws {
        let all: [String: Any] = ["AllDisksAndPartitions": [
            ["DeviceIdentifier": "disk2", "Size": 100, "Partitions": [
                ["DeviceIdentifier": "disk2s2", "Content": "Apple_APFS", "Size": 90],
            ]],
            ["DeviceIdentifier": "disk3", "Size": 90, "Partitions": [],
             "APFSPhysicalStores": [["DeviceIdentifier": "disk2s2"]],
             "APFSVolumes": [["DeviceIdentifier": "disk3s1", "VolumeName": "Data", "OSInternal": false, "Size": 90]]],
        ]]
        let physical: [String: Any] = ["WholeDisks": ["disk2"]]
        let d = try #require(try ExternalDiskParser.parse(all: plist(all), physical: plist(physical)).first)
        #expect(d.volumes == [ExternalVolume(name: "Data", mountPoint: nil)])
        #expect(!d.isMounted)
        #expect(d.mountTargets == ["disk3"])
    }

    @Test func plainPartitionMountsThroughPhysicalDisk() throws {
        let all: [String: Any] = ["AllDisksAndPartitions": [
            ["DeviceIdentifier": "disk5", "Size": 64, "Partitions": [
                ["DeviceIdentifier": "disk5s1", "Content": "EFI", "VolumeName": "EFI", "Size": 1],
                ["DeviceIdentifier": "disk5s2", "Content": "Microsoft Basic Data", "VolumeName": "FLASH",
                 "MountPoint": "/Volumes/FLASH", "Size": 63],
            ]],
        ]]
        let d = try #require(try ExternalDiskParser.parse(all: plist(all), physical: plist(["WholeDisks": ["disk5"]])).first)
        #expect(d.volumes == [ExternalVolume(name: "FLASH", mountPoint: "/Volumes/FLASH")])
        #expect(d.mountTargets == ["disk5"])
    }

    @Test func systemVolumesAreHiddenButStillCountAsMounted() throws {
        let all: [String: Any] = ["AllDisksAndPartitions": [
            ["DeviceIdentifier": "disk2", "Size": 100, "Partitions": [["DeviceIdentifier": "disk2s2", "Content": "Apple_APFS"]]],
            ["DeviceIdentifier": "disk3", "Partitions": [], "APFSPhysicalStores": [["DeviceIdentifier": "disk2s2"]],
             "APFSVolumes": [
                ["DeviceIdentifier": "disk3s2", "VolumeName": "Preboot", "OSInternal": true, "MountPoint": "/System/Volumes/x"],
                ["DeviceIdentifier": "disk3s1", "VolumeName": "Data", "OSInternal": false],
             ]],
        ]]
        let d = try #require(try ExternalDiskParser.parse(all: plist(all), physical: plist(["WholeDisks": ["disk2"]])).first)
        #expect(d.volumes.map(\.name) == ["Data"])
        #expect(d.isMounted) // прихований том теж заважає безпечно від'єднати диск
    }

    @Test func diskWithoutVolumesCannotBeMounted() throws {
        let all: [String: Any] = ["AllDisksAndPartitions": [
            ["DeviceIdentifier": "disk6", "Size": 10, "Content": "", "Partitions": []],
        ]]
        let d = try #require(try ExternalDiskParser.parse(all: plist(all), physical: plist(["WholeDisks": ["disk6"]])).first)
        #expect(d.mountTargets.isEmpty)
        #expect(!d.isMounted)
    }

    @Test func garbageThrows() {
        #expect(throws: (any Error).self) { try ExternalDiskParser.parse(all: Data("nope".utf8), physical: Data("nope".utf8)) }
    }
}

@Suite struct DiskutilRunnerTests {
    /// Тимчасовий «diskutil»: пише аргументи в журнал і виконує заданий скрипт.
    func fake(_ body: String) throws -> (DiskutilRunner, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let log = dir.appendingPathComponent("calls.log")
        let url = dir.appendingPathComponent("diskutil")
        try "#!/bin/sh\necho \"$*\" >> '\(log.path)'\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return (DiskutilRunner(executable: url), log)
    }

    func disk(targets: [String]) -> ExternalDisk {
        ExternalDisk(id: "disk2", sizeBytes: 1, volumes: [], isMounted: true, mountTargets: targets)
    }

    @Test func unmountUsesWholeDiskWithoutForce() async throws {
        let (r, log) = try fake("exit 0")
        try await r.unmount(disk(targets: ["disk3"]))
        #expect(try String(contentsOf: log, encoding: .utf8) == "unmountDisk /dev/disk2\n")
    }

    @Test func busyDiskReportsDissenter() async throws {
        let (r, _) = try fake("""
        echo "Unmount of disk2 failed: at least one volume could not be unmounted" >&2
        echo "Unmount was dissented by PID 2134 (Preview)" >&2
        echo "Dissenter parent PPID 1 (launchd)" >&2
        exit 1
        """)
        await #expect(throws: DiskutilError.failed("Unmount was dissented by PID 2134 (Preview)")) {
            try await r.unmount(disk(targets: []))
        }
    }

    @Test func mountRunsEveryTarget() async throws {
        let (r, log) = try fake("exit 0")
        try await r.mount(disk(targets: ["disk3", "disk2"]))
        #expect(try String(contentsOf: log, encoding: .utf8) == "mountDisk /dev/disk3\nmountDisk /dev/disk2\n")
    }

    @Test func missingExecutableFails() async {
        let r = DiskutilRunner(executable: URL(fileURLWithPath: "/nonexistent/diskutil"))
        await #expect(throws: DiskutilError.self) { try await r.list() }
    }

    @Test func listParsesBothQueries() async throws {
        let all = try #require(Bundle.module.url(forResource: "diskutil_external", withExtension: "plist", subdirectory: "Fixtures"))
        let physical = try #require(Bundle.module.url(forResource: "diskutil_physical", withExtension: "plist", subdirectory: "Fixtures"))
        let (r, log) = try fake("""
        case "$*" in *physical*) cat '\(physical.path)' ;; *) cat '\(all.path)' ;; esac
        """)
        #expect(try await r.list().map(\.id) == ["disk2"])
        #expect(try String(contentsOf: log, encoding: .utf8).contains("list -plist external physical"))
    }
}
