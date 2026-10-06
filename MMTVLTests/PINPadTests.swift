import Testing
@testable import MMTVL

struct PINPadTests {
    @Test func rowMovesAreClamped() {
        var pad = PINPad()
        #expect(pad.handle(.up) == .ignored)
        for _ in 0..<5 { _ = pad.handle(.down) }
        #expect(pad.row == 3)
        #expect(pad.handle(.down) == .ignored)
    }

    @Test func columnsEnterTheHighlightedRow() {
        var pad = PINPad()
        _ = pad.handle(.down)
        #expect(pad.handle(.left) == .changed)
        #expect(pad.handle(.select) == .changed)
        #expect(pad.handle(.right) == .changed)
        #expect(pad.digits == [4, 5, 6])
        #expect(pad.row == 1)
    }

    @Test func zeroRowOnlyAcceptsSelect() {
        var pad = PINPad()
        for _ in 0..<3 { _ = pad.handle(.down) }
        #expect(pad.handle(.left) == .ignored)
        #expect(pad.handle(.right) == .ignored)
        #expect(pad.digits.isEmpty)
        #expect(pad.handle(.select) == .changed)
        #expect(pad.digits == [0])
    }

    @Test func fourthDigitSubmits() {
        var pad = PINPad()
        var events: [PINPad.Event] = []
        for command in pinCommands(for: "1290") { events.append(pad.handle(command)) }
        #expect(events.last == .submitted("1290"))
        #expect(pad.handle(.select) == .ignored)
        #expect(pad.digits == [1, 2, 9, 0])
    }

    @Test func backDeletesThenCancels() {
        var pad = PINPad()
        _ = pad.handle(.left)
        #expect(pad.handle(.back) == .changed)
        #expect(pad.digits.isEmpty)
        #expect(pad.handle(.back) == .cancelled)
    }

    @Test func clearResetsDigitsAndRow() {
        var pad = PINPad()
        _ = pad.handle(.down)
        _ = pad.handle(.left)
        pad.clear()
        #expect(pad.digits.isEmpty)
        #expect(pad.row == 0)
    }

    @Test func clickClampsColumnAndMovesHighlight() {
        var pad = PINPad()
        #expect(pad.enter(row: 2, column: 9) == .changed)
        #expect(pad.digits == [9])
        #expect(pad.row == 2)
        _ = pad.enter(row: 3, column: 2)
        #expect(pad.digits == [9, 0])
        #expect(pad.enter(row: 7, column: 0) == .ignored)
    }

    @Test func otherCommandsAreIgnored() {
        var pad = PINPad()
        for command in [RemoteCommand.home, .playPause, .fastForward, .rewind] {
            #expect(pad.handle(command) == .ignored)
        }
    }

    @Test func helperProducesExpectedPresses() {
        #expect(pinCommands(for: "1357") == [.left, .right, .down, .select, .down, .left])
        #expect(pinCommands(for: "0") == [.down, .down, .down, .select])
    }
}
