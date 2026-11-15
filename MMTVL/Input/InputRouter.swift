import AppKit
import Observation
import os

/// Central input funnel (D3): every source (local keys, the global event tap, game controllers)
/// turns its input into `RemoteCommand`s and calls `dispatch(_:isGlobal:)`.
@Observable
final class InputRouter {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "InputRouter")

    /// The active screen. Returns `true` if the command was handled; only then is the event swallowed.
    /// The flag is true for a held key's or button's auto-repeat (M7g: Settings ignores repeated Left/Right).
    @ObservationIgnored var handler: ((_ command: RemoteCommand, _ isRepeat: Bool) -> Bool)?
    /// A global binding fired while another app is frontmost.
    @ObservationIgnored var onGlobalCommand: ((RemoteCommand) -> Void)?
    /// Called for every command dispatched while the launcher is active (cursor auto-hide).
    @ObservationIgnored var onCommandDispatched: (() -> Void)?
    @ObservationIgnored var bindings: KeyBindings
    /// M7 L21: mouse wheel / trackpad scrolling (`scrollingDeltaY`, `hasPreciseScrollingDeltas`). The event passes on.
    @ObservationIgnored var onScrollWheel: ((CGFloat, Bool) -> Void)?
    /// M7 L8: set while Settings learns a button; the next trigger is captured instead of dispatched.
    @ObservationIgnored var captureHandler: ((InputBinding.Trigger) -> Void)?
    /// M7m L19 (QA step 6, finding 5): a trigger went to `captureHandler` (every source's learnt press passes
    /// `capture(_:)`); the idle dimmer wakes.
    @ObservationIgnored var onTriggerCaptured: (() -> Void)?

    /// NSApp.isActive; tests replace it.
    @ObservationIgnored var isActive: () -> Bool = { NSApp.isActive }
    /// M7h: MMTVL's window shows but it isn't active, and it is being brought forward (M7c L3, `repairForeground`).
    @ObservationIgnored private(set) var isRepairingForeground = false
    /// The latest remote command that arrived during the repair; delivered once MMTVL is in front.
    @ObservationIgnored private var commandAfterRepair: RemoteCommand?

    @ObservationIgnored private var monitor: Any?
    /// M7c step 15: key-ups that belong to consumed key-downs.
    @ObservationIgnored private var consumedKeys = ConsumedKeys()

    init(bindings: KeyBindings) {
        self.bindings = bindings
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .systemDefined, .scrollWheel]) { [weak self] event in
            // L6: our own synthetic events (phone text, keys for other apps) pass through untouched.
            if let cg = event.cgEvent, SyntheticInput.isOwn(cg) { return event }
            guard let self else { return event }
            switch event.type {
            case .keyDown:
                let consumed = self.handleKeyDown(event)
                self.consumedKeys.keyDown(event.keyCode, consumed: consumed)
                return consumed ? nil : event
            case .keyUp:
                // M7c step 15: a consumed key's key-up is consumed too. YouTube's page got Return's key-up after
                // MMTVL's own Enter, and its on-screen keyboard typed the letter twice.
                return self.consumedKeys.keyUp(event.keyCode) ? nil : event
            case .systemDefined: return self.handleSystemDefined(event) ? nil : event
            case .scrollWheel:
                self.onScrollWheel?(event.scrollingDeltaY, event.hasPreciseScrollingDeltas)
                return event
            default: return event
            }
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    /// L8: with a handler and MMTVL active, hands the trigger to the handler and returns true (consume);
    /// otherwise false. Clears nothing: Settings stops learning by setting the handler to nil.
    @discardableResult
    func capture(_ trigger: InputBinding.Trigger) -> Bool {
        guard let captureHandler, NSApp.isActive else { return false }
        captureHandler(trigger)
        onTriggerCaptured?()
        return true
    }

    /// The single entry point for every input source. Returns true if consumed. `isRepeat`: a held key's or
    /// controller button's auto-repeat (sources without repeats, like the phone, leave it false).
    @discardableResult
    func dispatch(_ command: RemoteCommand, isGlobal: Bool, isRepeat: Bool = false) -> Bool {
        if isActive() {
            onCommandDispatched?()
            return handler?(command, isRepeat) ?? false
        }
        if isGlobal {
            onGlobalCommand?(command)
            return true
        }
        return false
    }

    /// M7h: the phone's and the Siri Remote's way in (`ExternalRouter`). Like `dispatch`, except that while MMTVL is
    /// being brought forward a non-global command is kept (the latest press; repeats are dropped) and delivered once
    /// MMTVL is in front, instead of being lost. Keys from the event tap and the local monitor keep using `dispatch`.
    @discardableResult
    func dispatchFromRemote(_ command: RemoteCommand, isGlobal: Bool, isRepeat: Bool = false) -> Bool {
        if isRepairingForeground {
            if isActive() {
                // MMTVL came forward before the repair's check finished: the kept press goes first, in order.
                deliverCommandAfterRepair()
            } else if !isGlobal {
                if !isRepeat { commandAfterRepair = command }
                return true
            }
        }
        return dispatch(command, isGlobal: isGlobal, isRepeat: isRepeat)
    }

    /// M7h: `repairForeground` started bringing MMTVL forward.
    func foregroundRepairStarted() {
        isRepairingForeground = true
        commandAfterRepair = nil
    }

    /// M7h: the repair ended. When MMTVL came forward, the kept command goes to the active screen (once);
    /// otherwise it is dropped.
    func foregroundRepairFinished(succeeded: Bool) {
        isRepairingForeground = false
        if succeeded {
            deliverCommandAfterRepair()
        } else {
            commandAfterRepair = nil
        }
    }

    /// The kept command to the active screen, at most once.
    private func deliverCommandAfterRepair() {
        guard let command = commandAfterRepair else { return }
        commandAfterRepair = nil
        onCommandDispatched?()
        _ = handler?(command, false)
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = KeyModifier.set(from: event.modifierFlags)
        if captureHandler != nil && NSApp.isActive {
            // L8: ⌘-combos pass through (⌘Q still quits); repeats are swallowed; the first press is captured.
            if modifiers.contains(.command) { return false }
            if !event.isARepeat {
                capture(InputBinding.Trigger.key(keyCode: event.keyCode, modifiers: Array(modifiers)).normalized)
            }
            return true
        }
        guard let binding = bindings.binding(keyCode: event.keyCode, modifiers: modifiers) else {
            // L6: only the local monitor logs keys, i.e. only while MMTVL is frontmost.
            let names = modifiers.map(\.rawValue).sorted()
            Self.logger.info("Unbound key \(event.keyCode) modifiers \(names, privacy: .public)")
            return false
        }
        Self.logger.debug("Key \(event.keyCode) → \(binding.command.rawValue, privacy: .public)")
        return dispatch(binding.command, isGlobal: binding.isGlobal, isRepeat: event.isARepeat)
    }

    /// Bound media keys are always swallowed while MMTVL is frontmost (L5), so they don't start Music.
    private func handleSystemDefined(_ event: NSEvent) -> Bool {
        guard let parsed = MediaKeyEvent.parse(subtype: event.subtype.rawValue, data1: event.data1) else { return false }
        if captureHandler != nil && NSApp.isActive {
            // L8: down and up are both swallowed; only a fresh key down is captured.
            if parsed.isKeyDown && !parsed.isRepeat { capture(.media(key: parsed.key)) }
            return true
        }
        guard let binding = bindings.binding(media: parsed.key) else { return false }
        if parsed.isKeyDown && !parsed.isRepeat {
            dispatch(binding.command, isGlobal: binding.isGlobal)
        }
        return true
    }
}

/// M7c step 15: which keys' key-downs the router consumed, so their key-ups are consumed as well
/// (a view, e.g. YouTube's web page, would otherwise see a lone key-up).
nonisolated struct ConsumedKeys {
    private var codes: Set<UInt16> = []

    mutating func keyDown(_ code: UInt16, consumed: Bool) {
        if consumed { codes.insert(code) } else { codes.remove(code) }
    }

    /// True when the key-up should be consumed.
    mutating func keyUp(_ code: UInt16) -> Bool {
        codes.remove(code) != nil
    }
}
