import CoreGraphics
import SwiftUI
import Testing
@testable import MMTVL

struct ParallaxTests {
    @Test func nudgeTiltsTowardWhereFocusCameFrom() {
        #expect(ParallaxMath.nudge(for: .right) == CGSize(width: -0.6, height: 0))
        #expect(ParallaxMath.nudge(for: .left) == CGSize(width: 0.6, height: 0))
        #expect(ParallaxMath.nudge(for: .down) == CGSize(width: 0, height: -0.6))
        #expect(ParallaxMath.nudge(for: .up) == CGSize(width: 0, height: 0.6))
        #expect(ParallaxMath.nudge(for: .select) == .zero)
    }

    @Test func hoverTiltIsNormalizedAndClamped() {
        let size = CGSize(width: 300, height: 180)
        #expect(ParallaxMath.tilt(hover: CGPoint(x: 150, y: 90), in: size) == .zero)
        #expect(ParallaxMath.tilt(hover: CGPoint(x: 300, y: 0), in: size) == CGSize(width: 1, height: -1))
        #expect(ParallaxMath.tilt(hover: CGPoint(x: 75, y: 135), in: size) == CGSize(width: -0.5, height: 0.5))
        #expect(ParallaxMath.tilt(hover: CGPoint(x: 400, y: -50), in: size) == CGSize(width: 1, height: -1))
        #expect(ParallaxMath.tilt(hover: CGPoint(x: 10, y: 10), in: .zero) == .zero)
    }

    @Test func specularFollowsTheTilt() {
        #expect(ParallaxMath.specularCenter(tilt: .zero) == UnitPoint(x: 0.5, y: 0.15))
        let center = ParallaxMath.specularCenter(tilt: CGSize(width: 1, height: -1))
        #expect(abs(center.x - 0.85) < 0.0001)
        #expect(abs(center.y - -0.2) < 0.0001)
    }

    /// M7h 13f: only a moving pointer tilts; a resting one (the view moved under it) never does.
    @Test func onlyAMovedPointerTilts() {
        let resting = CGPoint(x: 1690, y: 935)
        #expect(!ParallaxMath.followsPointer(at: resting, last: resting))
        #expect(ParallaxMath.followsPointer(at: CGPoint(x: 1691, y: 935), last: resting))
        #expect(ParallaxMath.followsPointer(at: CGPoint(x: 1690, y: 934.5), last: resting))
        #expect(!ParallaxMath.followsPointer(at: resting, last: nil))
    }
}
