import Foundation
import Testing

@Test func fixtureLoads() {
    #expect(Bundle.module.url(forResource: "nvme_apple", withExtension: "json", subdirectory: "Fixtures") != nil)
}
