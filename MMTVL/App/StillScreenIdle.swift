import Foundation

/// M7m L18 (D51, burn-in): the idle dimmer's state machine. A still screen (`AppRouter.isStillScreen`) dims
/// `dimAfter` after the later of the last command and the screen becoming still, and asks for the screen saver
/// `saverAfterDim` after dimming. A command or a screen that starts moving again wakes it. Pure; the router feeds it
/// the time.
nonisolated struct StillScreenIdle: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case awake, dimmed, screenSaver }

    var dimAfter: Duration
    var saverAfterDim: Duration
    private(set) var phase: Phase = .awake
    /// The last command; nil = none yet.
    private var lastActivity: ContinuousClock.Instant?
    /// When the screen became still; nil = it's moving (or MMTVL isn't in front).
    private var stillSince: ContinuousClock.Instant?
    /// When it dimmed.
    private var dimmedAt: ContinuousClock.Instant?

    init(dimAfter: Duration, saverAfterDim: Duration) {
        self.dimAfter = dimAfter
        self.saverAfterDim = saverAfterDim
    }

    var isStill: Bool { stillSince != nil }

    /// A command: wakes from either phase and starts the wait over.
    mutating func activity(at now: ContinuousClock.Instant) {
        lastActivity = now
        wake()
    }

    /// The screen became still, or started moving (which wakes it). Repeating the current value changes nothing.
    mutating func stillnessChanged(_ isStill: Bool, at now: ContinuousClock.Instant) {
        guard isStill != self.isStill else { return }
        if isStill {
            stillSince = now
        } else {
            stillSince = nil
            wake()
        }
    }

    /// Returns true when the phase changed.
    mutating func tick(at now: ContinuousClock.Instant) -> Bool {
        guard let stillSince else { return false }
        switch phase {
        case .awake:
            let since = max(stillSince, lastActivity ?? stillSince)
            guard now - since >= dimAfter else { return false }
            phase = .dimmed
            dimmedAt = now
            return true
        case .dimmed:
            guard let dimmedAt, now - dimmedAt >= saverAfterDim else { return false }
            phase = .screenSaver
            return true
        case .screenSaver:
            return false
        }
    }

    /// The screen saver ended (macOS's `didstop`): awake, as after a command.
    mutating func screenSaverStopped(at now: ContinuousClock.Instant) {
        activity(at: now)
    }

    private mutating func wake() {
        phase = .awake
        dimmedAt = nil
    }
}
