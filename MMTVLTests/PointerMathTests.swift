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
}
