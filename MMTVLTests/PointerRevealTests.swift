import CoreGraphics
import Foundation
import Testing
@testable import MMTVL

/// M7h step 13e (c): when trackpad mode reveals the pointer (pure).
struct PointerRevealTests {
    @Test func modeOnRevealsAtOnce() {
        var reveal = PointerReveal()
        reveal.modeChanged(isOn: true, at: 1)
        #expect(reveal.dueTime == 1)
        do { let taken = reveal.takeDue(at: 1, isAllowed: { true }); #expect(taken) }
        // Used up.
        #expect(!reveal.isPending)
        do { let taken = reveal.takeDue(at: 2, isAllowed: { true }); #expect(!taken) }
    }

    @Test func modeOnWithAFingerDownWaitsForTheLift() {
        var reveal = PointerReveal()
        reveal.touch(isTouching: true, at: 0)
        reveal.modeChanged(isOn: true, at: 1)
        #expect(!reveal.isPending)
        do { let taken = reveal.takeDue(at: 5, isAllowed: { true }); #expect(!taken) }
        reveal.touch(isTouching: false, at: 6)
        #expect(reveal.dueTime == 6 + PointerReveal.liftDelay)
        do { let taken = reveal.takeDue(at: 6, isAllowed: { true }); #expect(!taken) }
        do { let taken = reveal.takeDue(at: 6 + PointerReveal.liftDelay, isAllowed: { true }); #expect(taken) }
    }

    @Test func eachLiftRevealsOnceAfterTheDelay() {
        var reveal = PointerReveal()
        reveal.modeChanged(isOn: true, at: 0)
        _ = reveal.takeDue(at: 0, isAllowed: { true })
        for start in [1.0, 2.0, 3.0] {
            reveal.touch(isTouching: true, at: start)
            // Moves while touching aren't transitions.
            reveal.touch(isTouching: true, at: start + 0.1)
            #expect(!reveal.isPending)
            reveal.touch(isTouching: false, at: start + 0.5)
            do { let taken = reveal.takeDue(at: start + 0.5 + PointerReveal.liftDelay, isAllowed: { true }); #expect(taken) }
            do { let taken = reveal.takeDue(at: start + 0.9, isAllowed: { true }); #expect(!taken) }
        }
    }

    /// Debounced: a finger back down before the delay skips that lift's reveal; its own lift tries again.
    @Test func touchingAgainBeforeTheDelaySkipsIt() {
        var reveal = PointerReveal()
        reveal.modeChanged(isOn: true, at: 0)
        _ = reveal.takeDue(at: 0, isAllowed: { true })
        reveal.touch(isTouching: true, at: 1)
        reveal.touch(isTouching: false, at: 2)
        reveal.touch(isTouching: true, at: 2.05)
        #expect(!reveal.isPending)
        do { let taken = reveal.takeDue(at: 3, isAllowed: { true }); #expect(!taken) }
        reveal.touch(isTouching: false, at: 4)
        do { let taken = reveal.takeDue(at: 5, isAllowed: { true }); #expect(taken) }
    }

    @Test func liftsOutsideTrackpadModeDoNothing() {
        var reveal = PointerReveal()
        reveal.touch(isTouching: true, at: 0)
        reveal.touch(isTouching: false, at: 1)
        #expect(!reveal.isPending)
        do { let taken = reveal.takeDue(at: 5, isAllowed: { true }); #expect(!taken) }
    }

    @Test func modeOffCancelsAPendingReveal() {
        var reveal = PointerReveal()
        reveal.modeChanged(isOn: true, at: 0)
        reveal.modeChanged(isOn: false, at: 0.01)
        #expect(!reveal.isPending)
        do { let taken = reveal.takeDue(at: 1, isAllowed: { true }); #expect(!taken) }
        // A lift after it reveals nothing either.
        reveal.touch(isTouching: true, at: 2)
        reveal.touch(isTouching: false, at: 3)
        do { let taken = reveal.takeDue(at: 4, isAllowed: { true }); #expect(!taken) }
    }

    @Test func turningOnTwiceIsOneReveal() {
        var reveal = PointerReveal()
        reveal.modeChanged(isOn: true, at: 0)
        _ = reveal.takeDue(at: 0, isAllowed: { true })
        reveal.modeChanged(isOn: true, at: 1)
        #expect(!reveal.isPending)
    }

    /// The remote stopping or the surfaces resetting mid-touch: no lift frame comes, so it counts as one.
    @Test func aResetMidTouchCountsAsALift() {
        var reveal = PointerReveal()
        reveal.modeChanged(isOn: true, at: 0)
        _ = reveal.takeDue(at: 0, isAllowed: { true })
        reveal.touch(isTouching: true, at: 1)
        reveal.touchesReset(at: 2)
        #expect(!reveal.isTouching)
        do { let taken = reveal.takeDue(at: 2 + PointerReveal.liftDelay, isAllowed: { true }); #expect(taken) }
        // A reset with no finger down changes nothing.
        reveal.touchesReset(at: 3)
        #expect(!reveal.isPending)
    }

    /// A refused gate (or no Accessibility) drops the reveal; the next lift tries again. The gate is asked only
    /// when a reveal is due.
    @Test func aRefusedRevealIsDroppedAndTheNextLiftRetries() {
        var reveal = PointerReveal()
        var asked = 0
        reveal.modeChanged(isOn: true, at: 0)
        do { let taken = reveal.takeDue(at: -1, isAllowed: { asked += 1; return true }); #expect(!taken) }
        #expect(asked == 0)
        do { let taken = reveal.takeDue(at: 0, isAllowed: { asked += 1; return false }); #expect(!taken) }
        #expect(asked == 1)
        #expect(!reveal.isPending)
        do { let taken = reveal.takeDue(at: 1, isAllowed: { asked += 1; return true }); #expect(!taken) }
        #expect(asked == 1)
        reveal.touch(isTouching: true, at: 2)
        reveal.touch(isTouching: false, at: 3)
        do { let taken = reveal.takeDue(at: 4, isAllowed: { asked += 1; return true }); #expect(taken) }
        #expect(asked == 2)
    }
}

/// Security low 2: a pending reveal always means trackpad mode on and no finger down, whatever the sequence, so
/// `SiriRemoteInput`'s wait never finds a due reveal it can't take.
struct PointerRevealInvariantTests {
    /// SplitMix64, so each seed gives the same sequence on every run.
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    @Test(arguments: [1, 2, 3, 42, 2026] as [UInt64])
    func pendingMeansTrackpadModeAndNoFinger(seed: UInt64) {
        var generator = SeededGenerator(state: seed)
        var reveal = PointerReveal()
        var time: TimeInterval = 0
        var reveals = 0
        for _ in 0..<5000 {
            time += Double.random(in: 0...0.3, using: &generator)
            switch Int.random(in: 0..<5, using: &generator) {
            case 0: reveal.modeChanged(isOn: Bool.random(using: &generator), at: time)
            case 1: reveal.touch(isTouching: true, at: time)
            case 2: reveal.touch(isTouching: false, at: time)
            case 3: reveal.touchesReset(at: time)
            default:
                let allowed = Bool.random(using: &generator)
                if reveal.takeDue(at: time, isAllowed: { allowed }) { reveals += 1 }
            }
            if reveal.isPending {
                #expect(reveal.isTrackpadMode && !reveal.isTouching, "seed \(seed) at \(time)")
            }
            // A due reveal is always taken (what keeps the wait from looping).
            if let due = reveal.dueTime, time >= due {
                var copy = reveal
                let taken = copy.takeDue(at: time, isAllowed: { true })
                #expect(taken && !copy.isPending, "seed \(seed) at \(time)")
            }
        }
        #expect(reveals > 0)
    }
}

/// `PhonePointer.revealPath`: 1 point and back, never off the displays (step 13e (c)).
struct PointerRevealPathTests {
    static let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test func movesRightAndBack() {
        let path = PhonePointer.revealPath(current: CGPoint(x: 100, y: 200), displays: [Self.screen])
        #expect(path == [CGPoint(x: 101, y: 200), CGPoint(x: 100, y: 200)])
    }

    @Test func atTheRightEdgeMovesLeft() {
        let path = PhonePointer.revealPath(current: CGPoint(x: 1919, y: 500), displays: [Self.screen])
        #expect(path == [CGPoint(x: 1918, y: 500), CGPoint(x: 1919, y: 500)])
    }

    @Test func atTheLeftEdgeMovesRight() {
        let path = PhonePointer.revealPath(current: CGPoint(x: 0, y: 0), displays: [Self.screen])
        #expect(path == [CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)])
    }

    /// With the kiosk edge inset, a pointer at the edge moves inside first and stays there (as a click does).
    @Test func outsideTheEdgeInsetMovesInsideFirst() {
        let inset = PointerMath.kioskEdgeInset
        let path = PhonePointer.revealPath(current: CGPoint(x: 1919, y: 500), displays: [Self.screen], edgeInset: inset)
        let inside = CGPoint(x: 1920 - inset - 1, y: 500)
        #expect(path == [inside, CGPoint(x: inside.x - 1, y: 500), inside])
    }

    /// Two displays side by side: right of the first one's edge is on the second.
    @Test func crossesOntoTheNextDisplay() {
        let second = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let path = PhonePointer.revealPath(current: CGPoint(x: 1919, y: 500), displays: [Self.screen, second])
        #expect(path == [CGPoint(x: 1920, y: 500), CGPoint(x: 1919, y: 500)])
    }

    @Test func everyPointIsOnADisplay() {
        let displays = [Self.screen, CGRect(x: -1280, y: 100, width: 1280, height: 720)]
        let starts = [CGPoint(x: 1919, y: 1079), CGPoint(x: -1280, y: 100), CGPoint(x: -1, y: 819),
                      CGPoint(x: 5000, y: -300), CGPoint(x: 0.5, y: 0.5)]
        for start in starts {
            for inset in [0, PointerMath.kioskEdgeInset] {
                let path = PhonePointer.revealPath(current: start, displays: displays, edgeInset: inset)
                #expect(!path.isEmpty)
                for point in path {
                    #expect(displays.contains { $0.contains(point) }, "\(point) from \(start), inset \(inset)")
                }
            }
        }
    }

    @Test func noDisplaysOrANonFiniteLocationPostsNothing() {
        #expect(PhonePointer.revealPath(current: CGPoint(x: 10, y: 10), displays: []).isEmpty)
        #expect(PhonePointer.revealPath(current: CGPoint(x: CGFloat.nan, y: 10), displays: [Self.screen]).isEmpty)
        #expect(PhonePointer.revealPath(current: CGPoint(x: 10, y: CGFloat.infinity), displays: [Self.screen]).isEmpty)
    }
}

/// The reveal end to end through `SiriRemoteInput` (its wait task, the gate and Accessibility).
struct SiriRemotePointerRevealTests {
    typealias Harness = SiriRemoteTrackpadModeTests.Harness

    /// Waits (up to 2 s) for the input's reveal task.
    private func waitForReveals(_ harness: Harness, _ count: Int) async throws {
        for _ in 0..<100 where harness.reveals < count {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Waits (up to 2 s) until `condition` holds: the reveal task has run, even with the suite loading the main actor.
    private func wait(until condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Long enough for a reveal task that would fire to have fired.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(400))
    }

    @Test func trackpadModeOnRevealsOnce() async throws {
        let harness = Harness()
        harness.doubleSiri()
        try await waitForReveals(harness, 1)
        #expect(harness.reveals == 1)
        try await settle()
        #expect(harness.reveals == 1)
        harness.input.stop()
    }

    @Test func modeOnWithAFingerDownRevealsAfterTheLift() async throws {
        let harness = Harness()
        harness.input.touched(SwipeRecognizerTests.touching(0.5, 0.5, at: 0))
        harness.doubleSiri()
        try await settle()
        #expect(harness.reveals == 0)
        harness.time = 1
        harness.input.touched(SwipeRecognizerTests.lift(at: 1))
        harness.time = 2
        try await waitForReveals(harness, 1)
        #expect(harness.reveals == 1)
        harness.input.stop()
    }

    @Test func eachLiftRevealsAndATouchBeforeTheDelaySkipsIt() async throws {
        let harness = Harness()
        harness.doubleSiri()
        try await waitForReveals(harness, 1)
        // Lift, then down again before the delay: skipped.
        harness.time = 3
        harness.input.touched(SwipeRecognizerTests.touching(0.5, 0.5, at: 3))
        harness.input.touched(SwipeRecognizerTests.lift(at: 3.1))
        harness.input.touched(SwipeRecognizerTests.touching(0.5, 0.5, at: 3.12))
        harness.time = 10
        try await settle()
        #expect(harness.reveals == 1)
        // Its own lift reveals.
        harness.input.touched(SwipeRecognizerTests.lift(at: 10))
        harness.time = 11
        try await waitForReveals(harness, 2)
        #expect(harness.reveals == 2)
        harness.input.stop()
    }

    @Test func modeOffCancelsAPendingReveal() async throws {
        let harness = Harness()
        harness.input.touched(SwipeRecognizerTests.touching(0.5, 0.5, at: 0))
        harness.doubleSiri()
        harness.time = 1
        harness.input.touched(SwipeRecognizerTests.lift(at: 1))
        // Off before the lift's delay is over.
        harness.time = 1.01
        harness.doubleSiri()
        #expect(!harness.input.isTrackpadMode)
        harness.time = 5
        try await settle()
        #expect(harness.reveals == 0)
        harness.input.stop()
    }

    /// No lift frame comes when the surfaces reset mid-touch: it counts as one.
    @Test func surfacesResettingMidTouchCountAsALift() async throws {
        let harness = Harness()
        harness.doubleSiri()
        try await waitForReveals(harness, 1)
        harness.time = 2
        harness.input.touched(SwipeRecognizerTests.touching(0.5, 0.5, at: 2))
        harness.input.touchSurfacesReset()
        harness.time = 3
        try await waitForReveals(harness, 2)
        #expect(harness.reveals == 2)
        harness.input.stop()
    }

    /// Stopping the remote turns trackpad mode off: nothing is revealed, nothing stays pending.
    @Test func stoppingTheRemoteRevealsNothing() async throws {
        let harness = Harness()
        harness.input.touched(SwipeRecognizerTests.touching(0.5, 0.5, at: 0))
        harness.doubleSiri()
        harness.input.stop()
        harness.time = 5
        try await settle()
        #expect(harness.reveals == 0)
        #expect(!harness.input.isTrackpadMode)
    }

    /// Security M1: gated like every trackpad post; a refusal drops it and the next lift tries again.
    @Test func aBlockedAppGetsNoRevealUntilTheNextAllowedLift() async throws {
        let harness = Harness()
        harness.gate = .blocked(bundleID: "com.example.other")
        harness.doubleSiri()
        try await wait { harness.input.pointerBlockedNotices > 0 }
        #expect(harness.reveals == 0)
        #expect(harness.input.pointerBlockedNotices == 1)
        harness.gate = .allowed
        harness.time = 2
        harness.input.touched(SwipeRecognizerTests.touching(0.5, 0.5, at: 2))
        harness.input.touched(SwipeRecognizerTests.lift(at: 2.2))
        harness.time = 3
        try await waitForReveals(harness, 1)
        #expect(harness.reveals == 1)
        harness.input.stop()
    }

    @Test func withoutAccessibilityNothingIsRevealed() async throws {
        let harness = Harness()
        harness.canPost = false
        harness.doubleSiri()
        try await wait { harness.input.accessibilityNotices > 0 }
        #expect(harness.reveals == 0)
        #expect(harness.input.accessibilityNotices == 1)
        harness.input.stop()
    }

    @Test func liftsOutsideTrackpadModeRevealNothing() async throws {
        let harness = Harness()
        harness.input.touched(SwipeRecognizerTests.touching(0.5, 0.5, at: 0))
        harness.input.touched(SwipeRecognizerTests.lift(at: 0.5))
        harness.time = 5
        try await settle()
        #expect(harness.reveals == 0)
        harness.input.stop()
    }
}
