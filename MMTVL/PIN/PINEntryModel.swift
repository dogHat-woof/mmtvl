import Foundation
import Observation

/// The PIN screen's state: keypad, flow, lockout and messages, driven by `RemoteCommand`s (D20).
@Observable
final class PINEntryModel {
    enum Result: Equatable {
        case cancelled, verified, removed
        case newPIN(String)
    }

    let purpose: PINPurpose
    private(set) var pad = PINPad()
    private(set) var flow: PINFlow
    private(set) var lockout: PINLockout
    private(set) var message: String?
    private(set) var shakeTrigger = 0
    @ObservationIgnored private let storedPIN: String?
    @ObservationIgnored private let now: () -> Date

    init(purpose: PINPurpose, storedPIN: String?, lockout: PINLockout, now: @escaping () -> Date = Date.init) {
        self.purpose = purpose
        flow = PINFlow(purpose: purpose)
        self.storedPIN = storedPIN
        self.lockout = lockout
        self.now = now
    }

    var title: String {
        switch flow.stage {
        case .verify:
            switch purpose {
            case .change, .turnOff: "Enter Current PIN"
            case .quit: "Enter PIN to quit MMTVL"
            case .relaunch: "Enter PIN to relaunch MMTVL"
            case .restartMac: "Enter PIN to restart the Mac mini"
            default: "Enter PIN"
            }
        case .enterNew:
            "Enter a New PIN"
        case .confirmNew:
            "Enter the New PIN Again"
        }
    }

    func handle(_ command: RemoteCommand) -> Result? {
        let entersDigit = command == .left || command == .select || command == .right
        if entersDigit && refuseIfLockedOut() { return nil }
        return process(pad.handle(command))
    }

    /// Mouse click on the small keypad.
    func enter(row: Int, column: Int) -> Result? {
        if refuseIfLockedOut() { return nil }
        return process(pad.enter(row: row, column: column))
    }

    /// Only the verify stage counts toward and honors the lockout.
    private func refuseIfLockedOut() -> Bool {
        guard flow.stage == .verify, let seconds = lockout.remaining(at: now()) else { return false }
        message = Self.lockoutMessage(seconds)
        return true
    }

    private func process(_ event: PINPad.Event) -> Result? {
        switch event {
        case .cancelled:
            return .cancelled
        case .ignored:
            return nil
        case .changed:
            // The first new digit after an error clears the message.
            if !pad.digits.isEmpty { message = nil }
            return nil
        case .submitted(let code):
            return submit(code)
        }
    }

    private func submit(_ code: String) -> Result? {
        switch flow.submit(code, storedPIN: storedPIN) {
        case .next:
            pad.clear()
            message = nil
            return nil
        case .wrongPIN:
            lockout.recordFailure(at: now())
            shakeTrigger += 1
            pad.clear()
            message = lockout.remaining(at: now()).map(Self.lockoutMessage) ?? "Wrong PIN"
            return nil
        case .mismatch:
            shakeTrigger += 1
            pad.clear()
            message = "The PINs didn't match. Try again."
            return nil
        case .verified:
            lockout.recordSuccess()
            return .verified
        case .removed:
            lockout.recordSuccess()
            return .removed
        case .newPIN(let pin):
            return .newPIN(pin)
        }
    }

    private static func lockoutMessage(_ seconds: Int) -> String {
        "Too many tries. Try again in \(seconds) s."
    }
}
