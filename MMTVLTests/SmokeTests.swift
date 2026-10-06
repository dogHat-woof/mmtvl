import Testing
@testable import MMTVL

struct SmokeTests {
    @Test func appModuleLoads() {
        #expect(Bool(true))
    }

    @Test func mpvLinks() {
        #expect(LibraryVersions.mpvClientAPI >= 0x0002_0005)
    }
}
