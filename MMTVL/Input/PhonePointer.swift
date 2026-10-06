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

    /// L12: ×1.5 when slow up to ×3 at 40 points per message.
    static func accelerated(dx: Double, dy: Double) -> CGVector {
        let speed = hypot(dx, dy)
        let factor = 1.5 + 1.5 * min(speed, fullSpeed) / fullSpeed
        return CGVector(dx: dx * factor, dy: dy * factor)
    }

    /// L12 clamp: `point` if some display contains it, else clamped into the display containing `previous`
    /// (else the first display; no displays → `point`).
    static func clamp(_ point: CGPoint, displays: [CGRect], previous: CGPoint) -> CGPoint {
        if displays.contains(where: { $0.contains(point) }) { return point }
        guard let display = displays.first(where: { $0.contains(previous) }) ?? displays.first else { return point }
        return CGPoint(x: min(max(point.x, display.minX), display.maxX - 1),
                       y: min(max(point.y, display.minY), display.maxY - 1))
    }

    /// L12: (wheel1 vertical, wheel2 horizontal), pixels.
    static func scrollWheels(dx: Double, dy: Double) -> (Int32, Int32) {
        (Int32((dy * scrollScale).rounded() * scrollSign), Int32((dx * scrollScale).rounded() * scrollSign))
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

    func perform(_ action: PointerAction) {
        switch action {
        case .move(let dx, let dy):
            let delta = PointerMath.accelerated(dx: dx, dy: dy)
            let current = SyntheticInput.pointerLocation
            let target = PointerMath.clamp(CGPoint(x: current.x + delta.dx, y: current.y + delta.dy),
                                           displays: SyntheticInput.activeDisplayBounds(), previous: current)
            SyntheticInput.movePointer(to: target, delta: CGVector(dx: target.x - current.x, dy: target.y - current.y))
        case .click(let button):
            let location = SyntheticInput.pointerLocation
            let count = clicks.register(button, at: location, time: now())
            SyntheticInput.click(button, at: location, clickCount: count)
        case .scroll(let dx, let dy):
            let (wheel1, wheel2) = PointerMath.scrollWheels(dx: dx, dy: dy)
            SyntheticInput.scroll(wheel1: wheel1, wheel2: wheel2)
        }
    }
}
