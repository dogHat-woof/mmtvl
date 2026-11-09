import Foundation
import Testing
@testable import MMTVL

/// M7h L6: swipes on the Siri Remote's touch surface.
struct SwipeRecognizerTests {
    /// 60 frames a second.
    static let frameInterval = 1.0 / 60

    static func touching(_ x: Double, _ y: Double, at time: TimeInterval) -> TouchFrame {
        TouchFrame(count: 1, state: TouchFrame.touchingState, x: x, y: y, timestamp: time)
    }

    static func lift(at time: TimeInterval) -> TouchFrame {
        TouchFrame(count: 0, state: 0, x: 0, y: 0, timestamp: time)
    }

    /// Touching frames from one point to another, evenly over `duration`, starting at `start`.
    static func slide(from: (Double, Double), to: (Double, Double), start: TimeInterval = 10,
                      duration: TimeInterval) -> [TouchFrame] {
        let count = max(1, Int((duration / frameInterval).rounded()))
        return (0...count).map { index in
            let t = Double(index) / Double(count)
            return touching(from.0 + (to.0 - from.0) * t, from.1 + (to.1 - from.1) * t, at: start + duration * t)
        }
    }

    private func feed(_ recognizer: inout SwipeRecognizer, _ frames: [TouchFrame]) -> [RemoteCommand] {
        frames.flatMap { recognizer.feed($0) }
    }

    /// A slide, then the lift one frame later.
    private func swipe(_ recognizer: inout SwipeRecognizer, from: (Double, Double), to: (Double, Double),
                       start: TimeInterval = 10, duration: TimeInterval) -> [RemoteCommand] {
        let frames = Self.slide(from: from, to: to, start: start, duration: duration)
        return feed(&recognizer, frames + [Self.lift(at: start + duration + Self.frameInterval)])
    }

    @Test func slideRightStepsTwice() {
        var recognizer = SwipeRecognizer()
        // 0.5 over a second: two steps of 0.22, too slow to flick.
        #expect(swipe(&recognizer, from: (0.2, 0.5), to: (0.7, 0.5), duration: 1) == [.right, .right])
    }

    @Test func slideLeftStepsTwice() {
        var recognizer = SwipeRecognizer()
        #expect(swipe(&recognizer, from: (0.75, 0.5), to: (0.25, 0.5), duration: 1) == [.left, .left])
    }

    @Test func stepsComeWhileTheFingerMoves() {
        var recognizer = SwipeRecognizer()
        let frames = Self.slide(from: (0.2, 0.5), to: (0.7, 0.5), duration: 1)
        let firstStep = frames.firstIndex { !recognizer.feed($0).isEmpty }
        // The first step comes once the finger has moved 0.22, before the lift.
        #expect(firstStep.map { frames[$0].x - 0.2 >= SwipeRecognizer.stepDistance - 0.000_1 } == true)
        #expect(firstStep.map { frames[$0].x - 0.2 < SwipeRecognizer.stepDistance + 0.01 } == true)
    }

    @Test func slowShortSlideDoesNothing() {
        var recognizer = SwipeRecognizer()
        #expect(swipe(&recognizer, from: (0.3, 0.5), to: (0.5, 0.5), duration: 1).isEmpty)
    }

    @Test func fastFlickAddsStepsCappedAtTwo() {
        var recognizer = SwipeRecognizer()
        // 0.3 in 50 ms (6 units/s): one step from the distance, then the flick adds two (capped; 6 / 2 = 3).
        #expect(swipe(&recognizer, from: (0.3, 0.5), to: (0.6, 0.5), duration: 0.05) == [.right, .right, .right])
        // 0.5 in 50 ms (10 units/s): two steps, the flick still adds only two.
        var faster = SwipeRecognizer()
        #expect(swipe(&faster, from: (0.2, 0.5), to: (0.7, 0.5), duration: 0.05) == [.right, .right, .right, .right])
    }

    @Test func moderateFlickAddsOneStep() {
        var recognizer = SwipeRecognizer()
        // 0.15 in 50 ms (3 units/s): no step from the distance, one from the flick.
        #expect(swipe(&recognizer, from: (0.4, 0.5), to: (0.55, 0.5), duration: 0.05) == [.right])
    }

    @Test func tapDoesNothing() {
        var recognizer = SwipeRecognizer()
        // A tap's wobble can be quick, but it doesn't travel.
        #expect(swipe(&recognizer, from: (0.5, 0.5), to: (0.53, 0.5), duration: 0.01).isEmpty)
        #expect(feed(&recognizer, [Self.touching(0.5, 0.5, at: 20), Self.lift(at: 20.1)]).isEmpty)
    }

    @Test func slideDuringClickDoesNothing() {
        var recognizer = SwipeRecognizer()
        recognizer.clickpadPressed(at: 9.9)
        let frames = Self.slide(from: (0.2, 0.5), to: (0.7, 0.5), duration: 0.3)
        #expect(feed(&recognizer, frames).isEmpty)
        recognizer.clickpadReleased(at: 10.3)
        // Fast enough to flick, but the touch had a click.
        #expect(recognizer.feed(Self.lift(at: 10.32)).isEmpty)
    }

    @Test func noStepsJustAfterAClick() {
        var recognizer = SwipeRecognizer()
        recognizer.clickpadPressed(at: 9.8)
        recognizer.clickpadReleased(at: 9.9)
        // Within 150 ms of the release: movement doesn't count.
        let quiet = Self.slide(from: (0.2, 0.5), to: (0.45, 0.5), start: 9.92, duration: 0.1)
        #expect(feed(&recognizer, quiet).isEmpty)
        // After it, travel counts from where the finger was: 0.45 → 0.6 is less than a step.
        let after = Self.slide(from: (0.45, 0.5), to: (0.6, 0.5), start: 10.1, duration: 0.5)
        #expect(feed(&recognizer, after).isEmpty)
        // And a full step more does step.
        let more = Self.slide(from: (0.6, 0.5), to: (0.75, 0.5), start: 10.6, duration: 0.5)
        #expect(feed(&recognizer, more) == [.right])
    }

    @Test func clickWhileTouchingStopsTheFlick() {
        var recognizer = SwipeRecognizer()
        _ = recognizer.feed(Self.touching(0.3, 0.5, at: 10))
        recognizer.clickpadPressed(at: 10.01)
        recognizer.clickpadReleased(at: 10.05)
        // Long after the quiet time, a fast slide still steps, but doesn't flick on lift.
        let frames = Self.slide(from: (0.3, 0.5), to: (0.6, 0.5), start: 11, duration: 0.05)
        #expect(feed(&recognizer, frames) == [.right])
        #expect(recognizer.feed(Self.lift(at: 11.07)).isEmpty)
    }

    @Test func verticalDominantAxis() {
        var recognizer = SwipeRecognizer()
        // y grows upward: 0.74 → 0.29 is down, with some sideways drift.
        #expect(swipe(&recognizer, from: (0.5, 0.74), to: (0.6, 0.29), duration: 1) == [.down, .down])
        var up = SwipeRecognizer()
        #expect(swipe(&up, from: (0.45, 0.25), to: (0.4, 0.75), duration: 1) == [.up, .up])
    }

    @Test func sidewaysDriftDoesNotBuildUp() {
        var recognizer = SwipeRecognizer()
        // Mostly right with a little up: rights only.
        #expect(swipe(&recognizer, from: (0.1, 0.4), to: (0.8, 0.55), duration: 1.5) == [.right, .right, .right])
    }

    @Test func eachTouchStartsOver() {
        var recognizer = SwipeRecognizer()
        // Two slow 0.15 slides don't add up to a step.
        #expect(swipe(&recognizer, from: (0.3, 0.5), to: (0.45, 0.5), duration: 1).isEmpty)
        #expect(swipe(&recognizer, from: (0.3, 0.5), to: (0.45, 0.5), start: 12, duration: 1).isEmpty)
    }

    @Test func anotherFingerIsANewTouch() {
        var recognizer = SwipeRecognizer()
        // Finger 1 rests at 0.2; it lifts while finger 2 at 0.8 stays: no step for the jump.
        _ = recognizer.feed(Self.touching(0.2, 0.5, at: 10))
        var second = Self.touching(0.8, 0.5, at: 10.02)
        second.identifier = 2
        #expect(recognizer.feed(second).isEmpty)
        // Finger 2 then slides slowly 0.5 → two lefts from where it was, and its lift doesn't flick.
        let frames = Self.slide(from: (0.8, 0.5), to: (0.3, 0.5), start: 10.04, duration: 1).map { frame -> TouchFrame in
            var frame = frame
            frame.identifier = 2
            return frame
        }
        #expect(feed(&recognizer, frames) == [.left, .left])
        #expect(recognizer.feed(Self.lift(at: 11.1)).isEmpty)
    }

    @Test func fingerSwitchCarriesNoFlick() {
        var recognizer = SwipeRecognizer()
        // Finger 1 moves fast (no step yet), then finger 2 takes over still and lifts: no flick from finger 1.
        _ = feed(&recognizer, Self.slide(from: (0.4, 0.5), to: (0.55, 0.5), start: 10, duration: 0.05))
        var second = Self.touching(0.6, 0.5, at: 10.067)
        second.identifier = 2
        #expect(recognizer.feed(second).isEmpty)
        #expect(recognizer.feed(Self.lift(at: 10.08)).isEmpty)
    }

    @Test func liftWithoutATouchDoesNothing() {
        var recognizer = SwipeRecognizer()
        #expect(recognizer.feed(Self.lift(at: 1)).isEmpty)
    }

    /// M7h security finding 1: positions that can't be a finger count as no touch; a jump starts a new touch.
    @Test func badPositionsAndJumpsDoNothing() {
        var recognizer = SwipeRecognizer()
        for (x, y) in [(Double.nan, 0.5), (0.5, .infinity), (-.infinity, 0.5), (1e9, 0.5), (0.5, -1e9)] {
            #expect(recognizer.feed(Self.touching(0.5, 0.5, at: 1)).isEmpty)
            #expect(recognizer.feed(Self.touching(x, y, at: 1.01)).isEmpty)
            #expect(recognizer.feed(Self.lift(at: 1.02)).isEmpty)
        }
        // A jump of more than maxJump in one frame steps nothing and doesn't flick.
        #expect(recognizer.feed(Self.touching(0.1, 0.5, at: 2)).isEmpty)
        #expect(recognizer.feed(Self.touching(0.9, 0.5, at: 2.01)).isEmpty)
        #expect(recognizer.feed(Self.lift(at: 2.02)).isEmpty)
    }
}

/// M7h L6: swipes reach commands through the Siri Remote's L3 routing.
struct SiriRemoteSwipeRoutingTests {
    @Test func swipeRoutesLikeTheClickpad() {
        let fake = SiriRemoteHIDTests.FakeSystem()
        let hid = SiriRemoteHID(system: fake.system)
        let inputRouter = InputRouter(bindings: .defaults)
        var dispatched: [RemoteCommand] = []
        let external = ExternalRouter(isLauncherInFront: { true }, dispatch: { command, _, isRepeat in
            #expect(!isRepeat)
            dispatched.append(command)
        }, canPostEvents: { true }, postExternal: { _ in })
        var time: TimeInterval = 0
        let input = SiriRemoteInput(inputRouter: inputRouter, externalRouter: external, hid: hid, touch: nil, now: { time })
        input.swipesEnabled = true
        input.start()

        for frame in SwipeRecognizerTests.slide(from: (0.2, 0.5), to: (0.7, 0.5), start: 1, duration: 1) {
            input.touched(frame)
        }
        input.touched(SwipeRecognizerTests.lift(at: 2.02))
        #expect(dispatched == [.right, .right])

        // A slide while the centre is held: nothing from the touch.
        dispatched = []
        time = 3
        hid.deliver(.init(button: .select, isSiri: false, pressed: true))
        for frame in SwipeRecognizerTests.slide(from: (0.2, 0.5), to: (0.7, 0.5), start: 3, duration: 0.3) {
            input.touched(frame)
        }
        time = 3.31
        hid.deliver(.init(button: .select, isSiri: false, pressed: false))
        input.touched(SwipeRecognizerTests.lift(at: 3.32))
        #expect(dispatched == [.select])
        input.stop()
    }

    /// Step 13e: Swipes off (the default): touches outside trackpad mode do nothing; turning it off mid-touch too.
    @Test func swipesOffByDefaultDoNothing() {
        let fake = SiriRemoteHIDTests.FakeSystem()
        let hid = SiriRemoteHID(system: fake.system)
        var dispatched: [RemoteCommand] = []
        var actions: [PointerAction] = []
        let external = ExternalRouter(isLauncherInFront: { true }, dispatch: { command, _, _ in dispatched.append(command) },
                                      canPostEvents: { true }, postExternal: { _ in })
        let input = SiriRemoteInput(inputRouter: InputRouter(bindings: .defaults), externalRouter: external, hid: hid,
                                    touch: nil, pointer: { actions.append($0) }, now: { 0 })
        #expect(!input.swipesEnabled)
        input.start()
        for frame in SwipeRecognizerTests.slide(from: (0.2, 0.5), to: (0.7, 0.5), start: 1, duration: 1) {
            input.touched(frame)
        }
        input.touched(SwipeRecognizerTests.lift(at: 2.02))
        #expect(dispatched.isEmpty)
        #expect(actions.isEmpty)

        // On, then off halfway through a slide: the rest of it does nothing.
        input.swipesEnabled = true
        let frames = SwipeRecognizerTests.slide(from: (0.2, 0.5), to: (0.7, 0.5), start: 3, duration: 1)
        for frame in frames.prefix(frames.count / 2) { input.touched(frame) }
        let before = dispatched
        input.swipesEnabled = false
        for frame in frames.dropFirst(frames.count / 2) { input.touched(frame) }
        input.touched(SwipeRecognizerTests.lift(at: 4.02))
        #expect(dispatched == before)
        input.stop()
    }

    @Test func trackpadModeMovesThePointerInstead() {
        let fake = SiriRemoteHIDTests.FakeSystem()
        let hid = SiriRemoteHID(system: fake.system)
        let inputRouter = InputRouter(bindings: .defaults)
        var dispatched: [RemoteCommand] = []
        var actions: [PointerAction] = []
        let external = ExternalRouter(isLauncherInFront: { true }, dispatch: { command, _, _ in dispatched.append(command) },
                                      canPostEvents: { true }, postExternal: { _ in })
        var time: TimeInterval = 0
        let input = SiriRemoteInput(inputRouter: inputRouter, externalRouter: external, hid: hid, touch: nil,
                                    pointer: { actions.append($0) }, now: { time })
        input.start()
        // Siri twice: trackpad mode.
        hid.deliver(.init(button: nil, isSiri: true, pressed: true))
        hid.deliver(.init(button: nil, isSiri: true, pressed: false))
        time = 0.2
        hid.deliver(.init(button: nil, isSiri: true, pressed: true))
        hid.deliver(.init(button: nil, isSiri: true, pressed: false))
        #expect(input.isTrackpadMode)

        for frame in SwipeRecognizerTests.slide(from: (0.2, 0.5), to: (0.7, 0.5), start: 1, duration: 1) {
            input.touched(frame)
        }
        #expect(dispatched.isEmpty)
        #expect(!actions.isEmpty)
        #expect(actions.allSatisfy { if case .move = $0 { true } else { false } })
        input.stop()
    }
}
