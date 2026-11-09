import AppKit
import Carbon.HIToolbox
import CoreGraphics

nonisolated enum KeyModifier: String, Codable, Hashable, Sendable, CaseIterable {
    case command, option, control, shift

    /// Only these four count. `.function`, `.numericPad` and `.capsLock` are ignored (arrow keys carry `.function`/`.numericPad`).
    static func set(from flags: NSEvent.ModifierFlags) -> Set<KeyModifier> {
        var result: Set<KeyModifier> = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result
    }

    static func set(from flags: CGEventFlags) -> Set<KeyModifier> {
        var result: Set<KeyModifier> = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        return result
    }
}

nonisolated enum MediaKey: String, Codable, Hashable, Sendable {
    case playPause, next, previous, fastForward, rewind
}

nonisolated enum ControllerButton: String, Codable, Hashable, Sendable, CaseIterable {
    case dpadUp, dpadDown, dpadLeft, dpadRight   // left thumbstick feeds these too
    case a, b, x, y, leftShoulder, rightShoulder, menu, options, home
    case leftTrigger, rightTrigger               // M7: pressed past the threshold
}

/// One entry of `key-bindings.json` (D16).
nonisolated struct InputBinding: Codable, Hashable, Sendable {
    enum Trigger: Codable, Hashable, Sendable {
        case key(keyCode: UInt16, modifiers: [KeyModifier])   // array for stable JSON; matched as a Set
        case media(key: MediaKey)
        case controller(button: ControllerButton)
        case siriRemote(button: SiriRemoteButton)            // M7h L2: `{"siriRemote":{"button":"tv"}}`
    }

    var trigger: Trigger
    var command: RemoteCommand
    /// Also acts while another app is frontmost (key: needs Accessibility; controller: background monitoring).
    var isGlobal = false
    /// Free text for humans editing the JSON.
    var label: String?

    init(trigger: Trigger, command: RemoteCommand, isGlobal: Bool = false, label: String? = nil) {
        self.trigger = trigger
        self.command = command
        self.isGlobal = isGlobal
        self.label = label
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trigger = try container.decode(Trigger.self, forKey: .trigger)
        command = try container.decode(RemoteCommand.self, forKey: .command)
        isGlobal = try container.decodeIfPresent(Bool.self, forKey: .isGlobal) ?? false
        label = try container.decodeIfPresent(String.self, forKey: .label)
    }
}

nonisolated extension InputBinding.Trigger {
    /// M7 L9: key triggers match when key codes and modifier *sets* are equal (as lookups do); others by equality.
    func matches(_ other: InputBinding.Trigger) -> Bool {
        if case .key(let code, let modifiers) = self, case .key(let otherCode, let otherModifiers) = other {
            return code == otherCode && Set(modifiers) == Set(otherModifiers)
        }
        return self == other
    }

    /// M7h L2.
    var isSiriRemote: Bool {
        if case .siriRemote = self { return true }
        return false
    }

    /// M7h L9: a letter or digit key without modifiers (`kVK_ANSI_A…Z`, `kVK_ANSI_0…9`). It can't be global:
    /// it would fire while typing in other apps.
    var isPlainLetterOrDigit: Bool {
        guard case .key(let code, let modifiers) = self, modifiers.isEmpty else { return false }
        return Self.letterAndDigitKeyCodes.contains(Int(code))
    }

    private static let letterAndDigitKeyCodes: Set<Int> = [
        kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_I,
        kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R,
        kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y, kVK_ANSI_Z,
        kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7,
        kVK_ANSI_8, kVK_ANSI_9,
    ]

    /// Key modifiers sorted in `KeyModifier.allCases` order, duplicates removed.
    var normalized: InputBinding.Trigger {
        guard case .key(let code, let modifiers) = self else { return self }
        let set = Set(modifiers)
        return .key(keyCode: code, modifiers: KeyModifier.allCases.filter(set.contains))
    }
}
