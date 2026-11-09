import Carbon.HIToolbox
import Testing
@testable import MMTVL

struct TriggerNameTests {
    private func key(_ code: Int, _ modifiers: [KeyModifier] = []) -> InputBinding.Trigger {
        .key(keyCode: UInt16(code), modifiers: modifiers)
    }

    @Test func keyNames() {
        let expected: [(Int, String)] = [
            (kVK_PageUp, "Page Up"), (kVK_PageDown, "Page Down"), (kVK_Tab, "Tab"), (kVK_ContextualMenu, "Menu key"),
            (kVK_Return, "Return"), (kVK_Escape, "Escape"), (kVK_ANSI_A, "A"), (kVK_ANSI_7, "7"),
            (kVK_ANSI_Minus, "-"), (kVK_F13, "F13"), (kVK_ANSI_Keypad1, "Keypad 1"),
            (kVK_ANSI_KeypadEnter, "Keypad Enter"), (kVK_LeftArrow, "←"), (kVK_Home, "Home"),
        ]
        for (code, name) in expected {
            #expect(TriggerName.describe(key(code)) == name)
        }
    }

    @Test func modifiersComeFirstInSymbolOrder() {
        #expect(TriggerName.describe(key(kVK_F5, [.shift, .option])) == "⌥⇧ F5")
        #expect(TriggerName.describe(key(kVK_ANSI_K, [.command, .control])) == "⌃⌘ K")
    }

    @Test func unknownCode() {
        #expect(TriggerName.keyName(200) == nil)
        #expect(TriggerName.describe(key(200)) == "Key 200")
    }

    @Test func mediaAndController() {
        #expect(TriggerName.describe(.media(key: .playPause)) == "Media Play/Pause")
        #expect(TriggerName.describe(.media(key: .next)) == "Media Next")
        #expect(TriggerName.describe(.controller(button: .a)) == "Controller A")
        #expect(TriggerName.describe(.controller(button: .leftTrigger)) == "Controller Left Trigger")
        #expect(TriggerName.describe(.controller(button: .dpadUp)) == "Controller D-pad Up")
    }

    @Test func kinds() {
        #expect(TriggerName.kind(key(kVK_Tab)) == "Keyboard")
        #expect(TriggerName.kind(.media(key: .rewind)) == "Media key")
        #expect(TriggerName.kind(.controller(button: .y)) == "Game controller")
        #expect(TriggerName.kind(.siriRemote(button: .tv)) == "Siri Remote")
    }

    // MARK: M7h L2

    @Test func siriRemoteNames() {
        let expected: [(SiriRemoteButton, String)] = [
            (.tv, "Siri Remote TV"), (.back, "Siri Remote Back"), (.playPause, "Siri Remote Play/Pause"),
            (.volumeUp, "Siri Remote Volume Up"), (.volumeDown, "Siri Remote Volume Down"), (.mute, "Siri Remote Mute"),
            (.power, "Siri Remote Power"), (.up, "Siri Remote Up"), (.down, "Siri Remote Down"),
            (.left, "Siri Remote Left"), (.right, "Siri Remote Right"), (.select, "Siri Remote Select"),
        ]
        #expect(expected.count == SiriRemoteButton.allCases.count)
        for (button, name) in expected {
            #expect(TriggerName.describe(.siriRemote(button: button)) == name)
        }
    }
}
