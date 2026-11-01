import Testing
@testable import DiskHealthCore

@Suite struct IOKitLookupTests {
    @Test func nonServicePathIsNil() {
        #expect(IOKitLookup.wholeMedia(forServicePath: "/dev/disk0") == nil)
    }

    @Test func unknownServicePathIsNil() {
        #expect(IOKitLookup.wholeMedia(forServicePath: "IOService:/NoSuchDevice@0") == nil)
    }
}
