import Foundation
import Testing
@testable import MMTVL

struct KeychainTests {
    private let service = "dev.mmtvl.launcher.tests"

    @Test func roundTripInLoginKeychain() throws {
        let account = UUID().uuidString
        defer { try? Keychain.remove(account: account, service: service) }

        try Keychain.set("1234", account: account, service: service)
        #expect(try Keychain.string(account: account, service: service) == "1234")
        try Keychain.set("5678", account: account, service: service)
        #expect(try Keychain.string(account: account, service: service) == "5678")
        try Keychain.remove(account: account, service: service)
        #expect(try Keychain.string(account: account, service: service) == nil)
    }

    @Test func removingMissingItemDoesNotThrow() throws {
        try Keychain.remove(account: UUID().uuidString, service: service)
    }

    @Test func inMemoryPINStoreRoundTrips() throws {
        let store = PINStore.inMemory()
        #expect(store.load() == nil)
        try store.save("2468")
        #expect(store.load() == "2468")
        try store.remove()
        #expect(store.load() == nil)
        #expect(PINStore.inMemory("1111").load() == "1111")
    }
}
