import Foundation
import Testing
@testable import DiskHealthCore

@Suite struct SmartParserTests {
    @Test func nvmeAppleParses() throws {
        let d = try SmartParser.parseDisk(fixture("nvme_apple"))
        #expect(d.model == "APPLE SSD AP0512M")
        #expect(d.serial == "S0TESTSERIAL0001")
        #expect(d.id == "S0TESTSERIAL0001")
        #expect(d.deviceName == "/dev/disk0")
        #expect(d.deviceType == "nvme")
        #expect(d.smartAvailable)
        #expect(d.smartPassed == true)
        #expect(d.criticalWarning == 0)
        #expect(d.wearPercent == 50)
        #expect(d.availableSpare == 100)
        #expect(d.temperatureC == 31)
        #expect(d.powerOnHours == 5516)
        #expect(d.powerCycles == 245)
        #expect(d.unsafeShutdowns == 64)
        #expect(d.mediaErrors == 0)
        #expect(d.bytesWritten == 1_183_583_581 * 512_000)
        #expect(d.bytesRead == 1_265_764_929 * 512_000)
        #expect(d.messages.count == 1)
    }

    @Test func nvmeMissingCapacityIsNilNotCrash() throws {
        let d = try SmartParser.parseDisk(fixture("nvme_apple"))
        #expect(d.capacityBytes == nil)
    }

    @Test func sataParses() throws {
        let d = try SmartParser.parseDisk(fixture("sata_ssd"))
        #expect(d.deviceType == "sat")
        #expect(d.wearPercent == 3)
        #expect(d.pendingSectors == 2)
        #expect(d.reallocatedSectors == 0)
        #expect(d.crcErrors == 0)
        #expect(d.capacityBytes == 500_107_862_016)
        #expect(d.bytesWritten == 2000 * 512)
        #expect(d.temperatureC == 35)
        #expect(d.mediaErrors == nil)
    }

    @Test func usbNoSmart() throws {
        let d = try SmartParser.parseDisk(fixture("usb_nosmart"))
        #expect(!d.smartAvailable)
        #expect(d.smartPassed == nil)
        #expect(d.wearPercent == nil)
        #expect(d.id == "/dev/disk5")
        #expect(d.model == "USB Flash")
    }

    @Test func scanParses() throws {
        let devs = try SmartParser.parseScan(fixture("scan"))
        #expect(devs.count == 2)
        #expect(devs[1] == ScannedDevice(name: "/dev/disk4", type: "sat", proto: "ATA"))
    }

    @Test func garbageThrows() {
        #expect(throws: (any Error).self) { try SmartParser.parseDisk(Data("not json".utf8)) }
    }
}
