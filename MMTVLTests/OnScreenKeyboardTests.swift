import Testing
@testable import MMTVL

struct OnScreenKeyboardTests {
    private func press(_ keyboard: inout OnScreenKeyboard, _ commands: RemoteCommand...) -> OnScreenKeyboard.Outcome {
        var last = OnScreenKeyboard.Outcome.none
        for command in commands { last = keyboard.handle(command) }
        return last
    }

    @Test func selectTypesTheFocusedLetter() {
        var keyboard = OnScreenKeyboard()
        #expect(keyboard.handle(.select) == .changed)
        #expect(press(&keyboard, .right, .right, .select) == .changed)
        #expect(press(&keyboard, .down, .select) == .changed)
        #expect(keyboard.text == "acj")
    }

    @Test func deleteKeyAndPlayPauseRemoveTheLastCharacter() {
        var keyboard = OnScreenKeyboard(text: "abc")
        #expect(keyboard.handle(.playPause) == .changed)
        #expect(keyboard.text == "ab")
        // Bottom row: Space, Delete, 123. Down four times from `a` lands on Space.
        _ = press(&keyboard, .down, .down, .down, .down, .right)
        #expect(keyboard.focusedKey == .delete)
        #expect(keyboard.handle(.select) == .changed)
        #expect(keyboard.text == "a")
        _ = keyboard.handle(.select)
        #expect(keyboard.text == "")
        #expect(keyboard.handle(.select) == .none)
        #expect(keyboard.handle(.playPause) == .none)
    }

    @Test func spaceTypesASpace() {
        var keyboard = OnScreenKeyboard(text: "nba")
        _ = press(&keyboard, .down, .down, .down, .down)
        #expect(keyboard.focusedKey == .space)
        #expect(keyboard.handle(.select) == .changed)
        #expect(keyboard.text == "nba ")
    }

    @Test func modeKeySwitchesToDigitsAndBack() {
        var keyboard = OnScreenKeyboard()
        _ = press(&keyboard, .down, .down, .down, .down, .right, .right)
        #expect(keyboard.focusedKey == .mode(.digits))
        _ = keyboard.handle(.select)
        #expect(keyboard.mode == .digits)
        #expect(keyboard.focusedKey == .mode(.letters))
        #expect(keyboard.rows.count == 3)
        _ = press(&keyboard, .up, .up)
        #expect(keyboard.focusedKey == .character("6"))  // abc starts at column 5
        #expect(keyboard.handle(.select) == .changed)
        #expect(keyboard.text == "6")
        _ = press(&keyboard, .down, .down, .select)
        #expect(keyboard.mode == .letters)
        #expect(keyboard.focusedKey == .mode(.digits))
    }

    @Test func textIsCappedAt40Characters() {
        var keyboard = OnScreenKeyboard(text: String(repeating: "x", count: 45))
        #expect(keyboard.text.count == 40)
        #expect(keyboard.handle(.select) == .none)
        #expect(keyboard.text.count == 40)
        keyboard.apply(TextEdit(deletions: 0, insertion: "more"))
        #expect(keyboard.text.count == 40)
    }

    @Test func arrowsClampOnShortRows() {
        var keyboard = OnScreenKeyboard()
        // `g` (last column) down to `n`, `u`, then the five-key row clamps to `z`.
        _ = press(&keyboard, .right, .right, .right, .right, .right, .right)
        #expect(keyboard.focusedKey == .character("g"))
        _ = press(&keyboard, .down, .down, .down)
        #expect(keyboard.focusedKey == .character("z"))
        // `z` is column 4: Delete covers columns 3–4.
        _ = keyboard.handle(.down)
        #expect(keyboard.focusedKey == .delete)
        // Up from Delete lands on its first column, `y`.
        _ = keyboard.handle(.up)
        #expect(keyboard.focusedKey == .character("y"))
        // Down from the bottom row and Left from a row's first key do nothing.
        _ = press(&keyboard, .down, .down)
        #expect(keyboard.focusedKey == .delete)
        _ = press(&keyboard, .left, .left)
        #expect(keyboard.focusedKey == .space)
    }

    @Test func edgesLeaveTheKeyboard() {
        var keyboard = OnScreenKeyboard()
        #expect(keyboard.handle(.up) == .leaveUp)
        #expect(press(&keyboard, .right, .right, .right, .right, .right, .right) == .none)
        #expect(keyboard.handle(.right) == .leaveRight)
        #expect(keyboard.handle(.back) == .back)
        #expect(keyboard.handle(.menu) == .none)
        #expect(keyboard.handle(.channelUp) == .none)
        #expect(keyboard.handle(.channelDown) == .none)
        #expect(keyboard.text == "")
    }

    @Test func applyDeletesThenInserts() {
        var keyboard = OnScreenKeyboard(text: "lakers")
        keyboard.apply(TextEdit.between("lakers", "lake"))
        #expect(keyboard.text == "lake")
        keyboard.apply(TextEdit(deletions: 2, insertion: "kers game"))
        #expect(keyboard.text == "lakers game")
        keyboard.apply(TextEdit(deletions: 99, insertion: "nba"))
        #expect(keyboard.text == "nba")
    }

    @Test func wideKeysLineUpWithTheGrid() {
        let full = OnScreenKeyboardView.width(span: 7)
        #expect(abs(full - Theme.keyboardWidth) < 0.001)
        let row = OnScreenKeyboardView.width(span: 3) + OnScreenKeyboardView.width(span: 2) * 2 + Theme.keyboardKeySpacing * 2
        #expect(abs(row - Theme.keyboardWidth) < 0.001)
    }
}
