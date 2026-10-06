import AppKit
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

    /// Key modifiers sorted in `KeyModifier.allCases` order, duplicates removed.
    var normalized: InputBinding.Trigger {
        guard case .key(let code, let modifiers) = self else { return self }
        let set = Set(modifiers)
        return .key(keyCode: code, modifiers: KeyModifier.allCases.filter(set.contains))
    }
}
