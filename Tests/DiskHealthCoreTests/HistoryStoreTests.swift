import Foundation
import Testing
@testable import DiskHealthCore

@Suite struct HistoryStoreTests {
    func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("history.json")
    }

    let disk = DiskInfo(id: "SN1", deviceName: "/dev/disk0", deviceType: "nvme", model: "X",
                        smartAvailable: true, wearPercent: 50, temperatureC: 31, bytesWritten: 1000)

    @Test func appendAndReload() throws {
        let url = tempFile()
        let s = HistoryStore(fileURL: url)
        s.append([disk], at: Date())
        try s.save()

        let s2 = HistoryStore(fileURL: url)
        s2.load()
        let samples = s2.samples(for: "SN1")
        #expect(samples.count == 1)
        #expect(samples.first?.wearPercent == 50)
        #expect(samples.first?.bytesWritten == 1000)
    }

    @Test func prunesOlderThan365Days() {
        let s = HistoryStore(fileURL: tempFile())
        let now = Date()
        s.append([disk], at: now.addingTimeInterval(-400 * 86_400))
        s.append([disk], at: now)
        #expect(s.samples(for: "SN1").count == 1)
    }

    @Test func loadMissingFileIsEmpty() {
        let s = HistoryStore(fileURL: tempFile())
        s.load()
        #expect(s.samples(for: "SN1").isEmpty)
    }
}
