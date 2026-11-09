import CoreGraphics
import Foundation
import Testing
@testable import MMTVL

struct PointerMathTests {
    @Test func accelerationKeepsZeroAndDirection() {
        #expect(PointerMath.accelerated(dx: 0, dy: 0) == CGVector(dx: 0, dy: 0))
        // Slow: barely above ×1.5.
        let slow = PointerMath.accelerated(dx: 0.1, dy: 0)
        #expect(abs(slow.dx - 0.1 * 1.50375) < 1e-9)
        // Fast: ×3 from 40 points per message on.
        #expect(PointerMath.accelerated(dx: 30, dy: 40) == CGVector(dx: 90, dy: 120))
        #expect(PointerMath.accelerated(dx: -300, dy: 400) == CGVector(dx: -900, dy: 1200))
        // Halfway: ×2.25.
        #expect(PointerMath.accelerated(dx: 0, dy: -20) == CGVector(dx: 0, dy: -45))
    }

    @Test func clampInsideAndOutside() {
        let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        #expect(PointerMath.clamp(CGPoint(x: 100, y: 100), displays: [main], previous: .zero) == CGPoint(x: 100, y: 100))
        #expect(PointerMath.clamp(CGPoint(x: 2500, y: 500), displays: [main], previous: CGPoint(x: 1900, y: 500))
                == CGPoint(x: 1919, y: 500))
        #expect(PointerMath.clamp(CGPoint(x: -20, y: -5), displays: [main], previous: CGPoint(x: 3, y: 3))
                == CGPoint(x: 0, y: 0))
    }

    @Test func clampAcrossAGapBetweenDisplays() {
        let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let side = CGRect(x: 1920, y: 0, width: 1280, height: 720)
        // Moving into the side display is fine.
        #expect(PointerMath.clamp(CGPoint(x: 2000, y: 500), displays: [main, side], previous: CGPoint(x: 1900, y: 500))
                == CGPoint(x: 2000, y: 500))
        // Below the shorter side display is in no display: clamp into the one we came from.
        #expect(PointerMath.clamp(CGPoint(x: 2000, y: 900), displays: [main, side], previous: CGPoint(x: 1900, y: 900))
                == CGPoint(x: 1919, y: 900))
        #expect(PointerMath.clamp(CGPoint(x: 2000, y: 900), displays: [main, side], previous: CGPoint(x: 2000, y: 700))
                == CGPoint(x: 2000, y: 719))
    }

    @Test func clampWithoutDisplays() {
        #expect(PointerMath.clamp(CGPoint(x: 5, y: 5), displays: [], previous: .zero) == CGPoint(x: 5, y: 5))
    }

    @Test func scrollWheelSigns() {
        let (down1, down2) = PointerMath.scrollWheels(dx: 0, dy: 10)
        #expect(down1 == 20 && down2 == 0)
        let (up1, side2) = PointerMath.scrollWheels(dx: -3.3, dy: -10.2)
        #expect(up1 == -20 && side2 == -7)
    }

    @Test func clickCounter() {
        var counter = ClickCounter()
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let point = CGPoint(x: 10, y: 10)
        do { let count = counter.register(.left, at: point, time: start); #expect(count == 1) }
        do { let count = counter.register(.left, at: CGPoint(x: 14, y: 14), time: start + 0.3); #expect(count == 2) }
        do { let count = counter.register(.left, at: point, time: start + 0.6); #expect(count == 3) }
        do { let count = counter.register(.left, at: point, time: start + 0.9); #expect(count == 3) }
        // Too late.
        do { let count = counter.register(.left, at: point, time: start + 1.5); #expect(count == 1) }
        // Too far.
        do { let count = counter.register(.left, at: CGPoint(x: 30, y: 10), time: start + 1.6); #expect(count == 1) }
        // Other button.
        do { let count = counter.register(.right, at: CGPoint(x: 30, y: 10), time: start + 1.7); #expect(count == 1) }
        do { let count = counter.register(.right, at: CGPoint(x: 30, y: 10), time: start + 1.8); #expect(count == 2) }
    }

    /// M7h security finding 4: the Siri Remote's pointer stays off the screen edges whenever the kiosk lock is in
    /// force, MMTVL in front included (its presentation options return 1 s after it becomes active).
    @Test func remoteEdgeInsetCondition() {
        #expect(PointerMath.remoteEdgeInset(isLockEffective: true) == PointerMath.kioskEdgeInset)
        #expect(PointerMath.remoteEdgeInset(isLockEffective: false) == 0)
        #expect(PointerMath.kioskEdgeInset > 0)
    }

    /// Finding 4: with the inset, no move (a fling toward any corner or edge, from anywhere, the edge included)
    /// ends within the inset of an edge; without it, the full bounds as before.
    @Test func kioskInsetKeepsThePointerOffEveryEdge() {
        let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let side = CGRect(x: 1920, y: -200, width: 1280, height: 720)
        let inset = PointerMath.kioskEdgeInset
        func offEdges(_ point: CGPoint, _ display: CGRect) -> Bool {
            point.x - display.minX >= inset && (display.maxX - 1) - point.x >= inset
                && point.y - display.minY >= inset && (display.maxY - 1) - point.y >= inset
        }
        let flings: [(Double, Double)] = [(-1e9, -1e9), (1e9, -1e9), (-1e9, 1e9), (1e9, 1e9), (0, -5000), (0, 5000),
                                          (-5000, 0), (5000, 0), (-3, -3), (2, 0), (0, 1)]
        let starts = [CGPoint(x: 960, y: 540), CGPoint(x: 0, y: 0), CGPoint(x: 1919, y: 1079), CGPoint(x: 3, y: 700),
                      CGPoint(x: 1000, y: 2), CGPoint(x: 1917, y: 500)]
        for start in starts {
            for (dx, dy) in flings {
                guard let move = PhonePointer.moveTarget(dx: dx, dy: dy, current: start, displays: [main],
                                                         edgeInset: inset) else {
                    Issue.record("no move")
                    continue
                }
                #expect(offEdges(move.point, main), "\(start) + (\(dx), \(dy)) → \(move.point)")
            }
            #expect(offEdges(PhonePointer.clickLocation(current: start, displays: [main], edgeInset: inset), main))
        }
        // Two displays: each one's edges are kept, and a point inside a display's inset area is left alone.
        for (dx, dy) in flings {
            let move = PhonePointer.moveTarget(dx: dx, dy: dy, current: CGPoint(x: 2500, y: 100), displays: [main, side],
                                               edgeInset: inset)
            #expect(move.map { offEdges($0.point, side) || offEdges($0.point, main) } == true)
        }
        #expect(PhonePointer.clickLocation(current: CGPoint(x: 0, y: 0), displays: [main], edgeInset: inset)
                == CGPoint(x: inset, y: inset))
        #expect(PhonePointer.clickLocation(current: CGPoint(x: 500, y: 500), displays: [main], edgeInset: inset)
                == CGPoint(x: 500, y: 500))

        // Off (kiosk lock off, exited to the desktop, -windowed): the full bounds, as before.
        #expect(PhonePointer.moveTarget(dx: -1e9, dy: -1e9, current: CGPoint(x: 960, y: 540), displays: [main])?.point
                == CGPoint(x: 0, y: 0))
        #expect(PhonePointer.moveTarget(dx: 1e9, dy: 1e9, current: CGPoint(x: 960, y: 540), displays: [main],
                                        edgeInset: 0)?.point == CGPoint(x: 1919, y: 1079))
        #expect(PhonePointer.clickLocation(current: .zero, displays: [main], edgeInset: 0) == .zero)
    }

    /// M7h security finding 1: the shared sinks never trap, whatever the caller passes.
    @Test func badValuesNeverTrap() {
        let (wheel1, wheel2) = PointerMath.scrollWheels(dx: .nan, dy: 1e12)
        #expect(wheel1 == Int32.max && wheel2 == 0)
        let (inf1, inf2) = PointerMath.scrollWheels(dx: -.infinity, dy: .infinity)
        #expect(inf1 == 0 && inf2 == 0)
        #expect(PointerMath.scrollWheels(dx: -1e12, dy: 0).1 == Int32.min)
        #expect(PointerMath.accelerated(dx: .nan, dy: 3) == CGVector(dx: 0, dy: 0))
        #expect(PointerMath.accelerated(dx: 1, dy: .infinity) == CGVector(dx: 0, dy: 0))
        // Each axis is capped at maxDelta before acceleration (×3 at speed).
        #expect(PointerMath.accelerated(dx: 1e9, dy: 0) == CGVector(dx: PointerMath.maxDelta * 3, dy: 0))
        let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        #expect(PointerMath.clamp(CGPoint(x: CGFloat.nan, y: 5), displays: [main], previous: CGPoint(x: 7, y: 8))
                == CGPoint(x: 7, y: 8))
        #expect(PointerMath.clamp(CGPoint(x: 1, y: CGFloat.infinity), displays: [main],
                                  previous: CGPoint(x: CGFloat.nan, y: 0)) == .zero)
        #expect(PointerMath.eventDelta(.nan) == 0)
        #expect(PointerMath.eventDelta(-.infinity) == 0)
        #expect(PointerMath.eventDelta(1e30) == Int64(Int32.max))
        #expect(PointerMath.eventDelta(12.6) == 13)
    }

    /// M7h security finding 1: a PhonePointer move with a NaN delta (or location) posts nothing.
    @Test func nonFiniteMovePostsNothing() {
        let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let here = CGPoint(x: 100, y: 100)
        #expect(PhonePointer.moveTarget(dx: .nan, dy: 1, current: here, displays: [main]) == nil)
        #expect(PhonePointer.moveTarget(dx: 1, dy: -.infinity, current: here, displays: [main]) == nil)
        #expect(PhonePointer.moveTarget(dx: 1, dy: 1, current: CGPoint(x: CGFloat.nan, y: 0), displays: [main]) == nil)
        // A normal move is unchanged: ×1.5-ish, clamped into the display.
        let move = PhonePointer.moveTarget(dx: 10, dy: 0, current: here, displays: [main])
        #expect(move?.point == CGPoint(x: 100 + 10 * 1.875, y: 100))
        #expect(move?.delta == CGVector(dx: 10 * 1.875, dy: 0))
        #expect(PhonePointer.moveTarget(dx: 1000, dy: 0, current: CGPoint(x: 1900, y: 5), displays: [main])?.point
                == CGPoint(x: 1919, y: 5))
    }
}
