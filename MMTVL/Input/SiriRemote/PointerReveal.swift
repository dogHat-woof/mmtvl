import Foundation

/// M7h step 13e (c): when the Siri Remote's trackpad mode shows the pointer.
///
/// A cursor obscured by `NSCursor.setHiddenUntilMouseMoves(true)` (MMTVL's cursor auto-hide on each remote press,
/// other apps' hide-while-typing, or a Mac without a pointing device) comes back on the next mouse move, but
/// WindowServer skips that reveal while a touch is active (macOS 27 SkyLight: "Skip reveal: cursor obscured for active
/// touch"; **unverified** on the MM's macOS 26.6.2). Every Siri trackpad move is made with a finger on the surface, so
/// it never shows the cursor; the phone's moves (no touch) do. So trackpad mode reveals it itself
/// (`setHiddenUntilMouseMoves(false)` and a 1-point synthetic move and back, `PhonePointer.reveal`) when it turns on
/// and after each finger lift, never while a finger is down.
///
/// Pure: mode changes and touch transitions in, `takeDue` says when to reveal. Times are on one clock (`systemUptime`).
nonisolated struct PointerReveal: Equatable {
    /// A lift's reveal waits this long: a finger put back down sooner (the next stroke, a re-placed finger) skips it,
    /// and that touch's own lift tries again.
    static let liftDelay: TimeInterval = 0.15
    /// The shortest sleep of `SiriRemoteInput`'s wait for a due reveal (security low 2: never a busy loop).
    static let minimumWait: TimeInterval = 0.001

    private(set) var isTrackpadMode = false
    /// A finger is on the touch surface (the last frame touched with a valid position).
    private(set) var isTouching = false
    /// When the next reveal is due; nil when none is pending.
    private(set) var dueTime: TimeInterval?

    var isPending: Bool { dueTime != nil }

    /// Trackpad mode turned on or off. On: a reveal is due at once, or after the lift if a finger is down (it would
    /// be skipped meanwhile). Off: nothing is pending (cursor auto-hide takes over again).
    mutating func modeChanged(isOn: Bool, at time: TimeInterval) {
        guard isOn != isTrackpadMode else { return }
        isTrackpadMode = isOn
        dueTime = isOn && !isTouching ? time : nil
    }

    /// A touch frame's state (only changes count). Down: a pending reveal waits for the lift. Up in trackpad mode:
    /// one reveal, `liftDelay` later.
    mutating func touch(isTouching touching: Bool, at time: TimeInterval) {
        guard touching != isTouching else { return }
        isTouching = touching
        if touching {
            dueTime = nil
        } else if isTrackpadMode {
            dueTime = time + Self.liftDelay
        }
    }

    /// The remote stopped or its touch surfaces were reset (sleep, wake, a reconnect): no lift frame comes for a
    /// touch in progress, so it counts as a lift.
    mutating func touchesReset(at time: TimeInterval) {
        touch(isTouching: false, at: time)
    }

    /// Whether to reveal now. A due reveal is used up either way; `isAllowed` (Accessibility and the remote pointer
    /// gate, security M1) is asked only when one is due, and false drops it (the next lift tries again).
    mutating func takeDue(at time: TimeInterval, isAllowed: () -> Bool) -> Bool {
        guard let dueTime, time >= dueTime, isTrackpadMode, !isTouching else { return false }
        self.dueTime = nil
        return isAllowed()
    }
}
