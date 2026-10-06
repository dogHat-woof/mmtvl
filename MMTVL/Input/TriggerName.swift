import Carbon.HIToolbox

/// Human names of binding triggers for Settings → Remote Buttons (M7). Pure.
nonisolated enum TriggerName {
    /// "Page Up", "⌥⇧ F5", "Media Play/Pause", "Controller A", "Controller Left Trigger", "Key 200".
    /// Modifiers as symbols in ⌃⌥⇧⌘ order, then a space, then the key name.
    static func describe(_ trigger: InputBinding.Trigger) -> String {
        switch trigger {
        case .key(let code, let modifiers):
            let name = keyName(code) ?? "Key \(code)"
            let set = Set(modifiers)
            let symbols = modifierOrder.filter { set.contains($0.0) }.map(\.1).joined()
            return symbols.isEmpty ? name : "\(symbols) \(name)"
        case .media(let key):
            return "Media " + mediaName(key)
        case .controller(let button):
            return "Controller " + controllerName(button)
        }
    }

    /// "Keyboard", "Media key", "Game controller".
    static func kind(_ trigger: InputBinding.Trigger) -> String {
        switch trigger {
        case .key: "Keyboard"
        case .media: "Media key"
        case .controller: "Game controller"
        }
    }

    /// US layout names for Carbon `kVK_*` codes; nil for codes not in the table.
    static func keyName(_ code: UInt16) -> String? {
        keyNames[Int(code)]
    }

    private static let modifierOrder: [(KeyModifier, String)] = [
        (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
    ]

    private static func mediaName(_ key: MediaKey) -> String {
        switch key {
        case .playPause: "Play/Pause"
        case .next: "Next"
        case .previous: "Previous"
        case .fastForward: "Fast Forward"
        case .rewind: "Rewind"
        }
    }

    private static func controllerName(_ button: ControllerButton) -> String {
        switch button {
        case .dpadUp: "D-pad Up"
        case .dpadDown: "D-pad Down"
        case .dpadLeft: "D-pad Left"
        case .dpadRight: "D-pad Right"
        case .a: "A"
        case .b: "B"
        case .x: "X"
        case .y: "Y"
        case .leftShoulder: "Left Shoulder"
        case .rightShoulder: "Right Shoulder"
        case .menu: "Menu"
        case .options: "Options"
        case .home: "Home"
        case .leftTrigger: "Left Trigger"
        case .rightTrigger: "Right Trigger"
        }
    }

    private static let keyNames: [Int: String] = [
        // Letters
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
        kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
        kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        // Digits
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        // Punctuation
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`", kVK_ISO_Section: "§",
        // Keys independent of the layout
        kVK_Return: "Return", kVK_Tab: "Tab", kVK_Space: "Space", kVK_Delete: "Delete", kVK_Escape: "Escape",
        kVK_ForwardDelete: "Forward Delete", kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "Page Up",
        kVK_PageDown: "Page Down", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
        kVK_ContextualMenu: "Menu key", kVK_Help: "Help", kVK_CapsLock: "Caps Lock", kVK_Function: "Fn",
        kVK_VolumeUp: "Volume Up", kVK_VolumeDown: "Volume Down", kVK_Mute: "Mute",
        // Function keys
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
        kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19",
        kVK_F20: "F20",
        // Keypad
        kVK_ANSI_Keypad0: "Keypad 0", kVK_ANSI_Keypad1: "Keypad 1", kVK_ANSI_Keypad2: "Keypad 2",
        kVK_ANSI_Keypad3: "Keypad 3", kVK_ANSI_Keypad4: "Keypad 4", kVK_ANSI_Keypad5: "Keypad 5",
        kVK_ANSI_Keypad6: "Keypad 6", kVK_ANSI_Keypad7: "Keypad 7", kVK_ANSI_Keypad8: "Keypad 8",
        kVK_ANSI_Keypad9: "Keypad 9", kVK_ANSI_KeypadDecimal: "Keypad .", kVK_ANSI_KeypadMultiply: "Keypad *",
        kVK_ANSI_KeypadPlus: "Keypad +", kVK_ANSI_KeypadMinus: "Keypad -", kVK_ANSI_KeypadDivide: "Keypad /",
        kVK_ANSI_KeypadEquals: "Keypad =", kVK_ANSI_KeypadClear: "Keypad Clear", kVK_ANSI_KeypadEnter: "Keypad Enter",
        // JIS
        kVK_JIS_Yen: "¥", kVK_JIS_Underscore: "_", kVK_JIS_KeypadComma: "Keypad ,", kVK_JIS_Eisu: "Eisu",
        kVK_JIS_Kana: "Kana",
    ]
}
