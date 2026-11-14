import Foundation
import Testing
@testable import DiskHealthCore

@Suite struct DiskSpaceTests {
    @Test func internalDiskIsOneAPFSGroup() throws {
        let groups = try DiskSpaceCalculator.mountGroups(diskutilList: plistFixture("diskutil_internal"), wholeDisk: "disk0")
        #expect(groups.count == 1)
        let group = try #require(groups.first)
        #expect(group.contains("/")) // системний том змонтований як знімок
        #expect(group.contains("/System/Volumes/Data"))
    }

    @Test func externalAPFSDisk() throws {
        let groups = try DiskSpaceCalculator.mountGroups(diskutilList: plistFixture("diskutil_external"), wholeDisk: "disk2")
        #expect(groups == [["/Volumes/960"]])
    }

    @Test func plainPartitionsAreSeparateGroups() throws {
        let all: [String: Any] = ["AllDisksAndPartitions": [
            ["DeviceIdentifier": "disk5", "Partitions": [
                ["DeviceIdentifier": "disk5s1", "Content": "EFI", "MountPoint": "/Volumes/EFI"],
                ["DeviceIdentifier": "disk5s2", "Content": "Apple_APFS"],
                ["DeviceIdentifier": "disk5s3", "Content": "Microsoft Basic Data", "MountPoint": "/Volumes/SHARE"],
            ]],
            ["DeviceIdentifier": "disk6", "APFSPhysicalStores": [["DeviceIdentifier": "disk5s2"]],
             "APFSVolumes": [["DeviceIdentifier": "disk6s1", "MountPoint": "/Volumes/Mac"]]],
        ]]
        let data = try PropertyListSerialization.data(fromPropertyList: all, format: .xml, options: 0)
        #expect(try DiskSpaceCalculator.mountGroups(diskutilList: data, wholeDisk: "disk5") == [["/Volumes/Mac"], ["/Volumes/SHARE"]])
    }

    @Test func unknownDiskHasNoGroups() throws {
        #expect(try DiskSpaceCalculator.mountGroups(diskutilList: plistFixture("diskutil_internal"), wholeDisk: "disk9").isEmpty)
    }

    @Test func combineTakesBestValueInGroup() {
        // Реальні значення диска disk0: том VM повертає «доступно 0», його ігноруємо.
        let space = DiskSpaceCalculator.combine([[
            VolumeCapacity(totalBytes: 499_963_174_912, availableBytes: 261_212_198_897),
            VolumeCapacity(totalBytes: 499_963_174_912, availableBytes: 0),
        ]])
        #expect(space == DiskSpace(totalBytes: 499_963_174_912, availableBytes: 261_212_198_897))
        #expect(space?.usedPercent == 48)
        #expect(space?.usedBytes == 238_750_976_015)
    }

    @Test func combineSumsGroups() {
        let space = DiskSpaceCalculator.combine([
            [VolumeCapacity(totalBytes: 100, availableBytes: 10)],
            [VolumeCapacity(totalBytes: 100, availableBytes: 90)],
        ])
        #expect(space == DiskSpace(totalBytes: 200, availableBytes: 100))
        #expect(space?.usedPercent == 50)
    }

    @Test func combineWithoutDataIsNil() {
        #expect(DiskSpaceCalculator.combine([]) == nil)
        #expect(DiskSpaceCalculator.combine([[]]) == nil)
    }
}

@Suite struct SpaceAlertTests {
    let t = Thresholds()

    func item(_ usedPercent: Int64) -> SpaceAlertItem {
        SpaceAlertItem(id: "SN1", name: "Test SSD", space: DiskSpace(totalBytes: 100, availableBytes: 100 - usedPercent))
    }

    func run(_ pct: Int64, _ s: inout AlertState, _ th: Thresholds? = nil) -> [Alert] {
        AlertEngine.diffSpace([item(pct)], thresholds: th ?? t, state: &s)
    }

    @Test func firesOnceAboveThreshold() {
        var s = AlertState()
        let a = run(92, &s)
        #expect(a.count == 1)
        #expect(a.first?.title == "Test SSD")
        #expect(a.first?.body.hasPrefix("Disk is 92% full (threshold 90%).") == true)
        #expect(a.first?.critical == false)
        #expect(run(95, &s).isEmpty)
    }

    @Test func noRepeatWhileHoveringAroundThreshold() {
        var s = AlertState()
        var total = 0
        for pct: Int64 in [90, 89, 91, 87, 90] { total += run(pct, &s).count }
        #expect(total == 1)
    }

    @Test func rearmsAfterFreeingSpace() {
        var s = AlertState()
        var total = 0
        for pct: Int64 in [92, 80, 92] { total += run(pct, &s).count }
        #expect(total == 2)
    }

    @Test func belowThresholdNoAlert() {
        var s = AlertState()
        #expect(run(48, &s).isEmpty)
    }

    @Test func thresholdChangeDropsStaleKey() {
        var s = AlertState()
        _ = run(92, &s)
        var th = Thresholds(); th.fullWarning = 95
        _ = run(92, &s, th)
        #expect(!s.active.contains("SN1|full90"))
    }

    @Test func spaceKeysDoNotDisturbWearKeys() {
        var s = AlertState()
        s.active.insert("SN1|wear80")
        _ = run(92, &s)
        #expect(s.active.contains("SN1|wear80"))
    }
}
