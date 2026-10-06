import Foundation
import Testing
@testable import MMTVL

struct PairingTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func rightCodeIsAccepted() {
        var code = PairingCode(code: "1234", expires: start + PairingCode.lifetime)
        #expect(code.check("1234", now: start, makeCode: { "5678" }) == .accepted)
    }

    @Test func expiredCode() {
        var code = PairingCode(code: "1234", expires: start + PairingCode.lifetime)
        #expect(code.check("1234", now: start + PairingCode.lifetime + 1, makeCode: { "5678" }) == .expired)
    }

    @Test func fifthWrongCodeRotates() {
        var code = PairingCode(code: "1234", expires: start + PairingCode.lifetime)
        for failures in 1...4 {
            #expect(code.check("0000", now: start, makeCode: { "5678" }) == .rejected)
            #expect(code.failures == failures)
        }
        let rotated = PairingCode(code: "5678", expires: start + PairingCode.lifetime, failures: 0)
        #expect(code.check("0000", now: start, makeCode: { "5678" }) == .rotated(rotated))
        #expect(code == rotated)
    }

    @Test func randomCodesAreFourDigits() {
        for _ in 0..<200 {
            let code = PairingCode.random()
            #expect(code.count == 4 && code.allSatisfy(\.isASCII) && code.allSatisfy(\.isNumber))
        }
    }

    @Test func tokens() {
        let a = PhoneToken.make()
        let b = PhoneToken.make()
        #expect(a.count == 43)
        #expect(a.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        #expect(a != b)
        #expect(PhoneToken.hash("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    private func phone(_ name: String) -> PairedPhone {
        PairedPhone(id: UUID().uuidString, name: name, tokenHash: PhoneToken.hash(name), pairedAt: start)
    }

    @Test func inMemoryStore() throws {
        let store = PairedPhoneStore.inMemory()
        #expect(store.load().isEmpty)
        let phones = [phone("iPhone")]
        try store.save(phones)
        #expect(store.load() == phones)
    }

    @Test func keychainRoundTrip() throws {
        let service = "dev.mmtvl.launcher.tests"
        let account = UUID().uuidString
        defer { try? Keychain.remove(account: account, service: service) }

        let store = PairedPhoneStore.keychain(account: account, service: service)
        #expect(store.load().isEmpty)
        let phones = [phone("iPhone"), phone("Android phone")]
        try store.save(phones)
        #expect(store.load() == phones)
        try store.save([])
        #expect(store.load().isEmpty)
    }
}
