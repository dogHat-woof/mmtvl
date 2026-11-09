import Foundation

/// M7h L6: swipes on the Siri Remote's touch surface, like Apple TV. One finger (the first one MultitouchSupport
/// reports), dominant axis: each `stepDistance` of travel since the last step emits one direction; on lift, a
/// flick faster than `flickSpeed` adds up to `maxFlickSteps` more. No steps while a clickpad button is down or for
/// `clickQuiet` after one is released (clicking moves the finger a little), and a touch that had a click doesn't
/// flick. Taps do nothing. Pure: frames and clicks carry their times (seconds, `systemUptime`).
nonisolated struct SwipeRecognizer {
    /// Normalized travel per step (the surface is 0…1 in both axes).
    static let stepDistance = 0.22
    /// Units per second at lift above which a flick adds steps: one step per `flickSpeed` of speed, at most
    /// `maxFlickSteps`.
    static let flickSpeed = 2.0
    static let maxFlickSteps = 2
    /// The lift's speed is measured over the touching frames in this window before the lift.
    static let flickWindow: TimeInterval = 0.05
    /// A flick needs at least this much travel along its axis since the touch began (a tap's wobble isn't one).
    static let flickMinTravel = 0.1
    /// No steps for this long after a clickpad button is released.
    static let clickQuiet: TimeInterval = 0.15

    private struct Point {
        var x: Double
        var y: Double
    }

    private var isTouching = false
    /// The followed finger's identifier: a different one is a new touch.
    private var identifier: Int32 = 0
    /// Where the touch began (for the flick's minimum travel).
    private var start = Point(x: 0, y: 0)
    /// Where travel is measured from: the touch's start, moved by each step (and to the finger after a click).
    private var anchor = Point(x: 0, y: 0)
    /// Recent touching frames for the lift's speed.
    private var samples: [(time: TimeInterval, point: Point)] = []
    /// A clickpad button went down during this touch: no flick on lift.
    private var clickedThisTouch = false
    private var buttonsDown = 0
    private var lastRelease: TimeInterval?
    /// The previous touching frame's position (for `TouchFrame.maxJump`).
    private var lastPoint = Point(x: 0, y: 0)

    /// The direction commands this frame produces (none, one, or a few for a big jump or a flick).
    mutating func feed(_ frame: TouchFrame) -> [RemoteCommand] {
        guard frame.isTouching else {
            guard isTouching else { return [] }
            defer { cancelTouch() }
            guard !clickedThisTouch, !isQuiet(at: frame.timestamp) else { return [] }
            return flickSteps()
        }
        // M7h security: a position that can't be a finger counts as no touch (no flick either).
        guard frame.hasValidPosition else {
            cancelTouch()
            return []
        }
        let point = Point(x: frame.x, y: frame.y)
        if isTouching, frame.identifier != identifier || frame.jumps(from: lastPoint.x, lastPoint.y) {
            // Another finger is first now (the first lifted), or the finger jumped further than one frame can
            // move: start over from it, no step for the jump, no flick.
            cancelTouch()
        }
        lastPoint = point
        if !isTouching {
            isTouching = true
            identifier = frame.identifier
            start = point
            anchor = point
            samples = []
            clickedThisTouch = false
        }
        if isQuiet(at: frame.timestamp) {
            // Movement during a click (and just after it) doesn't count: measure again from here.
            clickedThisTouch = true
            anchor = point
            samples = []
            return []
        }
        samples.append((frame.timestamp, point))
        samples.removeAll { frame.timestamp - $0.time > Self.flickWindow }
        return steps(to: point)
    }

    /// A clickpad button (up, down, left, right, select) went down.
    mutating func clickpadPressed(at time: TimeInterval) {
        buttonsDown += 1
        if isTouching { clickedThisTouch = true }
    }

    /// A clickpad button came up (a synthesized release too).
    mutating func clickpadReleased(at time: TimeInterval) {
        buttonsDown = max(0, buttonsDown - 1)
        lastRelease = time
    }

    /// Forgets the current touch (a mode change, or the lift itself); click state stays.
    mutating func cancelTouch() {
        isTouching = false
        samples = []
        clickedThisTouch = false
    }

    /// Forgets everything (the remote stopped).
    mutating func reset() {
        self = SwipeRecognizer()
    }

    private func isQuiet(at time: TimeInterval) -> Bool {
        if buttonsDown > 0 { return true }
        if let lastRelease, time - lastRelease < Self.clickQuiet { return true }
        return false
    }

    /// Steps for the travel since the anchor, on the dominant axis; each step moves the anchor by one step along
    /// it and lines the other axis up with the finger (sideways drift doesn't build up).
    private mutating func steps(to point: Point) -> [RemoteCommand] {
        var commands: [RemoteCommand] = []
        while true {
            let dx = point.x - anchor.x
            let dy = point.y - anchor.y
            if abs(dx) >= abs(dy) {
                guard abs(dx) >= Self.stepDistance else { break }
                commands.append(dx > 0 ? .right : .left)
                anchor.x += dx > 0 ? Self.stepDistance : -Self.stepDistance
                anchor.y = point.y
            } else {
                guard abs(dy) >= Self.stepDistance else { break }
                // y grows upward on the remote.
                commands.append(dy > 0 ? .up : .down)
                anchor.y += dy > 0 ? Self.stepDistance : -Self.stepDistance
                anchor.x = point.x
            }
        }
        return commands
    }

    /// On lift: extra steps for a fast finger, in the direction it was moving.
    private func flickSteps() -> [RemoteCommand] {
        guard let first = samples.first, let last = samples.last, last.time > first.time else { return [] }
        let duration = last.time - first.time
        let vx = (last.point.x - first.point.x) / duration
        let vy = (last.point.y - first.point.y) / duration
        let horizontal = abs(vx) >= abs(vy)
        let speed = horizontal ? abs(vx) : abs(vy)
        guard speed > Self.flickSpeed else { return [] }
        let travel = horizontal ? abs(last.point.x - start.x) : abs(last.point.y - start.y)
        guard travel >= Self.flickMinTravel else { return [] }
        let count = min(Self.maxFlickSteps, Int(speed / Self.flickSpeed))
        let command: RemoteCommand = horizontal ? (vx > 0 ? .right : .left) : (vy > 0 ? .up : .down)
        return Array(repeating: command, count: count)
    }
}
