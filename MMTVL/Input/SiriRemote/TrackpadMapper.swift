import Foundation

/// M7h L7: trackpad mode's motion. The finger's movement becomes pointer moves (`PhonePointer` accelerates and
/// clamps them), or scrolling when the touch begins at the surface's right edge (vertical) or bottom edge
/// (horizontal); the touch keeps that role until it lifts. Pure: one frame in, actions out. Clicks are
/// `SiriRemoteGestures`' (L4). Pointer moves hold while a clickpad button is down and for `clickQuiet` after its
/// release (pressing moves the finger a little: at `pointerScale` enough to miss the target or `ClickCounter`'s
/// double-click distance); the finger is still followed, so the pointer doesn't jump when moves resume.
nonisolated struct TrackpadMapper {
    /// Points of pointer travel per unit of finger travel (the surface is 0…1).
    static let pointerScale = 1200.0
    /// Scroll units (`PointerAction.scroll`, before `PointerMath.scrollWheels`) per unit of finger travel.
    static let scrollScale = 600.0
    /// A touch that begins at x ≥ this scrolls vertically.
    static let verticalScrollEdge = 0.85
    /// A touch that begins at y ≤ this (and not at the right edge) scrolls horizontally.
    static let horizontalScrollEdge = 0.12
    /// No pointer moves for this long after a clickpad button is released (swipes' quiet time, L6).
    static let clickQuiet: TimeInterval = SwipeRecognizer.clickQuiet

    enum Role: Equatable {
        case pointer, verticalScroll, horizontalScroll
    }

    /// The current touch's role; nil while nothing touches.
    private(set) var role: Role?
    /// Where the touch began, only after the frame that began it (QA: the debug log of each touch's start).
    private(set) var touchStart: (x: Double, y: Double)?
    private var last: (x: Double, y: Double)?
    /// The followed finger's identifier: a different one is a new touch.
    private var identifier: Int32 = 0
    /// Clickpad buttons down now, and the last release (frames' clock); kept across touches and `reset()`.
    private var buttonsDown = 0
    private var lastRelease: TimeInterval?

    mutating func feed(_ frame: TouchFrame) -> [PointerAction] {
        touchStart = nil
        // M7h security: a position that can't be a finger counts as no touch.
        guard frame.isTouching, frame.hasValidPosition else {
            reset()
            return []
        }
        guard let last, let role, frame.identifier == identifier, !frame.jumps(from: last.x, last.y) else {
            // The touch begins (or another finger is first now, the first having lifted, or the finger jumped
            // further than one frame can move): its start decides its role; nothing moves yet, so the jump isn't a move.
            self.last = (frame.x, frame.y)
            self.identifier = frame.identifier
            self.role = Self.role(startingAt: frame.x, frame.y)
            self.touchStart = (frame.x, frame.y)
            return []
        }
        let dx = frame.x - last.x
        let dy = frame.y - last.y
        self.last = (frame.x, frame.y)
        // y grows upward on the remote and downward on screen: finger up moves the pointer up, and the content up
        // (scrolls follow the finger, like the phone's).
        switch role {
        case .pointer:
            guard dx != 0 || dy != 0, !isClickHeld(at: frame.timestamp) else { return [] }
            return [.move(dx: dx * Self.pointerScale, dy: -dy * Self.pointerScale)]
        case .verticalScroll:
            guard dy != 0 else { return [] }
            return [.scroll(dx: 0, dy: -dy * Self.scrollScale)]
        case .horizontalScroll:
            guard dx != 0 else { return [] }
            return [.scroll(dx: dx * Self.scrollScale, dy: 0)]
        }
    }

    /// Forgets the touch (a lift, a mode change, or the remote stopped); click state stays (the HID releases
    /// held buttons when the remote stops).
    mutating func reset() {
        role = nil
        last = nil
        touchStart = nil
    }

    /// A clickpad button (up, down, left, right, select) went down.
    mutating func clickpadPressed(at time: TimeInterval) {
        buttonsDown += 1
    }

    /// A clickpad button came up (a synthesized release too).
    mutating func clickpadReleased(at time: TimeInterval) {
        buttonsDown = max(0, buttonsDown - 1)
        lastRelease = time
    }

    private func isClickHeld(at time: TimeInterval) -> Bool {
        if buttonsDown > 0 { return true }
        if let lastRelease, time - lastRelease < Self.clickQuiet { return true }
        return false
    }

    static func role(startingAt x: Double, _ y: Double) -> Role {
        if x >= verticalScrollEdge { return .verticalScroll }
        if y <= horizontalScrollEdge { return .horizontalScroll }
        return .pointer
    }
}
