import AppKit
import Carbon.HIToolbox
import os

nonisolated private let inputLogger = Logger(subsystem: "dev.mmtvl.launcher", category: "Input")

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
        // M7 L7 (D27): revision 2.
        key(kVK_PageUp, .channelUp, "Page Up"),
        key(kVK_PageDown, .channelDown, "Page Down"),
        key(kVK_Tab, .menu, "Tab"),
        key(kVK_ContextualMenu, .menu, "Menu key"),
        controller(.rightTrigger, .channelUp),
        controller(.leftTrigger, .channelDown),
        controller(.y, .menu),
        // M7h L2 (D43): revision 3. Siri Remote bindings are always global (the remote is the TV's remote).
        siriRemote(.tv, .home),
        siriRemote(.back, .back),
        siriRemote(.up, .up),
        siriRemote(.down, .down),
        siriRemote(.left, .left),
        siriRemote(.right, .right),
        siriRemote(.select, .select),
        siriRemote(.playPause, .playPause),
        siriRemote(.volumeUp, .volumeUp),
        siriRemote(.volumeDown, .volumeDown),
        siriRemote(.mute, .mute),
        siriRemote(.power, .power),
    ]

    /// M7 L7: `settings.json` `keyBindingsRevision` below this gets the newer defaults once.
    /// 2: Menu and Channel Up/Down (M7). 3: the Siri Remote, and no plain letter/digit global bindings (M7h L2, L9).
    static let currentRevision = 3

    /// Appends each default binding of `commands` (and passing `include`) whose trigger matches no existing binding,
    /// in the defaults' order.
    func addingDefaults(for commands: Set<RemoteCommand>,
                        where include: (InputBinding) -> Bool = { _ in true }) -> KeyBindings {
        var result = bindings
        for binding in Self.defaultBindings where commands.contains(binding.command) && include(binding) {
            if !result.contains(where: { $0.trigger.matches(binding.trigger) }) {
                result.append(binding)
            }
        }
        return KeyBindings(result)
    }

    /// What `migrated(fromRevision:)` changed, for the log.
    struct Migration: Equatable, Sendable {
        var bindings: KeyBindings
        /// M7h L9: the global bindings taken out.
        var removedGlobal: [InputBinding]
    }

    /// The bindings of a `key-bindings.json` written at `revision`, brought up to `currentRevision`.
    /// Unchanged when `revision` is already current.
    func migrated(fromRevision revision: Int) -> Migration {
        var result = self
        var removed: [InputBinding] = []
        if revision < 2 {
            result = result.addingDefaults(for: [.menu, .channelUp, .channelDown])
        }
        if revision < 3 {
            // M7h L2: the Siri Remote defaults only (their commands' other default triggers aren't brought back).
            result = result.addingSiriRemoteDefaults()
            // M7h L9: a global plain letter fired while typing in other apps (Remote Buddy's "a" as Home).
            removed = result.bindings.filter { $0.isGlobal && $0.trigger.isPlainLetterOrDigit }
            result.bindings.removeAll { $0.isGlobal && $0.trigger.isPlainLetterOrDigit }
        }
        return Migration(bindings: result, removedGlobal: removed)
    }

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

    /// M7h L2: the Siri Remote default bindings whose trigger isn't bound yet (no other default comes back).
    func addingSiriRemoteDefaults() -> KeyBindings {
        let siriCommands = Set(Self.defaultBindings.filter(\.trigger.isSiriRemote).map(\.command))
        return addingDefaults(for: siriCommands, where: { $0.trigger.isSiriRemote })
    }

    /// M7h: true when any binding has a Siri Remote trigger. A file without one (written by an older build after a
    /// rollback, at revision 3) gets the Siri Remote defaults again at launch.
    var hasSiriRemoteBindings: Bool {
        bindings.contains { $0.trigger.isSiriRemote }
    }

    /// M7h L2.
    func binding(siriRemote: SiriRemoteButton) -> InputBinding? {
        bindings.first { $0.trigger == .siriRemote(button: siriRemote) }
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

    private static func siriRemote(_ button: SiriRemoteButton, _ command: RemoteCommand) -> InputBinding {
        let trigger = InputBinding.Trigger.siriRemote(button: button)
        return InputBinding(trigger: trigger, command: command, isGlobal: true, label: TriggerName.describe(trigger))
    }
}

/// `key-bindings.json` as stored: a JSON array of bindings. M7h: decoded entry by entry, so an entry this build can't
/// read (a trigger or command from a newer build, a typo) is skipped instead of making the whole file corrupt.
/// Corrupt (so `JSONConfigFile` moves it to `.bak` and writes the defaults): a file that isn't a JSON array, and a
/// non-empty array none of whose entries decode. Skipped entries are dropped at the next save; `load(from:)` copies
/// the original to `.bak` first.
nonisolated struct StoredBindings: Codable, Equatable, Sendable {
    var bindings: [InputBinding]
    /// How many entries didn't decode (for the log; never their contents).
    var skippedCount = 0

    init(_ bindings: [InputBinding]) {
        self.bindings = bindings
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var bindings: [InputBinding] = []
        var skipped = 0
        while !container.isAtEnd {
            // `superDecoder()` moves past the entry whether or not it decodes.
            let entry = try container.superDecoder()
            if let binding = try? InputBinding(from: entry) {
                bindings.append(binding)
            } else {
                skipped += 1
            }
        }
        if bindings.isEmpty && skipped > 0 {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "No binding could be read"))
        }
        self.bindings = bindings
        skippedCount = skipped
    }

    /// Loads `file` (missing or corrupt: defaults, as `JSONConfigFile.load()`). When entries were skipped, copies the
    /// file as read to `<name>.bak` before anything saves over it (once per load, so once per launch).
    static func load(from file: JSONConfigFile<StoredBindings>) -> StoredBindings {
        let stored = file.load()
        if stored.skippedCount > 0 {
            do {
                try file.copyToBackup()
            } catch {
                inputLogger.error("Failed to back up \(file.url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return stored
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(bindings)
    }
}
