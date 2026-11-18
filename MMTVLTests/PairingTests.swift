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
        var code = PairingCode(code: "1234", secret: "s", expires: start + PairingCode.lifetime)
        for failures in 1...4 {
            #expect(code.check("0000", now: start, makeCode: { "5678" }) == .rejected)
            #expect(code.failures == failures)
        }
        let rotated = PairingCode(code: "5678", secret: "s", expires: start + PairingCode.lifetime, failures: 0,
                                  totalFailures: 5)
        #expect(code.check("0000", now: start, makeCode: { "5678" }) == .rotated(rotated))
        #expect(code == rotated)
    }

    /// Security (pre-release review, high; re-review L1): the tenth wrong code in one pairing, across rotations, turns
    /// the typed code off for good; the secret still pairs until the pairing expires, and wrong secrets keep counting.
    @Test func tenthWrongCodeLocksOnlyTheCode() {
        var code = PairingCode(code: "1234", expires: start + PairingCode.lifetime)
        var results: [PairingCode.Check] = []
        for _ in 1...PairingCode.maxTotalFailures {
            results.append(code.check("0000", now: start, makeCode: { "5678" }))
        }
        #expect(results.last == .codeLocked)
        #expect(results.dropLast().allSatisfy { $0 != .codeLocked && $0 != .accepted })
        #expect(code.totalFailures == PairingCode.maxTotalFailures)
        #expect(code.isCodeLocked)

        // The current code is refused (and counts); no more rotations.
        let current = code.code
        #expect(code.check(current, now: start, makeCode: { "9999" }) == .codeLocked)
        #expect(code.code == current)
        #expect(code.check(String(repeating: "0", count: 32), now: start, makeCode: { "9999" }) == .codeLocked)
        #expect(code.totalFailures == PairingCode.maxTotalFailures + 2)
        #expect(code.check(code.secret, now: start, makeCode: { "9999" }) == .accepted)
        #expect(code.check(code.secret, now: start + PairingCode.lifetime, makeCode: { "9999" }) == .expired)
    }

    /// Security (pre-release review, high): the QR code's 128-bit secret pairs like the code; an unchecked attempt fails.
    @Test func secretIsAcceptedAndRandom() {
        var code = PairingCode(code: "1234", expires: start + PairingCode.lifetime)
        #expect(code.secret.count == 32 && code.secret.allSatisfy(\.isHexDigit))
        #expect(code.secret != PairingCode.makeSecret())
        #expect(code.check(code.secret, now: start, makeCode: { "5678" }) == .accepted)
        #expect(code.check(String(code.secret.dropLast()), now: start, makeCode: { "5678" }) == .rejected)
        #expect(code.fail(now: start, makeCode: { "5678" }) == .rejected)
        #expect(code.totalFailures == 2)
        var empty = PairingCode(code: "1234", secret: "", expires: start + PairingCode.lifetime)
        #expect(empty.check("", now: start, makeCode: { "5678" }) == .rejected)
    }

    /// Pre-release lows (e): only 4 ASCII digits are throttled as typed codes; renewing changes code and secret, keeps
    /// the expiry and the total of wrong codes.
    @Test func codeAttemptsAndRenewal() {
        #expect(PairingCode.isCodeAttempt("0420"))
        for attempt in ["", "123", "12345", "12a4", "١٢٣٤", String(repeating: "a", count: 32)] {
            #expect(!PairingCode.isCodeAttempt(attempt), "\(attempt)")
        }
        var code = PairingCode(code: "1234", expires: start + PairingCode.lifetime, failures: 3, totalFailures: 7)
        let oldSecret = code.secret
        code.renew(makeCode: { "5678" })
        #expect(code.code == "5678")
        #expect(code.secret != oldSecret && code.secret.count == 32)
        #expect(code.expires == start + PairingCode.lifetime)
        #expect(code.failures == 0)
        #expect(code.totalFailures == 7)
        #expect(code.check(oldSecret, now: start, makeCode: { "9999" }) == .rejected)
        #expect(code.check(code.secret, now: start, makeCode: { "9999" }) == .accepted)
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
