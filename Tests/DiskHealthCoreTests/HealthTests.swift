import Foundation
import Testing
@testable import DiskHealthCore

@Suite struct HealthTests {
    let t = Thresholds()

    func nvme() throws -> DiskInfo { try SmartParser.parseDisk(fixture("nvme_apple")) }

    @Test func okDisk() throws {
        let r = HealthEvaluator.evaluate(try nvme(), t)
        #expect(r.level == .ok)
        #expect(r.healthPercent == 50)
    }

    @Test func wearWarning() throws {
        var d = try nvme(); d.wearPercent = 85
        #expect(HealthEvaluator.evaluate(d, t).level == .warning)
    }

    @Test func wearCritical() throws {
        var d = try nvme(); d.wearPercent = 90
        let r = HealthEvaluator.evaluate(d, t)
        #expect(r.level == .critical)
        #expect(r.reasons.contains("Знос 90%"))
    }

    @Test func smartFailed() throws {
        var d = try nvme(); d.smartPassed = false
        let r = HealthEvaluator.evaluate(d, t)
        #expect(r.level == .critical)
        #expect(r.reasons.contains("SMART: FAILED"))
    }

    @Test func criticalWarningNonZero() throws {
        var d = try nvme(); d.criticalWarning = 4
        #expect(HealthEvaluator.evaluate(d, t).level == .critical)
    }

    @Test func mediaErrors() throws {
        var d = try nvme(); d.mediaErrors = 1
        #expect(HealthEvaluator.evaluate(d, t).level == .critical)
    }

    @Test func hot() throws {
        var d = try nvme(); d.temperatureC = 60
        let r = HealthEvaluator.evaluate(d, t)
        #expect(r.level == .warning)
        #expect(r.reasons.contains("Температура 60 °C"))
    }

    @Test func pendingSectors() throws {
        let d = try SmartParser.parseDisk(fixture("sata_ssd"))
        #expect(HealthEvaluator.evaluate(d, t).level == .warning)
    }

    @Test func noSmart() throws {
        let d = try SmartParser.parseDisk(fixture("usb_nosmart"))
        let r = HealthEvaluator.evaluate(d, t)
        #expect(r.level == .unknown)
        #expect(r.reasons.contains("SMART недоступний"))
        #expect(r.healthPercent == nil)
    }

    @Test func customThresholds() throws {
        var custom = Thresholds(); custom.wearWarning = 40
        #expect(HealthEvaluator.evaluate(try nvme(), custom).level == .warning)
    }

    @Test func overallIgnoresUnknown() {
        #expect(HealthLevel.overall([.unknown, .ok]) == .ok)
        #expect(HealthLevel.overall([.unknown]) == .unknown)
        #expect(HealthLevel.overall([.ok, .critical, .warning]) == .critical)
    }
}
