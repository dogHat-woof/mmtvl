import AppKit
import Observation
import os

/// Central input funnel (D3): every source (local keys, the global event tap, game controllers)
/// turns its input into `RemoteCommand`s and calls `dispatch(_:isGlobal:)`.
@Observable
final class InputRouter {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "InputRouter")

    /// The active screen. Returns `true` if the command was handled; only then is the event swallowed.
    @ObservationIgnored var handler: ((RemoteCommand) -> Bool)?
    /// A global binding fired while another app is frontmost.
    @ObservationIgnored var onGlobalCommand: ((RemoteCommand) -> Void)?
    /// Called for every command dispatched while the launcher is active (cursor auto-hide).
    @ObservationIgnored var onCommandDispatched: (() -> Void)?
    @ObservationIgnored var bindings: KeyBindings
    /// M7 L21: mouse wheel / trackpad scrolling (`scrollingDeltaY`, `hasPreciseScrollingDeltas`). The event passes on.
    @ObservationIgnored var onScrollWheel: ((CGFloat, Bool) -> Void)?
    /// M7 L8: set while Settings learns a button; the next trigger is captured instead of dispatched.
    @ObservationIgnored var captureHandler: ((InputBinding.Trigger) -> Void)?

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
        return true
    }

    /// The single entry point for every input source. Returns true if consumed.
    @discardableResult
    func dispatch(_ command: RemoteCommand, isGlobal: Bool) -> Bool {
        if NSApp.isActive {
            onCommandDispatched?()
            return handler?(command) ?? false
        }
        if isGlobal {
            onGlobalCommand?(command)
            return true
        }
        return false
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
        return dispatch(binding.command, isGlobal: binding.isGlobal)
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
