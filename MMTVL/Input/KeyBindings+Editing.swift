/// Pure editing for Settings → Remote Buttons (M7 L8–L11).
nonisolated extension KeyBindings {
    /// L10: their last binding can't be removed.
    static let essentialCommands: Set<RemoteCommand> = [.up, .down, .left, .right, .select, .back]

    /// In file order.
    func bindings(for command: RemoteCommand) -> [InputBinding] {
        bindings.filter { $0.command == command }
    }

    /// The first binding whose trigger matches.
    func binding(matching trigger: InputBinding.Trigger) -> InputBinding? {
        bindings.first { $0.trigger.matches(trigger) }
    }

    /// L8: removes every binding matching `trigger` (it moves from another command), then appends it to `command`.
    /// New Home bindings work in other apps (L11), except a plain letter or digit (M7h L9); Power and Power Menu ones
    /// can be switched on in Settings (M7h step 12); Siri Remote bindings always do (M7h L2).
    func adding(_ trigger: InputBinding.Trigger, for command: RemoteCommand) -> KeyBindings {
        var result = removing(trigger).bindings
        let isGlobal = trigger.isSiriRemote || (command == .home && Self.canSetGlobal(trigger))
        result.append(InputBinding(trigger: trigger.normalized, command: command, isGlobal: isGlobal,
                                   label: TriggerName.describe(trigger)))
        return KeyBindings(result)
    }

    /// M7h L9: false for a letter or digit key without modifiers (it would fire while typing in other apps).
    static func canSetGlobal(_ trigger: InputBinding.Trigger) -> Bool {
        !trigger.isPlainLetterOrDigit
    }

    /// Removes every binding matching `trigger` (L9: duplicates too).
    func removing(_ trigger: InputBinding.Trigger) -> KeyBindings {
        KeyBindings(bindings.filter { !$0.trigger.matches(trigger) })
    }

    /// Sets isGlobal on every binding matching `trigger`. M7h L9: a plain letter or digit stays non-global;
    /// L2: a Siri Remote binding stays global.
    func settingGlobal(_ isGlobal: Bool, for trigger: InputBinding.Trigger) -> KeyBindings {
        KeyBindings(bindings.map { binding in
            guard binding.trigger.matches(trigger) else { return binding }
            var changed = binding
            changed.isGlobal = binding.trigger.isSiriRemote || (isGlobal && Self.canSetGlobal(binding.trigger))
            return changed
        })
    }

    /// L10: false when the trigger's command is essential and every one of its bindings uses this trigger.
    func canRemove(_ trigger: InputBinding.Trigger) -> Bool {
        guard let command = binding(matching: trigger)?.command, Self.essentialCommands.contains(command) else {
            return true
        }
        return bindings(for: command).contains { !$0.trigger.matches(trigger) }
    }
}
