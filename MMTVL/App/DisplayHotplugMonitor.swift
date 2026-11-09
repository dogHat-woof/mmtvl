import CoreGraphics
import os

// M7h L16 (D45): HDMI hot-plugs. A TV power cycle removed and re-added the HDMI display about four times in 25 s
// (2026-11-05), and Plex HTPC showed a black screen after each (M7f §1). CoreGraphics' reconfiguration callback
// reports each display added or removed; the app marks Plex to restart on its next open (`AppLauncher`).

/// One display added or removed. Pure.
nonisolated struct HotplugEvent: Equatable, Sendable {
    enum Change: String, Equatable, Sendable { case added, removed }

    var displayID: CGDirectDisplayID
    var change: Change

    init(displayID: CGDirectDisplayID, change: Change) {
        self.displayID = displayID
        self.change = change
    }

    /// nil for the "about to reconfigure" call and for changes that neither add nor remove a display (mode,
    /// mirroring, moves).
    init?(displayID: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        if flags.contains(.beginConfigurationFlag) { return nil }
        if flags.contains(.removeFlag) {
            change = .removed
        } else if flags.contains(.addFlag) {
            change = .added
        } else {
            return nil
        }
        self.displayID = displayID
    }
}

/// Main actor. One at a time (`start` registers it with CoreGraphics; tests call `handle` directly).
final class DisplayHotplugMonitor {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Display")
    /// The registered monitor; the C callback can't capture it.
    private(set) static weak var active: DisplayHotplugMonitor?

    var onEvent: (HotplugEvent) -> Void = { _ in }
    private var isRegistered = false

    func start() {
        guard !isRegistered else { return }
        let error = CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, nil)
        guard error == .success else {
            Self.logger.error("Couldn't watch for display changes (\(error.rawValue, privacy: .public))")
            return
        }
        // The callback's events reach the main actor later, so setting it after registering misses none.
        Self.active = self
        isRegistered = true
    }

    isolated deinit {
        stop()
    }

    func stop() {
        guard isRegistered else { return }
        CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, nil)
        isRegistered = false
        if Self.active === self { Self.active = nil }
    }

    func handle(_ event: HotplugEvent) {
        Self.logger.notice("Display \(event.displayID, privacy: .public) \(event.change.rawValue, privacy: .public)")
        onEvent(event)
    }

    fileprivate static func deliver(_ event: HotplugEvent) {
        active?.handle(event)
    }
}

/// C callback: can't capture context or be actor-isolated, and may run on any thread. Reduced to a `HotplugEvent`,
/// then handled on the main actor.
nonisolated private func displayReconfigurationCallback(
    displayID: CGDirectDisplayID,
    flags: CGDisplayChangeSummaryFlags,
    userInfo: UnsafeMutableRawPointer?
) {
    guard let event = HotplugEvent(displayID: displayID, flags: flags) else { return }
    Task { @MainActor in DisplayHotplugMonitor.deliver(event) }
}
