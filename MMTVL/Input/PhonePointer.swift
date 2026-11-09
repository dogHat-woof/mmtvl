import CoreGraphics
import Foundation

/// The phone trackpad (M7b D31, L11–L13).
nonisolated enum PointerButton: String, Sendable { case left, right }

nonisolated enum PointerAction: Equatable, Sendable {
    /// CSS pixels from the phone.
    case move(dx: Double, dy: Double)
    case click(PointerButton)
    /// CSS pixels; content follows the fingers.
    case scroll(dx: Double, dy: Double)
}

/// Pure pointer math (L12).
nonisolated enum PointerMath {
    /// L11: larger deltas are ignored.
    static let maxDelta: Double = 1000
    static let scrollScale: Double = 2
    /// 1: content follows the finger (flip if natural scrolling inverts posted scrolls, step 10).
    static let scrollSign: Double = 1
    /// Speed (points per message) at which acceleration tops out.
    private static let fullSpeed: Double = 40
    /// M7h (security): points the Siri Remote's pointer keeps off every screen edge while the kiosk lock is in force,
    /// so it can't reveal the menu bar (Force Quit), the Dock or a hot corner. A TV-tuning value.
    static let kioskEdgeInset: CGFloat = 6

    /// The Siri Remote's edge inset: `kioskEdgeInset` while the lock is in force (kiosk mode, `kioskLock`, not
    /// exited to the desktop), whichever app is in front; else 0 (the full screen, as before). Also with MMTVL
    /// active: its presentation options (hidden menu bar and Dock, no Force Quit) only return 1 s after it
    /// becomes active (`KioskWindowController`), and its own UI doesn't need the outer edge.
    static func remoteEdgeInset(isLockEffective: Bool) -> CGFloat {
        isLockEffective ? kioskEdgeInset : 0
    }

    /// L12: ×1.5 when slow up to ×3 at 40 points per message. M7h security: a non-finite delta is no move, and
    /// each axis is capped at `maxDelta` (every caller's sink is safe, not only the phone's checked messages).
    static func accelerated(dx: Double, dy: Double) -> CGVector {
        guard dx.isFinite, dy.isFinite else { return CGVector(dx: 0, dy: 0) }
        let dx = min(max(dx, -maxDelta), maxDelta)
        let dy = min(max(dy, -maxDelta), maxDelta)
        let speed = hypot(dx, dy)
        let factor = 1.5 + 1.5 * min(speed, fullSpeed) / fullSpeed
        return CGVector(dx: dx * factor, dy: dy * factor)
    }

    /// L12 clamp: `point` if some display contains it, else clamped into the display containing `previous`
    /// (else the first display; no displays → `point`).
    /// M7h security: a non-finite `point` stays at `previous` (or the first display's origin). `edgeInset` keeps
    /// the point that far from every edge of each display (`kioskEdgeInset`; 0 = the full bounds).
    static func clamp(_ point: CGPoint, displays: [CGRect], previous: CGPoint, edgeInset: CGFloat = 0) -> CGPoint {
        guard point.x.isFinite, point.y.isFinite else {
            if previous.x.isFinite, previous.y.isFinite { return previous }
            return displays.first?.origin ?? .zero
        }
        let areas = displays.map { inset($0, by: edgeInset) }
        if areas.contains(where: { $0.contains(point) }) { return point }
        guard let index = displays.firstIndex(where: { $0.contains(previous) }) ?? (displays.isEmpty ? nil : 0)
        else { return point }
        let area = areas[index]
        return CGPoint(x: min(max(point.x, area.minX), area.maxX - 1),
                       y: min(max(point.y, area.minY), area.maxY - 1))
    }

    /// `display` shrunk by `amount` on every side (never below 2 × 2 points).
    private static func inset(_ display: CGRect, by amount: CGFloat) -> CGRect {
        guard amount > 0 else { return display }
        return display.insetBy(dx: min(amount, max(0, display.width / 2 - 1)),
                               dy: min(amount, max(0, display.height / 2 - 1)))
    }

    /// L12: (wheel1 vertical, wheel2 horizontal), pixels. M7h security: non-finite input is 0, and values are
    /// clamped to `Int32`'s range (never a trapping conversion).
    static func scrollWheels(dx: Double, dy: Double) -> (Int32, Int32) {
        (wheel(dy), wheel(dx))
    }

    private static func wheel(_ value: Double) -> Int32 {
        let pixels = (value * scrollScale).rounded() * scrollSign
        guard pixels.isFinite else { return 0 }
        return Int32(min(max(pixels, Double(Int32.min)), Double(Int32.max)))
    }

    /// M7h security: an event's integer delta field; non-finite is 0, clamped to `Int32`'s range.
    static func eventDelta(_ value: Double) -> Int64 {
        guard value.isFinite else { return 0 }
        return Int64(min(max(value.rounded(), Double(Int32.min)), Double(Int32.max)))
    }
}

/// Double and triple clicks (L12): within 0.5 s and 6 points of the last click of the same button.
nonisolated struct ClickCounter {
    static let interval: TimeInterval = 0.5
    static let distance: CGFloat = 6
    static let maxCount: Int64 = 3

    private var last: (button: PointerButton, point: CGPoint, time: Date, count: Int64)?

    /// 1, 2 or 3.
    mutating func register(_ button: PointerButton, at point: CGPoint, time: Date) -> Int64 {
        var count: Int64 = 1
        if let last, last.button == button,
           time.timeIntervalSince(last.time) <= Self.interval,
           hypot(point.x - last.point.x, point.y - last.point.y) <= Self.distance {
            count = min(last.count + 1, Self.maxCount)
        }
        last = (button, point, time, count)
        return count
    }
}

/// Posts pointer actions with `SyntheticInput` (tagged, L13).
final class PhonePointer {
    var now: () -> Date = Date.init
    private var clicks = ClickCounter()

    /// `edgeInset`: the Siri Remote's kiosk edge inset (`PointerMath.remoteEdgeInset`); the phone passes 0.
    func perform(_ action: PointerAction, edgeInset: CGFloat = 0) {
        switch action {
        case .move(let dx, let dy):
            let current = SyntheticInput.pointerLocation
            guard let move = Self.moveTarget(dx: dx, dy: dy, current: current,
                                             displays: SyntheticInput.activeDisplayBounds(), edgeInset: edgeInset)
            else { return }
            SyntheticInput.movePointer(to: move.point, delta: move.delta)
        case .click(let button):
            var location = SyntheticInput.pointerLocation
            if edgeInset > 0 {
                // The pointer may sit at an edge (a mouse left it there): move it in first, click there.
                let inside = Self.clickLocation(current: location, displays: SyntheticInput.activeDisplayBounds(),
                                                edgeInset: edgeInset)
                if inside != location {
                    SyntheticInput.movePointer(to: inside, delta: CGVector(dx: inside.x - location.x, dy: inside.y - location.y))
                    location = inside
                }
            }
            let count = clicks.register(button, at: location, time: now())
            SyntheticInput.click(button, at: location, clickCount: count)
        case .scroll(let dx, let dy):
            let (wheel1, wheel2) = PointerMath.scrollWheels(dx: dx, dy: dy)
            SyntheticInput.scroll(wheel1: wheel1, wheel2: wheel2)
        }
    }

    /// Where a move puts the pointer, and the delta to post; nil (nothing posted) for a non-finite delta or
    /// pointer location (M7h security).
    static func moveTarget(dx: Double, dy: Double, current: CGPoint, displays: [CGRect],
                           edgeInset: CGFloat = 0) -> (point: CGPoint, delta: CGVector)? {
        guard dx.isFinite, dy.isFinite, current.x.isFinite, current.y.isFinite else { return nil }
        let delta = PointerMath.accelerated(dx: dx, dy: dy)
        let target = PointerMath.clamp(CGPoint(x: current.x + delta.dx, y: current.y + delta.dy),
                                       displays: displays, previous: current, edgeInset: edgeInset)
        return (target, CGVector(dx: target.x - current.x, dy: target.y - current.y))
    }

    /// Where a click lands: the pointer, moved inside the edge inset when it's nearer an edge.
    static func clickLocation(current: CGPoint, displays: [CGRect], edgeInset: CGFloat) -> CGPoint {
        PointerMath.clamp(current, displays: displays, previous: current, edgeInset: edgeInset)
    }

    /// M7h step 13e (c): a mouse move that shows an obscured pointer (the Siri Remote's trackpad mode,
    /// `PointerReveal`), 1 point and back, so it ends where it was. `edgeInset` as for moves: a pointer outside it is
    /// moved inside first (as a click does) and stays there.
    func reveal(edgeInset: CGFloat = 0) {
        var from = SyntheticInput.pointerLocation
        for point in Self.revealPath(current: from, displays: SyntheticInput.activeDisplayBounds(), edgeInset: edgeInset) {
            SyntheticInput.movePointer(to: point, delta: CGVector(dx: point.x - from.x, dy: point.y - from.y))
            from = point
        }
    }

    /// The reveal's moves, in order: inside the edge inset if the pointer is outside it, then 1 point right (left
    /// when right would leave the displays or the inset) and back. Every point is on a display. Empty (nothing
    /// posted) for no displays or a non-finite location.
    static func revealPath(current: CGPoint, displays: [CGRect], edgeInset: CGFloat = 0) -> [CGPoint] {
        guard current.x.isFinite, current.y.isFinite, !displays.isEmpty else { return [] }
        let base = clickLocation(current: current, displays: displays, edgeInset: edgeInset)
        let nudged = { (dx: CGFloat) in
            PointerMath.clamp(CGPoint(x: base.x + dx, y: base.y), displays: displays, previous: base, edgeInset: edgeInset)
        }
        var path = base == current ? [] : [base]
        let right = nudged(1)
        let step = right != base ? right : nudged(-1)
        if step != base { path += [step, base] }
        return path
    }
}
