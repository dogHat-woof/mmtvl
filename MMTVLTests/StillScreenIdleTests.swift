import Foundation
import Testing
@testable import MMTVL

/// M7m L18: the idle dimmer's state machine, on a hand-advanced clock.
struct StillScreenIdleTests {
    private let start = ContinuousClock.now
    private func at(_ seconds: Int) -> ContinuousClock.Instant { start + .seconds(seconds) }

    private func makeIdle() -> StillScreenIdle {
        StillScreenIdle(dimAfter: .seconds(300), saverAfterDim: .seconds(300))
    }

    @Test func dimsFiveMinutesAfterTheLastPress() {
        var idle = makeIdle()
        var changed: Bool
        idle.stillnessChanged(true, at: at(0))
        idle.activity(at: at(100))
        changed = idle.tick(at: at(399))
        #expect(!changed)
        #expect(idle.phase == .awake)
        changed = idle.tick(at: at(400))
        #expect(changed)
        #expect(idle.phase == .dimmed)
        changed = idle.tick(at: at(401))
        #expect(!changed)
    }

    /// A long playback with presses long ago, then a pause: the five minutes start at the pause.
    @Test func dimsFiveMinutesAfterBecomingStill() {
        var idle = makeIdle()
        var changed: Bool
        idle.activity(at: at(0))
        idle.stillnessChanged(false, at: at(0))
        changed = idle.tick(at: at(3600))
        #expect(!changed)
        #expect(idle.phase == .awake)
        idle.stillnessChanged(true, at: at(3600))
        changed = idle.tick(at: at(3899))
        #expect(!changed)
        #expect(idle.phase == .awake)
        changed = idle.tick(at: at(3900))
        #expect(changed)
        #expect(idle.phase == .dimmed)
    }

    @Test func movingAgainWakes() {
        var idle = makeIdle()
        var changed: Bool
        idle.stillnessChanged(true, at: at(0))
        changed = idle.tick(at: at(300))
        #expect(changed)
        #expect(idle.phase == .dimmed)
        idle.stillnessChanged(false, at: at(310))
        #expect(idle.phase == .awake)
        changed = idle.tick(at: at(1000))
        #expect(!changed)
        // Still again: a fresh five minutes.
        idle.stillnessChanged(true, at: at(1000))
        changed = idle.tick(at: at(1299))
        #expect(!changed)
        changed = idle.tick(at: at(1300))
        #expect(changed)
        #expect(idle.phase == .dimmed)
    }

    @Test func asksForTheScreenSaverFiveMinutesAfterDimming() {
        var idle = makeIdle()
        var changed: Bool
        idle.stillnessChanged(true, at: at(0))
        changed = idle.tick(at: at(300))
        #expect(changed)
        changed = idle.tick(at: at(599))
        #expect(!changed)
        #expect(idle.phase == .dimmed)
        changed = idle.tick(at: at(600))
        #expect(changed)
        #expect(idle.phase == .screenSaver)
        changed = idle.tick(at: at(2000))
        #expect(!changed)
        #expect(idle.phase == .screenSaver)
    }

    @Test func activityWakesFromEitherPhase() {
        var idle = makeIdle()
        var changed: Bool
        idle.stillnessChanged(true, at: at(0))
        changed = idle.tick(at: at(300))
        #expect(changed)
        idle.activity(at: at(301))
        #expect(idle.phase == .awake)
        changed = idle.tick(at: at(600))
        #expect(!changed)
        changed = idle.tick(at: at(601))
        #expect(changed)
        changed = idle.tick(at: at(901))
        #expect(changed)
        #expect(idle.phase == .screenSaver)
        idle.activity(at: at(902))
        #expect(idle.phase == .awake)
        changed = idle.tick(at: at(1201))
        #expect(!changed)
        changed = idle.tick(at: at(1202))
        #expect(changed)
        #expect(idle.phase == .dimmed)
    }

    @Test func screenSaverStoppedWakes() {
        var idle = makeIdle()
        var changed: Bool
        idle.stillnessChanged(true, at: at(0))
        changed = idle.tick(at: at(300))
        #expect(changed)
        changed = idle.tick(at: at(600))
        #expect(changed)
        idle.screenSaverStopped(at: at(700))
        #expect(idle.phase == .awake)
        changed = idle.tick(at: at(999))
        #expect(!changed)
        changed = idle.tick(at: at(1000))
        #expect(changed)
        #expect(idle.phase == .dimmed)
    }
}
