import AppKit
import Testing
@testable import MMTVL

struct MediaKeyEventTests {
    @Test func playKeyDown() {
        let parsed = MediaKeyEvent.parse(subtype: 8, data1: (16 << 16) | (0xA << 8))
        #expect(parsed == .init(key: .playPause, isKeyDown: true, isRepeat: false))
    }

    @Test func keyUp() {
        let parsed = MediaKeyEvent.parse(subtype: 8, data1: (16 << 16) | (0xB << 8))
        #expect(parsed == .init(key: .playPause, isKeyDown: false, isRepeat: false))
    }

    @Test func repeatBit() {
        let parsed = MediaKeyEvent.parse(subtype: 8, data1: (17 << 16) | (0xA << 8) | 1)
        #expect(parsed == .init(key: .next, isKeyDown: true, isRepeat: true))
    }

    @Test func otherSubtypeIsNil() {
        #expect(MediaKeyEvent.parse(subtype: 7, data1: (16 << 16) | (0xA << 8)) == nil)
    }

    @Test func volumeUpIsNil() {
        #expect(MediaKeyEvent.parse(subtype: 8, data1: (0 << 16) | (0xA << 8)) == nil)
    }

    /// M7h L3a: volume keys parse on their own path only.
    @Test func volumeKeysParseOnTheVolumePath() {
        #expect(MediaKeyEvent.parseVolume(subtype: 8, data1: (0 << 16) | (0xA << 8))
                == .init(action: .up, isKeyDown: true, isRepeat: false))
        #expect(MediaKeyEvent.parseVolume(subtype: 8, data1: (1 << 16) | (0xA << 8) | 1)
                == .init(action: .down, isKeyDown: true, isRepeat: true))
        #expect(MediaKeyEvent.parseVolume(subtype: 8, data1: (7 << 16) | (0xB << 8))
                == .init(action: .mute, isKeyDown: false, isRepeat: false))
        #expect(MediaKeyEvent.parseVolume(subtype: 7, data1: (0 << 16) | (0xA << 8)) == nil)
        // Other keys aren't volume (brightness 2/3, play 16), and `parse` is unchanged for all of them.
        for code in [2, 3, 16, 17] {
            #expect(MediaKeyEvent.parseVolume(subtype: 8, data1: (code << 16) | (0xA << 8)) == nil)
        }
        for code in [0, 1, 7] {
            #expect(MediaKeyEvent.parse(subtype: 8, data1: (code << 16) | (0xA << 8)) == nil)
        }
        #expect(MediaKeyEvent.parse(subtype: 8, data1: (16 << 16) | (0xA << 8))?.key == .playPause)
    }
}

/// M7h L3a: the event tap's volume path.
struct GlobalEventTapVolumeTests {
    final class Harness {
        var ready = true
        var actions: [VolumeAction] = []
        let tap: GlobalEventTap

        let inputRouter: InputRouter
        var isActive = false

        init(isWindowed: Bool = false) {
            let inputRouter = InputRouter(bindings: .defaults)
            self.inputRouter = inputRouter
            tap = GlobalEventTap(inputRouter: inputRouter, isWindowed: isWindowed)
            weak var harness: Harness?
            tap.volumeKeysConsumed = { harness?.ready ?? false }
            tap.onVolume = { harness?.actions.append($0) }
            tap.schedule = { $0() }
            harness = self
            inputRouter.isActive = { harness?.isActive ?? false }
        }

        func key(_ code: Int, down: Bool = true, isRepeat: Bool = false) -> Bool {
            tap.decide(.media(subtype: 8, data1: (code << 16) | ((down ? 0xA : 0xB) << 8) | (isRepeat ? 1 : 0)))
        }
    }

    @Test func readyConsumesAndPerforms() {
        let harness = Harness()
        #expect(harness.key(0))
        #expect(harness.key(0, isRepeat: true))
        #expect(harness.key(0, down: false))
        #expect(harness.key(1))
        #expect(harness.key(7))
        #expect(harness.key(7, isRepeat: true))   // a held Mute: taken, not repeated
        #expect(harness.key(7, down: false))
        #expect(harness.actions == [.up, .up, .down, .mute])
    }

    /// Security low (pre-build 2): while Settings learns a button (MMTVL in front), a volume key never goes to the
    /// receiver, even when it's ready; it passes on (volume keys aren't a trigger that can be learned). After learning,
    /// the receiver gets them again.
    @Test func learningComesBeforeTheReceiver() {
        let harness = Harness()
        harness.isActive = true
        harness.inputRouter.captureHandler = { _ in }
        for code in [0, 1, 7] {
            #expect(!harness.key(code))
            #expect(!harness.key(code, down: false))
        }
        #expect(harness.actions.isEmpty)
        // A key held from before learning finishes the way it started.
        harness.inputRouter.captureHandler = nil
        #expect(harness.key(0))
        harness.inputRouter.captureHandler = { _ in }
        #expect(harness.key(0, isRepeat: true))   // taken, dropped
        #expect(harness.key(0, down: false))
        #expect(harness.actions == [.up])
        // Learning only counts with MMTVL in front.
        harness.isActive = false
        #expect(harness.key(1))
        #expect(harness.actions == [.up, .down])
    }

    @Test func notReadyPassesThrough() {
        let harness = Harness()
        harness.ready = false
        for code in [0, 1, 7] {
            #expect(!harness.key(code))
            #expect(!harness.key(code, down: false))
        }
        #expect(harness.actions.isEmpty)
    }

    @Test func windowedPassesThrough() {
        let harness = Harness(isWindowed: true)
        #expect(!harness.key(0))
        #expect(!harness.key(7))
        #expect(harness.actions.isEmpty)
    }

    /// QA minor 4: a held key's repeats and key-up go the way its key-down went.
    @Test func aHeldKeyFollowsItsKeyDown() {
        let harness = Harness()
        #expect(harness.key(0))
        harness.ready = false   // the receiver stopped answering while held
        #expect(harness.key(0, isRepeat: true))   // QA minor 3: taken, but dropped
        #expect(harness.key(0, down: false))
        #expect(harness.actions == [.up])

        #expect(!harness.key(1))   // not ready: macOS gets it
        harness.ready = true
        #expect(!harness.key(1, isRepeat: true))
        #expect(!harness.key(1, down: false))
        // A key-up whose key-down the tap never saw passes through.
        #expect(!harness.key(7, down: false))
        #expect(harness.actions == [.up])
    }

    /// QA minor 3: once the receiver isn't ready during a taken hold, its repeats are dropped (no fallback route and
    /// toast per repeat) until the key-up, even if it's ready again; the next key-down decides again.
    @Test func repeatsAreDroppedOnceTheReceiverIsntReady() {
        let harness = Harness()
        #expect(harness.key(1))
        #expect(harness.key(1, isRepeat: true))
        harness.ready = false
        #expect(harness.key(1, isRepeat: true))
        harness.ready = true
        #expect(harness.key(1, isRepeat: true))
        #expect(harness.key(1, down: false))
        #expect(harness.actions == [.down, .down])
        #expect(harness.key(1))
        #expect(harness.key(1, isRepeat: true))
        #expect(harness.actions == [.down, .down, .down, .down])
    }

    @Test func trackerAsksReadinessForKeyDownsAndRepeatsOnly() {
        var tracker = VolumeKeyTracker()
        var asked = 0
        let ready = { () -> Bool in asked += 1; return true }
        let down = MediaKeyEvent.Volume(action: .down, isKeyDown: true, isRepeat: false)
        #expect(tracker.decide(down, routeReady: ready, isWindowed: false) == .consume(perform: .down))
        let held = MediaKeyEvent.Volume(action: .down, isKeyDown: true, isRepeat: true)
        #expect(tracker.decide(held, routeReady: ready, isWindowed: false) == .consume(perform: .down))
        let up = MediaKeyEvent.Volume(action: .down, isKeyDown: false, isRepeat: false)
        #expect(tracker.decide(up, routeReady: ready, isWindowed: false) == .consume(perform: nil))
        #expect(tracker.taken.isEmpty)
        #expect(asked == 2)
    }

    @Test func decisionTable() {
        let up = MediaKeyEvent.Volume(action: .up, isKeyDown: true, isRepeat: true)
        #expect(VolumeKeyDecision.decide(up, routeReady: true, isWindowed: false) == .consume(perform: .up))
        #expect(VolumeKeyDecision.decide(up, routeReady: false, isWindowed: false) == .passThrough)
        #expect(VolumeKeyDecision.decide(up, routeReady: true, isWindowed: true) == .passThrough)
        let muteUp = MediaKeyEvent.Volume(action: .mute, isKeyDown: false, isRepeat: false)
        #expect(VolumeKeyDecision.decide(muteUp, routeReady: true, isWindowed: false) == .consume(perform: nil))
    }

    /// L6: MMTVL's own posted volume keys (the `keys` route to SoundSource) are never taken again.
    @Test func ownSyntheticEventsPassThrough() throws {
        let systemDefined = try #require(CGEventType(rawValue: 14))
        func volumeUpEvent() throws -> CGEvent {
            try #require(NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA00),
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: (0 << 16) | (0xA << 8), data2: -1
            )?.cgEvent)
        }
        let own = try volumeUpEvent()
        own.setIntegerValueField(.eventSourceUserData, value: SyntheticInput.marker)
        #expect(TapEvent(type: systemDefined, event: own) == .own)

        // The same key from another process (the remote, the keyboard) is a media event.
        let other = try volumeUpEvent()
        other.setIntegerValueField(.eventSourceUnixProcessID, value: 1)
        #expect(TapEvent(type: systemDefined, event: other) == .media(subtype: 8, data1: (0 << 16) | (0xA << 8)))

        let harness = Harness()
        #expect(!harness.tap.decide(.own))
        #expect(harness.actions.isEmpty)
    }
}
