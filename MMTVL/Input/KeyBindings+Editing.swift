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
    /// Only Home bindings work in other apps (L11).
    func adding(_ trigger: InputBinding.Trigger, for command: RemoteCommand) -> KeyBindings {
        var result = removing(trigger).bindings
        result.append(InputBinding(trigger: trigger.normalized, command: command, isGlobal: command == .home,
                                   label: TriggerName.describe(trigger)))
        return KeyBindings(result)
    }

    /// Removes every binding matching `trigger` (L9: duplicates too).
    func removing(_ trigger: InputBinding.Trigger) -> KeyBindings {
        KeyBindings(bindings.filter { !$0.trigger.matches(trigger) })
    }

    /// Sets isGlobal on every binding matching `trigger`.
    func settingGlobal(_ isGlobal: Bool, for trigger: InputBinding.Trigger) -> KeyBindings {
        KeyBindings(bindings.map { binding in
            guard binding.trigger.matches(trigger) else { return binding }
            var changed = binding
            changed.isGlobal = isGlobal
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
