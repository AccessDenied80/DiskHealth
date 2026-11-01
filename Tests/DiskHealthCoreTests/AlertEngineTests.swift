import Foundation
import Testing
@testable import DiskHealthCore

@Suite struct AlertEngineTests {
    let t = Thresholds()

    func disk(wear: Int? = 10, crc: Int? = nil, pending: Int? = nil, smart: Bool = true) -> DiskInfo {
        DiskInfo(id: "SN1", deviceName: "/dev/disk0", deviceType: "nvme", model: "Test SSD",
                 smartAvailable: smart, smartPassed: smart ? true : nil, wearPercent: wear,
                 temperatureC: 30, pendingSectors: pending, crcErrors: crc)
    }

    @Test func firesOnceForWear() {
        var s = AlertState()
        let a1 = AlertEngine.diff(disks: [disk(wear: 85)], thresholds: t, state: &s)
        let a2 = AlertEngine.diff(disks: [disk(wear: 85)], thresholds: t, state: &s)
        #expect(a1.count == 1)
        #expect(a2.isEmpty)
    }

    @Test func refiresAfterClear() {
        var s = AlertState()
        var total = 0
        for w in [85, 50, 85] { total += AlertEngine.diff(disks: [disk(wear: w)], thresholds: t, state: &s).count }
        #expect(total == 2)
    }

    @Test func bothWearThresholds() {
        var s = AlertState()
        let a = AlertEngine.diff(disks: [disk(wear: 95)], thresholds: t, state: &s)
        #expect(a.count == 2)
        #expect(a.filter(\.critical).count == 1)
    }

    @Test func changedThresholdDropsStaleKeys() {
        var s = AlertState()
        var custom = Thresholds(); custom.wearWarning = 70
        _ = AlertEngine.diff(disks: [disk(wear: 85)], thresholds: t, state: &s)       // wear80 активний
        _ = AlertEngine.diff(disks: [disk(wear: 85)], thresholds: custom, state: &s)  // поріг змінено
        #expect(!s.active.contains("SN1|wear80"))
        #expect(s.active.contains("SN1|wear70"))
    }

    @Test func counterIncreaseFires() {
        var s = AlertState()
        #expect(AlertEngine.diff(disks: [disk(crc: 0)], thresholds: t, state: &s).isEmpty)
        #expect(AlertEngine.diff(disks: [disk(crc: 3)], thresholds: t, state: &s).count == 1)
        #expect(AlertEngine.diff(disks: [disk(crc: 3)], thresholds: t, state: &s).isEmpty)
    }

    @Test func firstSightPendingNonZeroFires() {
        var s = AlertState()
        #expect(AlertEngine.diff(disks: [disk(pending: 2)], thresholds: t, state: &s).count == 1)
    }

    @Test func noSmartNoAlerts() {
        var s = AlertState()
        var d = disk(wear: 99, smart: false)
        d.smartPassed = false
        #expect(AlertEngine.diff(disks: [d], thresholds: t, state: &s).isEmpty)
    }

    @Test func smartFailedFires() {
        var s = AlertState()
        var d = disk(); d.smartPassed = false
        let a = AlertEngine.diff(disks: [d], thresholds: t, state: &s)
        #expect(a.count == 1)
        #expect(a.first?.critical == true)
        #expect(a.first?.key == "SN1|smartFailed")
    }

    @Test func stateRoundTripsJSON() throws {
        var s = AlertState()
        _ = AlertEngine.diff(disks: [disk(wear: 85, crc: 1)], thresholds: t, state: &s)
        var back = try JSONDecoder().decode(AlertState.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        // Після перезапуску застосунку ті самі умови не дублюють сповіщення.
        #expect(AlertEngine.diff(disks: [disk(wear: 85, crc: 1)], thresholds: t, state: &back).isEmpty)
    }
}
