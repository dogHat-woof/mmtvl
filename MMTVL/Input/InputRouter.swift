import AppKit
import Observation
import os

/// Central input funnel (D3): converts local key events into `RemoteCommand`s
/// and forwards them to the active screen's handler.
@Observable
final class InputRouter {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "InputRouter")

    /// Returns `true` if the command was handled; only then is the key event swallowed.
    @ObservationIgnored var handler: ((RemoteCommand) -> Bool)?

    @ObservationIgnored private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let command = KeyBindings.command(keyCode: event.keyCode, modifiers: event.modifierFlags)
            else { return event }
            Self.logger.debug("Key \(event.keyCode) → \(String(describing: command), privacy: .public)")
            return self.handler?(command) == true ? nil : event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
