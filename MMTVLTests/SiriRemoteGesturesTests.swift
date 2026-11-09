import Foundation
import Testing
@testable import MMTVL

/// M7h L4, L5: the Siri Remote's press/release state machine.
struct SiriRemoteGesturesTests {
    private typealias Event = SiriRemoteGestures.Event

    /// Ticks every 10 ms from `start` to `end`; returns each event with the tick time it came at.
    private func ticks(_ gestures: inout SiriRemoteGestures, from start: TimeInterval, to end: TimeInterval)
        -> [(time: TimeInterval, event: Event)] {
        var result: [(TimeInterval, Event)] = []
        var step = 0
        while true {
            let time = start + Double(step) * 0.01
            if time > end + 0.000_1 { break }
            result += gestures.tick(at: time).map { (time, $0) }
            step += 1
        }
        return result
    }

    @Test func shortCentreSelects() {
        var gestures = SiriRemoteGestures()
        #expect(gestures.press(.select, command: .select, at: 10).isEmpty)
        #expect(gestures.needsTicks)
        #expect(ticks(&gestures, from: 10, to: 10.3).isEmpty)
        #expect(gestures.release(.select, at: 10.3) == [.command(.select, isRepeat: false)])
        #expect(!gestures.needsTicks)
    }

    @Test func longCentreSendsMenuOnceAndNoSelect() {
        var gestures = SiriRemoteGestures()
        _ = gestures.press(.select, command: .select, at: 0)
        let fired = ticks(&gestures, from: 0, to: 2)
        #expect(fired.map(\.event) == [.command(.menu, isRepeat: false)])
        #expect(abs(fired[0].time - SiriRemoteTiming.centreLongPress) < 0.011)
        #expect(!gestures.needsTicks)
        #expect(gestures.release(.select, at: 2).isEmpty)
    }

    @Test func heldDirectionRepeats() {
        var gestures = SiriRemoteGestures()
        #expect(gestures.press(.up, command: .up, at: 0) == [.command(.up, isRepeat: false)])
        let fired = ticks(&gestures, from: 0, to: 0.82)
        #expect(fired.allSatisfy { $0.event == .command(.up, isRepeat: true) })
        let times = fired.map(\.time)
        // 0.45, then every 0.12: 0.57, 0.69, 0.81 (ticks are 10 ms apart).
        #expect(times.count == 4)
        let expected: [TimeInterval] = [0.45, 0.57, 0.69, 0.81]
        for (time, want) in zip(times, expected) {
            #expect(abs(time - want) < 0.011)
        }
        #expect(gestures.release(.up, at: 0.85).isEmpty)
        #expect(!gestures.needsTicks)
        #expect(ticks(&gestures, from: 0.85, to: 2).isEmpty)
    }

    @Test func repeatsFollowTheBinding() {
        var gestures = SiriRemoteGestures()
        // The clickpad's Up bound to Channel Up: sent on press, not repeated (only directions repeat).
        #expect(gestures.press(.up, command: .channelUp, at: 0) == [.command(.channelUp, isRepeat: false)])
        #expect(!gestures.needsTicks)
        // An unbound button does nothing.
        #expect(gestures.press(.down, command: nil, at: 1).isEmpty)
        #expect(gestures.release(.down, at: 1.1).isEmpty)
    }

    @Test func aNewPressStopsTheRepeat() {
        var gestures = SiriRemoteGestures()
        _ = gestures.press(.up, command: .up, at: 0)
        #expect(gestures.press(.back, command: .back, at: 0.2) == [.command(.back, isRepeat: false)])
        #expect(ticks(&gestures, from: 0.2, to: 1).isEmpty)
    }

    @Test func otherButtonsActOnPress() {
        var gestures = SiriRemoteGestures()
        #expect(gestures.press(.tv, command: .home, at: 0) == [.command(.home, isRepeat: false)])
        #expect(gestures.release(.tv, at: 0.1).isEmpty)
        #expect(gestures.press(.playPause, command: .playPause, at: 1) == [.command(.playPause, isRepeat: false)])
        #expect(gestures.press(.volumeUp, command: .volumeUp, at: 2) == [.command(.volumeUp, isRepeat: false)])
    }

    @Test func duplicatePressIsIgnored() {
        var gestures = SiriRemoteGestures()
        _ = gestures.press(.back, command: .back, at: 0)
        #expect(gestures.press(.back, command: .back, at: 0.01).isEmpty)
        #expect(gestures.release(.back, at: 0.1).isEmpty)
        #expect(gestures.release(.back, at: 0.2).isEmpty)
    }

    @Test func siriDoublePressTogglesTrackpad() {
        var gestures = SiriRemoteGestures()
        #expect(gestures.siriPressed(at: 0).isEmpty)
        #expect(gestures.siriPressed(at: 0.3) == [.toggleTrackpad])
        // A third press starts over.
        #expect(gestures.siriPressed(at: 0.5).isEmpty)
    }

    @Test func singleSiriDoesNothing() {
        var gestures = SiriRemoteGestures()
        #expect(gestures.siriPressed(at: 0).isEmpty)
        #expect(!gestures.needsTicks)
        #expect(ticks(&gestures, from: 0, to: 1).isEmpty)
        // Too slow for a double-press.
        #expect(gestures.siriPressed(at: 0.5).isEmpty)
        #expect(gestures.siriPressed(at: 1.5).isEmpty)
    }

    @Test func longPowerOpensThePowerMenu() {
        var gestures = SiriRemoteGestures()
        #expect(gestures.press(.power, command: .power, at: 0).isEmpty)
        let fired = ticks(&gestures, from: 0, to: 2)
        #expect(fired.map(\.event) == [.command(.powerMenu, isRepeat: false)])
        #expect(abs(fired[0].time - SiriRemoteTiming.powerLongPress) < 0.011)
        #expect(gestures.release(.power, at: 2).isEmpty)
    }

    @Test func shortPowerSendsPower() {
        var gestures = SiriRemoteGestures()
        _ = gestures.press(.power, command: .power, at: 0)
        #expect(ticks(&gestures, from: 0, to: 0.7).isEmpty)
        #expect(gestures.release(.power, at: 0.7) == [.command(.power, isRepeat: false)])
    }

    @Test func trackpadShortCentreClicksLeft() {
        var gestures = SiriRemoteGestures()
        gestures.isTrackpadMode = true
        _ = gestures.press(.select, command: .select, at: 0)
        #expect(ticks(&gestures, from: 0, to: 0.3).isEmpty)
        #expect(gestures.release(.select, at: 0.3) == [.click(.left)])
    }

    @Test func trackpadLongCentreClicksRightOnce() {
        var gestures = SiriRemoteGestures()
        gestures.isTrackpadMode = true
        _ = gestures.press(.select, command: .select, at: 0)
        #expect(ticks(&gestures, from: 0, to: 3).map(\.event) == [.click(.right)])
        #expect(gestures.release(.select, at: 3).isEmpty)
    }

    /// Long presses belong to the physical button: a rebound (or unbound) centre still clicks in trackpad mode.
    @Test func trackpadCentreClicksWhateverItsBinding() {
        for command in [RemoteCommand.playPause, nil] {
            var gestures = SiriRemoteGestures()
            gestures.isTrackpadMode = true
            _ = gestures.press(.select, command: command, at: 0)
            #expect(gestures.release(.select, at: 0.2) == [.click(.left)])
            _ = gestures.press(.select, command: command, at: 1)
            #expect(ticks(&gestures, from: 1, to: 3).map(\.event) == [.click(.right)])
            #expect(gestures.release(.select, at: 3).isEmpty)
        }
    }

    /// QA finding 2: a release after the threshold but before the next tick is still the long press.
    @Test func releaseAfterTheThresholdBeforeATickIsLong() {
        var trackpad = SiriRemoteGestures()
        trackpad.isTrackpadMode = true
        _ = trackpad.press(.select, command: .select, at: 0)
        #expect(trackpad.release(.select, at: 0.62) == [.click(.right)])

        var normal = SiriRemoteGestures()
        _ = normal.press(.select, command: .select, at: 0)
        #expect(normal.release(.select, at: 0.62) == [.command(.menu, isRepeat: false)])
        _ = normal.press(.power, command: .power, at: 1)
        #expect(normal.release(.power, at: 1.85) == [.command(.powerMenu, isRepeat: false)])
        // Just before the threshold: still short.
        _ = normal.press(.select, command: .select, at: 2)
        #expect(normal.release(.select, at: 2.59) == [.command(.select, isRepeat: false)])
    }

    @Test func trackpadKeepsOtherButtons() {
        var gestures = SiriRemoteGestures()
        gestures.isTrackpadMode = true
        #expect(gestures.press(.back, command: .back, at: 0) == [.command(.back, isRepeat: false)])
    }

    @Test func removalMidPressReleasesWithoutLongPress() {
        var gestures = SiriRemoteGestures()
        _ = gestures.press(.select, command: .select, at: 0)
        _ = ticks(&gestures, from: 0, to: 0.3)
        gestures.cancel(.select)
        #expect(!gestures.needsTicks)
        #expect(ticks(&gestures, from: 0.3, to: 2).isEmpty)
        // The real release (if it ever comes) does nothing either.
        #expect(gestures.release(.select, at: 2).isEmpty)

        _ = gestures.press(.up, command: .up, at: 3)
        gestures.cancel(.up)
        #expect(ticks(&gestures, from: 3, to: 4).isEmpty)

        _ = gestures.press(.power, command: .power, at: 5)
        gestures.cancelAll()
        #expect(ticks(&gestures, from: 5, to: 6).isEmpty)
        // The button works again after the removal.
        #expect(gestures.press(.up, command: .up, at: 7) == [.command(.up, isRepeat: false)])
    }
}

/// M7h L3: the routing shared by the phone and the Siri Remote.
struct ExternalRouterTests {
    final class Recorder {
        var inFront = false
        var canPost = true
        var dispatched: [(RemoteCommand, Bool, Bool)] = []
        var posted: [ExternalKey] = []

        var router: ExternalRouter {
            ExternalRouter(
                isLauncherInFront: { self.inFront },
                dispatch: { self.dispatched.append(($0, $1, $2)) },
                canPostEvents: { self.canPost },
                postExternal: { self.posted.append($0) }
            )
        }
    }

    @Test func launcherInFrontGetsEverything() {
        let recorder = Recorder()
        recorder.inFront = true
        #expect(recorder.router.route(.up, isRepeat: true) == .launcher)
        #expect(recorder.router.route(.home) == .launcher)
        #expect(recorder.dispatched.map(\.0) == [.up, .home])
        #expect(recorder.dispatched.map(\.1) == [false, false])
        #expect(recorder.dispatched.map(\.2) == [true, false])
        #expect(recorder.posted.isEmpty)
    }

    @Test func homeFromAnotherAppIsGlobal() {
        let recorder = Recorder()
        recorder.canPost = false
        #expect(recorder.router.route(.home) == .home)
        #expect(recorder.dispatched.map(\.0) == [.home])
        #expect(recorder.dispatched.map(\.1) == [true])
    }

    @Test func otherAppsGetKeys() {
        let recorder = Recorder()
        #expect(recorder.router.route(.select) == .posted(.key(36)))
        #expect(recorder.router.route(.menu) == .unmapped)
        #expect(recorder.posted == [.key(36)])
        #expect(recorder.dispatched.isEmpty)
    }

    @Test func volumeAndPowerPostNothing() {
        let recorder = Recorder()
        for command in [RemoteCommand.volumeUp, .volumeDown, .mute, .power, .powerMenu] {
            #expect(recorder.router.route(command) == .unmapped)
        }
        #expect(recorder.posted.isEmpty)
        #expect(recorder.dispatched.isEmpty)
    }

    @Test func withoutAccessibilityNothingIsPosted() {
        let recorder = Recorder()
        recorder.canPost = false
        #expect(recorder.router.route(.up) == .needsAccessibility)
        #expect(recorder.posted.isEmpty)
    }
}

/// M7h step 4 security review: `SiriRemoteHID`'s lifecycle around IOKit's callbacks, with the IOKit parts faked.
struct SiriRemoteHIDTests {
    final class FakeSystem {
        var opened = 0
        var closed = 0
        var pending: [@MainActor () -> Void] = []

        var system: SiriRemoteHID.System {
            SiriRemoteHID.System(
                openManager: { _ in
                    self.opened += 1
                    return NSObject()
                },
                closeManager: { _ in self.closed += 1 },
                nextTurn: { self.pending.append($0) }
            )
        }

        func runNextTurn() {
            let blocks = pending
            pending.removeAll()
            blocks.forEach { $0() }
        }
    }

    private let release = SiriRemoteHID.ButtonEvent(button: .select, isSiri: false, pressed: false)

    /// Step 11 (QA major): Settings hears the remote connect (first interface) and disconnect (last one, or a stop).
    @Test func connectAndDisconnectAreAnnounced() {
        let fake = FakeSystem()
        let hid = SiriRemoteHID(system: fake.system)
        var calls = 0
        hid.onConnectionChange = { calls += 1 }
        hid.start()
        // Kept alive, so the two identifiers differ.
        let objects = [NSObject(), NSObject()]
        let first = ObjectIdentifier(objects[0])
        let second = ObjectIdentifier(objects[1])
        hid.interfaceOpened(first, device: nil)
        #expect(hid.isConnected)
        #expect(calls == 1)
        hid.interfaceOpened(second, device: nil)
        #expect(calls == 1)   // the same remote's other interface
        hid.interfaceRemoved(first)
        #expect(calls == 1)
        hid.interfaceRemoved(second)
        #expect(!hid.isConnected)
        #expect(calls == 2)
        hid.interfaceRemoved(second)
        #expect(calls == 2)
        // Stopping while connected is a disconnect too; stopping without one says nothing.
        hid.interfaceOpened(first, device: nil)
        #expect(calls == 3)
        hid.stop()
        #expect(calls == 4)
        hid.start()
        hid.stop()
        #expect(calls == 4)
        withExtendedLifetime(objects) {}
    }

    @Test func siriRemoteInputForwardsConnectionChanges() {
        let fake = FakeSystem()
        let hid = SiriRemoteHID(system: fake.system)
        let router = InputRouter(bindings: .defaults)
        let input = SiriRemoteInput(inputRouter: router, externalRouter: ExternalRouter(
            isLauncherInFront: { true }, dispatch: { _, _, _ in }, canPostEvents: { false }, postExternal: { _ in }),
            hid: hid, touch: nil)
        var calls = 0
        input.onConnectionChange = { calls += 1 }
        input.start()
        hid.interfaceOpened(ObjectIdentifier(NSObject()), device: nil)
        #expect(input.isConnected)
        #expect(calls == 1)
        input.stop()
        #expect(calls == 2)
    }

    @Test func stopOutsideDeliveryTearsDownAtOnce() {
        let fake = FakeSystem()
        let hid = SiriRemoteHID(system: fake.system)
        hid.start()
        #expect(hid.isRunning)
        hid.stop()
        #expect(fake.closed == 1)
        #expect(!hid.isRunning)
        #expect(fake.pending.isEmpty)
    }

    /// Finding 1: a stop() from inside onButton (Settings turned the remote off with its own Select) waits until
    /// IOKit's callback has returned.
    @Test func stopDuringDeliveryIsDeferred() {
        let fake = FakeSystem()
        let hid = SiriRemoteHID(system: fake.system)
        hid.start()
        var closedDuringCallback: Int?
        hid.onButton = { _ in
            hid.stop()
            closedDuringCallback = fake.closed
        }
        hid.deliver(release)
        #expect(closedDuringCallback == 0)
        #expect(fake.closed == 0)
        #expect(!hid.isRunning)
        fake.runNextTurn()
        #expect(fake.closed == 1)

        // Reading starts again normally after the deferred stop.
        hid.onButton = nil
        hid.start()
        #expect(fake.opened == 2)
        #expect(hid.isRunning)
        hid.stop()
        #expect(fake.closed == 2)
    }

    @Test func startAfterADeferredStopKeepsReading() {
        let fake = FakeSystem()
        let hid = SiriRemoteHID(system: fake.system)
        hid.start()
        hid.onButton = { _ in
            hid.stop()
            hid.start()
        }
        hid.deliver(release)
        fake.runNextTurn()
        #expect(fake.closed == 0)
        #expect(fake.opened == 1)
        #expect(hid.isRunning)
        hid.onButton = nil
        hid.stop()
        #expect(fake.closed == 1)
    }

    /// QA: a value from a device the reader didn't open is dropped and said once per start, not per value.
    @Test func unknownSenderIsLoggedOncePerStart() {
        let fake = FakeSystem()
        let hid = SiriRemoteHID(system: fake.system)
        var events: [SiriRemoteHID.ButtonEvent] = []
        hid.onButton = { events.append($0) }
        let unknown = ObjectIdentifier(NSObject())
        hid.start()
        for pressed in [true, false, true] {
            hid.valueChanged(page: SiriRemoteButton.consumerPage, usage: 0xCD, pressed: pressed, deviceID: unknown)
        }
        #expect(hid.unknownSenderNotices == 1)
        #expect(events.isEmpty)
        hid.stop()
        hid.start()
        hid.valueChanged(page: SiriRemoteButton.consumerPage, usage: 0xCD, pressed: true, deviceID: unknown)
        #expect(hid.unknownSenderNotices == 2)
        #expect(events.isEmpty)
        hid.stop()
    }

    /// Build 24 TV checks: the digitizer (0x0D) is left to macOS so its kernel touch driver starts; every other
    /// interface is still opened (seized, else shared).
    @Test func digitizerInterfaceIsLeftUnopened() {
        #expect(!SiriRemoteHID.shouldOpen(primaryUsagePage: 0x0D))
        #expect(!SiriRemoteHID.shouldOpen(primaryUsagePage: SiriRemoteHID.digitizerPage))
    }

    @Test(arguments: [UInt32(0x0C), 0x01, 0xFF00, 0x20])
    func otherInterfacesAreOpened(page: UInt32) {
        #expect(SiriRemoteHID.shouldOpen(primaryUsagePage: page))
    }

    @Test func interfaceWithoutAPrimaryPageIsOpened() {
        #expect(SiriRemoteHID.shouldOpen(primaryUsagePage: nil))
    }

    /// Finding 2: a reader released while running unschedules its manager (its callbacks hold it unretained).
    @Test func deinitTearsDown() {
        let fake = FakeSystem()
        var hid: SiriRemoteHID? = SiriRemoteHID(system: fake.system)
        hid?.start()
        hid = nil
        #expect(fake.closed == 1)

        // Already stopped: nothing more.
        var stopped: SiriRemoteHID? = SiriRemoteHID(system: fake.system)
        stopped?.start()
        stopped?.stop()
        stopped = nil
        #expect(fake.closed == 2)
    }
}

/// M7h QA: the Siri Remote's Accessibility notice is logged once per run of the remote.
struct SiriRemoteInputTests {
    @Test func accessibilityNoticeOncePerStart() {
        let fake = SiriRemoteHIDTests.FakeSystem()
        let hid = SiriRemoteHID(system: fake.system)
        let inputRouter = InputRouter(bindings: .defaults)
        inputRouter.isActive = { false }
        var posted: [ExternalKey] = []
        let external = ExternalRouter(isLauncherInFront: { false }, dispatch: { _, _, _ in },
                                      canPostEvents: { false }, postExternal: { posted.append($0) })
        let input = SiriRemoteInput(inputRouter: inputRouter, externalRouter: external, hid: hid, touch: nil, now: { 0 })

        func click(_ button: SiriRemoteButton) {
            hid.deliver(.init(button: button, isSiri: false, pressed: true))
            hid.deliver(.init(button: button, isSiri: false, pressed: false))
        }

        input.start()
        click(.back)
        click(.playPause)
        #expect(input.accessibilityNotices == 1)
        input.stop()
        input.start()
        click(.back)
        #expect(input.accessibilityNotices == 2)
        #expect(posted.isEmpty)
        input.stop()
    }
}

/// M7h step 7: trackpad mode end to end through `SiriRemoteInput` (L4, L5, L7).
struct SiriRemoteTrackpadModeTests {
    final class Harness {
        let fake = SiriRemoteHIDTests.FakeSystem()
        let hid: SiriRemoteHID
        let input: SiriRemoteInput
        var time: TimeInterval = 0
        var canPost = true
        /// Security M1: what `KioskGuard.pointerGate` says about the app in front.
        var gate: KioskGuard.PointerGate = .allowed
        var dispatched: [(command: RemoteCommand, isGlobal: Bool)] = []
        var actions: [PointerAction] = []
        var modeChanges: [Bool] = []
        /// Step 13e (c): pointer reveals (`revealPointer`).
        var reveals = 0

        init(launcherInFront: Bool = true) {
            hid = SiriRemoteHID(system: fake.system)
            let inputRouter = InputRouter(bindings: .defaults)
            inputRouter.isActive = { launcherInFront }
            weak var harness: Harness?
            let external = ExternalRouter(isLauncherInFront: { launcherInFront },
                                          dispatch: { command, isGlobal, _ in harness?.dispatched.append((command, isGlobal)) },
                                          canPostEvents: { harness?.canPost ?? false }, postExternal: { _ in })
            var input: SiriRemoteInput?
            input = SiriRemoteInput(inputRouter: inputRouter, externalRouter: external, hid: hid, touch: nil,
                                    pointer: { harness?.actions.append($0) },
                                    pointerGate: { harness?.gate ?? .allowed },
                                    revealPointer: { harness?.reveals += 1 }, now: { harness?.time ?? 0 })
            self.input = input!
            harness = self
            self.input.onTrackpadModeChange = { [unowned self] in self.modeChanges.append($0) }
            self.input.start()
        }

        func press(_ button: SiriRemoteButton) { hid.deliver(.init(button: button, isSiri: false, pressed: true)) }
        func release(_ button: SiriRemoteButton) { hid.deliver(.init(button: button, isSiri: false, pressed: false)) }
        func click(_ button: SiriRemoteButton) {
            press(button)
            release(button)
        }

        /// Siri twice within 0.4 s (L5).
        func doubleSiri() {
            for offset in [0.0, 0.2] {
                time += offset
                hid.deliver(.init(button: nil, isSiri: true, pressed: true))
                hid.deliver(.init(button: nil, isSiri: true, pressed: false))
            }
        }

        var clicks: [PointerButton] {
            actions.compactMap { if case .click(let button) = $0 { button } else { nil } }
        }
        var moves: [PointerAction] {
            actions.filter { if case .move = $0 { true } else { false } }
        }
    }

    @Test func siriDoublePressTogglesOnAndOff() {
        let harness = Harness()
        harness.doubleSiri()
        #expect(harness.input.isTrackpadMode)
        harness.time = 2
        harness.doubleSiri()
        #expect(!harness.input.isTrackpadMode)
        #expect(harness.modeChanges == [true, false])
        harness.input.stop()
    }

    @Test func homeLeavesTrackpadModeAndGoesHome() {
        let harness = Harness()
        harness.doubleSiri()
        harness.click(.tv)
        #expect(!harness.input.isTrackpadMode)
        #expect(harness.modeChanges == [true, false])
        #expect(harness.dispatched.map(\.command) == [.home])
        // Home without trackpad mode changes nothing.
        harness.click(.tv)
        #expect(harness.modeChanges == [true, false])
        harness.input.stop()
    }

    @Test func shortCentreIsALeftClickThroughThePointer() {
        let harness = Harness()
        harness.doubleSiri()
        harness.time = 1
        harness.press(.select)
        harness.time = 1.1
        harness.release(.select)
        #expect(harness.clicks == [.left])
        #expect(harness.dispatched.isEmpty)
        harness.input.stop()
    }

    @Test func longCentreIsOneRightClick() async throws {
        let harness = Harness()
        harness.doubleSiri()
        harness.time = 1
        harness.press(.select)
        harness.time = 1 + SiriRemoteTiming.centreLongPress + 0.05
        // The input's 30 ms tick task fires the long press.
        for _ in 0..<100 where harness.clicks.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        harness.time = 3
        try await Task.sleep(for: .milliseconds(100))
        harness.release(.select)
        #expect(harness.clicks == [.right])
        #expect(harness.dispatched.isEmpty)
        harness.input.stop()
    }

    /// L3: Back is Back in trackpad mode too.
    @Test func backStillRoutesBack() {
        let harness = Harness()
        harness.doubleSiri()
        harness.click(.back)
        #expect(harness.dispatched.map(\.command) == [.back])
        #expect(harness.input.isTrackpadMode)
        #expect(harness.clicks.isEmpty)
        harness.input.stop()
    }

    /// Step 5 QA: a click doesn't drag the pointer off its target.
    @Test func pointerHoldsDuringAClick() {
        let harness = Harness()
        harness.doubleSiri()
        // The finger rests, then the press moves it while the button is down.
        harness.input.touched(SwipeRecognizerTests.touching(0.5, 0.5, at: 1))
        harness.time = 1.05
        harness.press(.select)
        for frame in SwipeRecognizerTests.slide(from: (0.5, 0.5), to: (0.56, 0.45), start: 1.06, duration: 0.1) {
            harness.input.touched(frame)
        }
        harness.time = 1.2
        harness.release(.select)
        // Just after the release (within the quiet time): still held.
        harness.input.touched(SwipeRecognizerTests.touching(0.57, 0.44, at: 1.3))
        #expect(harness.moves.isEmpty)
        #expect(harness.clicks == [.left])
        // After the quiet time moves resume from where the finger is (no jump).
        harness.input.touched(SwipeRecognizerTests.touching(0.58, 0.44, at: 1.5))
        #expect(harness.moves.count == 1)
        if case .move(let dx, let dy) = harness.moves.first {
            #expect(abs(dx - 0.01 * TrackpadMapper.pointerScale) < 0.001)
            #expect(abs(dy) < 0.001)
        }
        harness.input.stop()
    }

    @Test func withoutAccessibilityNothingIsPosted() {
        let harness = Harness()
        harness.canPost = false
        harness.doubleSiri()
        harness.click(.select)
        for frame in SwipeRecognizerTests.slide(from: (0.3, 0.5), to: (0.6, 0.5), start: 1, duration: 0.2) {
            harness.input.touched(frame)
        }
        #expect(harness.actions.isEmpty)
        #expect(harness.input.accessibilityNotices == 1)
        harness.input.stop()
    }

    /// Security M1: with the kiosk lock in force and an app the guard doesn't allow in front, no move, click or
    /// scroll is posted, the refusal is logged once per front app, and trackpad mode stays on.
    @Test func blockedFrontAppGetsNoPointerActions() {
        let harness = Harness()
        harness.doubleSiri()
        harness.gate = .blocked(bundleID: "com.apple.mail")
        harness.time = 1
        harness.click(.select)
        for frame in SwipeRecognizerTests.slide(from: (0.3, 0.5), to: (0.6, 0.5), start: 2, duration: 0.2) {
            harness.input.touched(frame)
        }
        harness.input.touched(SwipeRecognizerTests.lift(at: 2.3))
        // A scroll from the right edge.
        for frame in SwipeRecognizerTests.slide(from: (0.9, 0.3), to: (0.9, 0.6), start: 3, duration: 0.2) {
            harness.input.touched(frame)
        }
        #expect(harness.actions.isEmpty)
        #expect(harness.input.isTrackpadMode)
        #expect(harness.input.pointerBlockedNotices == 1)
        // Another app not allowed: said again.
        harness.gate = .blocked(bundleID: "com.apple.Notes")
        harness.time = 4
        harness.click(.select)
        #expect(harness.input.pointerBlockedNotices == 2)
        #expect(harness.actions.isEmpty)
        harness.input.stop()
    }

    /// Security M1: an allowed app in front (MMTVL, a session app, Reflector, or no lock) gets actions as before.
    @Test func allowedFrontAppGetsPointerActions() {
        let harness = Harness()
        harness.doubleSiri()
        harness.gate = .blocked(bundleID: "com.apple.mail")
        harness.time = 1
        harness.click(.select)
        harness.gate = .allowed
        harness.time = 2
        harness.click(.select)
        for frame in SwipeRecognizerTests.slide(from: (0.3, 0.5), to: (0.6, 0.5), start: 3, duration: 0.2) {
            harness.input.touched(frame)
        }
        #expect(harness.clicks == [.left])
        #expect(!harness.moves.isEmpty)
        // Back to the blocked app after an allowed one: said again.
        harness.gate = .blocked(bundleID: "com.apple.mail")
        harness.time = 4
        harness.click(.select)
        #expect(harness.input.pointerBlockedNotices == 2)
        harness.input.stop()
    }

    @Test func stoppingTheRemoteLeavesTrackpadMode() {
        let harness = Harness()
        harness.doubleSiri()
        harness.input.stop()
        #expect(!harness.input.isTrackpadMode)
        #expect(harness.modeChanges == [true, false])
    }

    /// Security finding 3: after the surfaces stop or rebuild (sleep, wake), the first frame doesn't move by a
    /// stale delta from before.
    @Test func surfaceResetForgetsTheTouch() {
        let harness = Harness()
        harness.doubleSiri()
        harness.input.touched(SwipeRecognizerTests.touching(0.3, 0.5, at: 1))
        harness.input.touchSurfacesReset()
        harness.input.touched(SwipeRecognizerTests.touching(0.5, 0.5, at: 100))
        #expect(harness.moves.isEmpty)
        harness.input.touched(SwipeRecognizerTests.touching(0.51, 0.5, at: 100.02))
        #expect(harness.moves.count == 1)
        harness.input.stop()
    }

    /// L7: `cursorAutoHide` doesn't hide the pointer while trackpad mode is on.
    @Test func autoHideIsSuppressedInTrackpadMode() {
        #expect(CursorAutoHide.hides(setting: true, isTrackpadMode: false))
        #expect(!CursorAutoHide.hides(setting: true, isTrackpadMode: true))
        #expect(!CursorAutoHide.hides(setting: false, isTrackpadMode: false))
        #expect(!CursorAutoHide.hides(setting: false, isTrackpadMode: true))
    }

    /// Step 13e (c) QA minor: trackpad mode on shows the pointer; off hides it again only with auto-hide on and MMTVL
    /// active (the double-press isn't a dispatched command, so nothing else would).
    @Test func trackpadModeChangesShowAndHideThePointer() {
        for setting in [true, false] {
            for isAppActive in [true, false] {
                #expect(CursorAutoHide.hiddenUntilMouseMoves(trackpadModeOn: true, setting: setting,
                                                             isAppActive: isAppActive) == false)
            }
        }
        #expect(CursorAutoHide.hiddenUntilMouseMoves(trackpadModeOn: false, setting: true, isAppActive: true) == true)
        #expect(CursorAutoHide.hiddenUntilMouseMoves(trackpadModeOn: false, setting: true, isAppActive: false) == nil)
        #expect(CursorAutoHide.hiddenUntilMouseMoves(trackpadModeOn: false, setting: false, isAppActive: true) == nil)
        #expect(CursorAutoHide.hiddenUntilMouseMoves(trackpadModeOn: false, setting: false, isAppActive: false) == nil)
    }
}
