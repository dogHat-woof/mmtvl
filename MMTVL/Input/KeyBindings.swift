import AppKit
import Carbon.HIToolbox

/// The remappable trigger → command table (D16), stored in `key-bindings.json` as `[InputBinding]`.
nonisolated struct KeyBindings: Equatable, Sendable {
    static let fileName = "key-bindings.json"

    var bindings: [InputBinding]

    init(_ bindings: [InputBinding]) {
        self.bindings = bindings
    }

    static let defaults = KeyBindings(defaultBindings)

    static let defaultBindings: [InputBinding] = [
        key(kVK_LeftArrow, .left, "←"),
        key(kVK_RightArrow, .right, "→"),
        key(kVK_DownArrow, .down, "↓"),
        key(kVK_UpArrow, .up, "↑"),
        key(kVK_Return, .select, "Return"),
        key(kVK_ANSI_KeypadEnter, .select, "Keypad Enter"),
        key(kVK_Escape, .back, "Escape"),
        key(kVK_Delete, .back, "Delete"),
        key(kVK_Space, .playPause, "Space"),
        key(kVK_Home, .home, "Home key (fn+←)", isGlobal: true),
        InputBinding(trigger: .media(key: .playPause), command: .playPause, label: "Media play/pause"),
        InputBinding(trigger: .media(key: .next), command: .fastForward, label: "Media next"),
        InputBinding(trigger: .media(key: .previous), command: .rewind, label: "Media previous"),
        InputBinding(trigger: .media(key: .fastForward), command: .fastForward, label: "Media fast forward"),
        InputBinding(trigger: .media(key: .rewind), command: .rewind, label: "Media rewind"),
        controller(.dpadUp, .up),
        controller(.dpadDown, .down),
        controller(.dpadLeft, .left),
        controller(.dpadRight, .right),
        controller(.a, .select),
        controller(.b, .back),
        controller(.x, .playPause),
        controller(.leftShoulder, .rewind),
        controller(.rightShoulder, .fastForward),
        controller(.home, .home, isGlobal: true),
        controller(.menu, .home, isGlobal: true),
    ]

    /// Exact modifier match: `Set(binding.modifiers) == modifiers`. First match wins.
    /// No default binding has ⌘, so ⌘-combos never match and always pass through.
    func binding(keyCode: UInt16, modifiers: Set<KeyModifier>) -> InputBinding? {
        bindings.first { binding in
            guard case .key(let code, let bindingModifiers) = binding.trigger else { return false }
            return code == keyCode && Set(bindingModifiers) == modifiers
        }
    }

    func binding(media: MediaKey) -> InputBinding? {
        bindings.first { $0.trigger == .media(key: media) }
    }

    func binding(controller: ControllerButton) -> InputBinding? {
        bindings.first { $0.trigger == .controller(button: controller) }
    }

    /// Convenience kept for tests and the local monitor.
    func command(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> RemoteCommand? {
        binding(keyCode: keyCode, modifiers: KeyModifier.set(from: modifiers))?.command
    }

    private static func key(_ keyCode: Int, _ command: RemoteCommand, _ label: String, isGlobal: Bool = false) -> InputBinding {
        InputBinding(trigger: .key(keyCode: UInt16(keyCode), modifiers: []), command: command, isGlobal: isGlobal, label: label)
    }

    private static func controller(_ button: ControllerButton, _ command: RemoteCommand, isGlobal: Bool = false) -> InputBinding {
        InputBinding(trigger: .controller(button: button), command: command, isGlobal: isGlobal, label: "Controller \(button.rawValue)")
    }
}
