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

    @ObservationIgnored private var monitor: Any?

    init(bindings: KeyBindings) {
        self.bindings = bindings
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .systemDefined]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .keyDown: return self.handleKeyDown(event) ? nil : event
            case .systemDefined: return self.handleSystemDefined(event) ? nil : event
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
        guard let parsed = MediaKeyEvent.parse(subtype: event.subtype.rawValue, data1: event.data1),
              let binding = bindings.binding(media: parsed.key)
        else { return false }
        if parsed.isKeyDown && !parsed.isRepeat {
            dispatch(binding.command, isGlobal: binding.isGlobal)
        }
        return true
    }
}
