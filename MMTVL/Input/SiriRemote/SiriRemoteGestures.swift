import Foundation

/// M7h L4, L5: the Siri Remote's timings, in one place for tuning on the TV.
nonisolated enum SiriRemoteTiming {
    /// A held clickpad direction repeats after this, then every `repeatInterval` (`ControllerInput`'s values).
    static let repeatDelay: TimeInterval = 0.45
    static let repeatInterval: TimeInterval = 0.12
    /// Centre held this long: `menu` (normal mode) or a right click (trackpad mode), once while held.
    static let centreLongPress: TimeInterval = 0.6
    /// Power held this long: `powerMenu`.
    static let powerLongPress: TimeInterval = 0.8
    /// Two Siri presses this close toggle trackpad mode.
    static let siriDoublePress: TimeInterval = 0.4
    /// How often `SiriRemoteInput` ticks the state machine while `needsTicks`.
    static let tickInterval: Duration = .milliseconds(30)
}

/// M7h L4, L5: turns the Siri Remote's presses and releases into commands, the trackpad toggle and clicks.
/// Pure: the caller passes the time (seconds on a monotonic clock) and calls `tick(at:)` while `needsTicks`.
/// Buttons arrive with the command their binding gives (nil = unbound); long presses belong to the physical
/// button (centre → `menu` or a right click, power → `powerMenu`) whatever it is bound to.
nonisolated struct SiriRemoteGestures {
    enum Event: Equatable {
        case command(RemoteCommand, isRepeat: Bool)
        case toggleTrackpad
        case click(PointerButton)
    }

    /// Set by the owner when the mode changes (it toggles on `.toggleTrackpad`). Changes what the centre does.
    var isTrackpadMode = false

    private static let directions: Set<RemoteCommand> = [.up, .down, .left, .right]

    private struct Held {
        let command: RemoteCommand?
        let pressedAt: TimeInterval
        /// Centre and power: when the long press fires (nil once it has fired, or for other buttons).
        var longPressAt: TimeInterval?
        /// The long press fired; the release does nothing.
        var longPressFired = false
        /// Directions: the next auto-repeat.
        var nextRepeatAt: TimeInterval?
    }

    private var held: [SiriRemoteButton: Held] = [:]
    private var lastSiriPress: TimeInterval?

    /// True while a long press or a repeat is pending: the owner should call `tick(at:)` about every 30 ms.
    var needsTicks: Bool {
        held.values.contains { $0.longPressAt != nil || $0.nextRepeatAt != nil }
    }

    mutating func press(_ button: SiriRemoteButton, command: RemoteCommand?, at now: TimeInterval) -> [Event] {
        // A second press without a release (a duplicate report) is ignored.
        guard held[button] == nil else { return [] }
        // Like ControllerInput: a new press stops any other button's repeat.
        for key in held.keys { held[key]?.nextRepeatAt = nil }
        var state = Held(command: command, pressedAt: now)
        switch button {
        case .select:
            state.longPressAt = now + SiriRemoteTiming.centreLongPress
            held[button] = state
            return []
        case .power:
            state.longPressAt = now + SiriRemoteTiming.powerLongPress
            held[button] = state
            return []
        default:
            guard let command else {
                held[button] = state
                return []
            }
            if Self.directions.contains(command) {
                state.nextRepeatAt = now + SiriRemoteTiming.repeatDelay
            }
            held[button] = state
            return [.command(command, isRepeat: false)]
        }
    }

    mutating func release(_ button: SiriRemoteButton, at now: TimeInterval) -> [Event] {
        guard let state = held.removeValue(forKey: button) else { return [] }
        guard !state.longPressFired else { return [] }
        // Released after the threshold but before the next tick: still a long press.
        if let longPressAt = state.longPressAt, now >= longPressAt, let event = longPressEvent(for: button) {
            return [event]
        }
        switch button {
        case .select:
            if isTrackpadMode { return [.click(.left)] }
            return state.command.map { [.command($0, isRepeat: false)] } ?? []
        case .power:
            return state.command.map { [.command($0, isRepeat: false)] } ?? []
        default:
            return []
        }
    }

    /// L5: two presses within `siriDoublePress` toggle trackpad mode; a single press does nothing.
    mutating func siriPressed(at now: TimeInterval) -> [Event] {
        if let last = lastSiriPress, now - last <= SiriRemoteTiming.siriDoublePress {
            lastSiriPress = nil
            return [.toggleTrackpad]
        }
        lastSiriPress = now
        return []
    }

    /// The remote went away (or reading stopped) while buttons were held: they count as released, with no
    /// event at all (no select, no long press, no more repeats), since the user may not have let go.
    mutating func cancel(_ button: SiriRemoteButton) {
        held[button] = nil
    }

    /// Centre: `menu`, or a right click in trackpad mode; power: `powerMenu` (L4, whatever the binding).
    private func longPressEvent(for button: SiriRemoteButton) -> Event? {
        switch button {
        case .select: isTrackpadMode ? .click(.right) : .command(.menu, isRepeat: false)
        case .power: .command(.powerMenu, isRepeat: false)
        default: nil
        }
    }

    mutating func cancelAll() {
        held.removeAll()
        lastSiriPress = nil
    }

    /// Long presses and repeats that are due. At most one repeat per button per tick (a stalled main thread
    /// doesn't burst).
    mutating func tick(at now: TimeInterval) -> [Event] {
        var events: [Event] = []
        for button in held.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard var state = held[button] else { continue }
            if let longPressAt = state.longPressAt, now >= longPressAt {
                state.longPressAt = nil
                state.longPressFired = true
                if let event = longPressEvent(for: button) { events.append(event) }
            }
            if let nextRepeatAt = state.nextRepeatAt, now >= nextRepeatAt, let command = state.command {
                events.append(.command(command, isRepeat: true))
                var next = nextRepeatAt + SiriRemoteTiming.repeatInterval
                if next <= now { next = now + SiriRemoteTiming.repeatInterval }
                state.nextRepeatAt = next
            }
            held[button] = state
        }
        return events
    }
}
