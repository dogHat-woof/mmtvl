import Foundation
import Testing
@testable import MMTVL

struct PINEntryModelTests {
    /// A clock tests can move forward.
    private final class Clock {
        var now = Date(timeIntervalSinceReferenceDate: 1_000)
    }

    private func makeModel(_ purpose: PINPurpose, stored: String? = "1357", clock: Clock = Clock()) -> PINEntryModel {
        PINEntryModel(purpose: purpose, storedPIN: stored, lockout: PINLockout(), now: { clock.now })
    }

    /// Enters `code` and returns the last result.
    @discardableResult
    private func type(_ code: String, into model: PINEntryModel) -> PINEntryModel.Result? {
        var result: PINEntryModel.Result?
        for command in pinCommands(for: code, startRow: model.pad.row) {
            result = model.handle(command)
        }
        return result
    }

    @Test func rightPINVerifies() {
        let model = makeModel(.openSettings)
        #expect(type("1357", into: model) == .verified)
    }

    @Test func wrongPINShakesAndClears() {
        let model = makeModel(.openSettings)
        #expect(type("2468", into: model) == nil)
        #expect(model.message == "Wrong PIN")
        #expect(model.shakeTrigger == 1)
        #expect(model.pad.digits.isEmpty)
        #expect(model.pad.row == 0)
    }

    @Test func messageClearsOnNextDigit() {
        let model = makeModel(.openSettings)
        type("2468", into: model)
        _ = model.handle(.left)
        #expect(model.message == nil)
    }

    @Test func lockoutRefusesDigitsUntilItExpires() {
        let clock = Clock()
        let model = makeModel(.openSettings, clock: clock)
        for _ in 0..<5 { type("2468", into: model) }
        #expect(model.message == "Too many tries. Try again in 60 s.")
        clock.now += 30
        #expect(model.handle(.left) == nil)
        #expect(model.pad.digits.isEmpty)
        #expect(model.message == "Too many tries. Try again in 30 s.")
        clock.now += 30
        #expect(type("1357", into: model) == .verified)
    }

    @Test func backOnEmptyCancels() {
        let model = makeModel(.exitToDesktop)
        #expect(model.handle(.back) == .cancelled)
    }

    @Test func setNewFlow() {
        let model = makeModel(.setNew, stored: nil)
        #expect(model.title == "Enter a New PIN")
        #expect(type("2580", into: model) == nil)
        #expect(model.title == "Enter the New PIN Again")
        #expect(type("2580", into: model) == .newPIN("2580"))
    }

    @Test func setNewMismatchShowsMessage() {
        let model = makeModel(.setNew, stored: nil)
        type("1111", into: model)
        type("2222", into: model)
        #expect(model.message == "The PINs didn't match. Try again.")
        #expect(model.shakeTrigger == 1)
        #expect(model.title == "Enter a New PIN")
    }

    @Test func titles() {
        #expect(makeModel(.openSettings).title == "Enter PIN")
        #expect(makeModel(.openTile(id: "browser")).title == "Enter PIN")
        #expect(makeModel(.change).title == "Enter Current PIN")
        #expect(makeModel(.turnOff).title == "Enter Current PIN")
    }

    @Test func clickEntersDigits() {
        let model = makeModel(.openSettings, stored: "1590")
        #expect(model.enter(row: 0, column: 0) == nil)
        #expect(model.enter(row: 1, column: 1) == nil)
        #expect(model.enter(row: 2, column: 2) == nil)
        #expect(model.enter(row: 3, column: 0) == .verified)
    }
}
