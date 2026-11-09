import Foundation
import Testing
@testable import MMTVL

struct PINFlowTests {
    @Test func verifyRightAndWrong() {
        var flow = PINFlow(purpose: .openSettings)
        #expect(flow.submit("0000", storedPIN: "1234") == .wrongPIN)
        #expect(flow.submit("1234", storedPIN: "1234") == .verified)
    }

    @Test func verifyWithoutStoredPINPasses() {
        var flow = PINFlow(purpose: .exitToDesktop)
        #expect(flow.submit("9999", storedPIN: nil) == .verified)
    }

    @Test func changeFlow() {
        var flow = PINFlow(purpose: .change)
        #expect(flow.stage == .verify)
        #expect(flow.submit("1234", storedPIN: "1234") == .next)
        #expect(flow.stage == .enterNew)
        #expect(flow.submit("5678", storedPIN: "1234") == .next)
        #expect(flow.stage == .confirmNew("5678"))
        #expect(flow.submit("5678", storedPIN: "1234") == .newPIN("5678"))
    }

    @Test func setNewMismatchStartsOver() {
        var flow = PINFlow(purpose: .setNew)
        #expect(flow.stage == .enterNew)
        #expect(flow.submit("1111", storedPIN: nil) == .next)
        #expect(flow.submit("2222", storedPIN: nil) == .mismatch)
        #expect(flow.stage == .enterNew)
    }

    /// M7h L15: the power menu's Relaunch and Restart.
    @Test func relaunchAndRestartVerify() {
        for purpose in [PINPurpose.relaunch, .restartMac] {
            var flow = PINFlow(purpose: purpose)
            #expect(flow.stage == .verify)
            #expect(flow.submit("4321", storedPIN: "1234") == .wrongPIN)
            #expect(flow.submit("1234", storedPIN: "1234") == .verified)
        }
    }

    @Test func turnOff() {
        var flow = PINFlow(purpose: .turnOff)
        #expect(flow.submit("4321", storedPIN: "1234") == .wrongPIN)
        #expect(flow.submit("1234", storedPIN: "1234") == .removed)
    }
}

struct PINLockoutTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func fifthFailureLocks() {
        var lockout = PINLockout()
        for _ in 0..<4 { lockout.recordFailure(at: start) }
        #expect(lockout.remaining(at: start) == nil)
        lockout.recordFailure(at: start)
        #expect(lockout.remaining(at: start) == 60)
        #expect(lockout.remaining(at: start.addingTimeInterval(59.5)) == 1)
        #expect(lockout.remaining(at: start.addingTimeInterval(60)) == nil)
        #expect(lockout.lockedUntil == nil)
    }

    @Test func successClears() {
        var lockout = PINLockout()
        for _ in 0..<5 { lockout.recordFailure(at: start) }
        lockout.recordSuccess()
        #expect(lockout.remaining(at: start) == nil)
        #expect(lockout.failures == 0)
    }
}
