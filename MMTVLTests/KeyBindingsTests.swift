import AppKit
import Carbon.HIToolbox
import Testing
@testable import MMTVL

struct KeyBindingsTests {
    @Test(arguments: [
        (kVK_UpArrow, RemoteCommand.up),
        (kVK_DownArrow, .down),
        (kVK_LeftArrow, .left),
        (kVK_RightArrow, .right),
        (kVK_Return, .select),
        (kVK_ANSI_KeypadEnter, .select),
        (kVK_Escape, .back),
        (kVK_Delete, .back),
        (kVK_Space, .playPause),
        (kVK_Home, .home),
    ])
    func mapsKey(keyCode: Int, expected: RemoteCommand) {
        #expect(KeyBindings.command(keyCode: UInt16(keyCode), modifiers: []) == expected)
    }

    @Test func arrowKeysWithFunctionFlagStillMap() {
        // Arrow key events carry .function and .numericPad flags.
        #expect(KeyBindings.command(keyCode: UInt16(kVK_LeftArrow), modifiers: [.function, .numericPad]) == .left)
    }

    @Test func commandModifiedKeysPassThrough() {
        #expect(KeyBindings.command(keyCode: UInt16(kVK_RightArrow), modifiers: [.command]) == nil)
        #expect(KeyBindings.command(keyCode: UInt16(kVK_Return), modifiers: [.command, .shift]) == nil)
    }

    @Test func unknownKeyIsNil() {
        #expect(KeyBindings.command(keyCode: UInt16(kVK_ANSI_Q), modifiers: []) == nil)
    }
}
