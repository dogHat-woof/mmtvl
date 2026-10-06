import Testing
@testable import MMTVL

struct ThumbstickDirectionTests {
    @Test func pressRight() {
        #expect(ThumbstickDirection.resolve(x: 0.7, y: 0.1, current: nil) == .right)
    }

    @Test func hysteresisKeepsDirection() {
        #expect(ThumbstickDirection.resolve(x: 0.4, y: 0, current: .right) == .right)
    }

    @Test func releaseBelowThreshold() {
        #expect(ThumbstickDirection.resolve(x: 0.2, y: 0, current: .right) == nil)
    }

    @Test func pressDown() {
        #expect(ThumbstickDirection.resolve(x: 0.1, y: -0.8, current: nil) == .down)
    }

    @Test func belowPressThresholdIsNil() {
        #expect(ThumbstickDirection.resolve(x: 0.5, y: 0.5, current: nil) == nil)
    }

    @Test func dominantAxisWins() {
        #expect(ThumbstickDirection.resolve(x: -0.7, y: 0.65, current: nil) == .left)
    }
}
