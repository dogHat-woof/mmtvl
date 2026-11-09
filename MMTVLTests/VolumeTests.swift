import Foundation
import Testing
@testable import MMTVL

struct VolumeTests {
    private func choose(_ mode: VolumeMode, receiver: Bool = false, soundSource: Bool = false, settable: Bool = false,
                        active: Bool = false) -> VolumeRoute {
        VolumeRoute.choose(mode: mode, receiverReady: receiver, soundSourceRunning: soundSource, systemSettable: settable,
                           launcherActive: active)
    }

    @Test func autoRoute() {
        #expect(choose(.auto, soundSource: true, settable: true, active: true) == .keys)
        #expect(choose(.auto, settable: true, active: true) == .system)
        #expect(choose(.auto, active: true) == .app)
        #expect(choose(.auto) == .unavailable)
    }

    /// D44: a ready receiver comes first in `auto`, ahead of SoundSource, the system and the app.
    @Test func autoRouteWithAReadyReceiver() {
        #expect(choose(.auto, receiver: true, soundSource: true, settable: true, active: true) == .receiver)
        #expect(choose(.auto, receiver: true) == .receiver)
    }

    @Test func receiverRoute() {
        #expect(choose(.receiver, receiver: true) == .receiver)
        #expect(choose(.receiver, soundSource: true, settable: true, active: true) == .unavailable)
    }

    @Test func forcedRoutes() {
        #expect(choose(.keys) == .keys)
        #expect(choose(.system, soundSource: true, settable: true) == .system)
        #expect(choose(.system, soundSource: true, active: true) == .unavailable)
        #expect(choose(.app, soundSource: true, settable: true, active: true) == .app)
        #expect(choose(.app, soundSource: true, settable: true) == .unavailable)
    }

    /// Forced modes ignore a ready receiver.
    @Test func forcedRoutesWithAReadyReceiver() {
        #expect(choose(.keys, receiver: true) == .keys)
        #expect(choose(.system, receiver: true, settable: true) == .system)
        #expect(choose(.system, receiver: true) == .unavailable)
        #expect(choose(.app, receiver: true, active: true) == .app)
        #expect(choose(.app, receiver: true) == .unavailable)
    }

    @Test func appVolume() {
        var volume = AppVolume()
        volume.apply(.up)
        #expect(volume.level == 100)
        for _ in 0..<3 { volume.apply(.down) }
        #expect(volume.level == 85)
        volume.apply(.mute)
        #expect(volume.muted)
        volume.apply(.mute)
        #expect(!volume.muted)
        volume.apply(.mute)
        volume.apply(.up)
        #expect(!volume.muted)
        #expect(volume.level == 90)

        var silent = AppVolume(level: 0, muted: false)
        silent.apply(.down)
        #expect(silent.level == 0)
    }

    @Test func systemVolumeStep() {
        #expect(SystemVolume.step(0.5, .up) == 0.5625)
        #expect(SystemVolume.step(0, .down) == 0)
        #expect(SystemVolume.step(0.97, .up) == 1)
        #expect(SystemVolume.step(0.51, .up) == 0.5625)
        #expect(SystemVolume.step(0.5, .down) == 0.4375)
    }

    @Test func volumeModeParsing() {
        #expect(VolumeMode(rawValue: "keys") == .keys)
        #expect(VolumeMode(rawValue: "receiver") == .receiver)
        #expect(VolumeMode(rawValue: "bogus") == nil)
    }

    /// Step 10: the receiver's dB as the phone's level, −80 dB → 0, 0 dB → 1, linear and clamped; never from `raw`.
    @Test func receiverFeedbackMapping() {
        #expect(VolumeFeedback.receiver(dB: -20, muted: false) == .level(0.75, muted: false))
        #expect(VolumeFeedback.receiver(dB: -40, muted: nil) == .level(0.5, muted: false))
        #expect(VolumeFeedback.receiver(dB: 0, muted: false) == .level(1, muted: false))
        #expect(VolumeFeedback.receiver(dB: 12, muted: false) == .level(1, muted: false))
        #expect(VolumeFeedback.receiver(dB: -80, muted: false) == .level(0, muted: false))
        #expect(VolumeFeedback.receiver(dB: -90.5, muted: false) == .level(0, muted: false))
        // QA minor 5: −∞ (Pioneer `VOL00`, Denon `MV00`) is the bottom, not "unknown".
        #expect(VolumeFeedback.receiver(dB: -.infinity, muted: false) == .level(0, muted: false))
        #expect(VolumeFeedback.receiver(dB: -.infinity, muted: true) == .level(0, muted: true))
        #expect(VolumeFeedback.receiver(dB: -20, muted: true) == .level(0.75, muted: true))
        // No dB (Onkyo, or −∞): muted still says so; otherwise the level is unknown.
        #expect(VolumeFeedback.receiver(dB: nil, muted: true) == .level(0, muted: true))
        #expect(VolumeFeedback.receiver(dB: nil, muted: false) == .sentKeys)
        #expect(VolumeFeedback.receiver(dB: nil, muted: nil) == .sentKeys)
    }

    /// L8: "Volume −20 dB" / "Muted" / "Volume" for the receiver.
    /// Security (step 10): formatting never traps, whatever the value.
    @Test func formatIsSafeForAnyValue() {
        #expect(VolumeToast.format(dB: -.infinity) == "Min")
        #expect(VolumeToast.format(dB: 1e18) == "+1000000000000000000 dB")
        #expect(!VolumeToast.format(dB: -1e300).isEmpty)
        #expect(!VolumeToast.format(dB: .nan).isEmpty)
        #expect(!VolumeToast.format(dB: .infinity).isEmpty)
        #expect(VolumeToast.format(dB: -0.0) == "0 dB")
        #expect(VolumeToast.message(for: VolumeOutcome(route: .app, feedback: .level(.nan, muted: false)))?.text
                == "Volume 0 %")
    }

    @Test func toastMessages() {
        func text(_ route: VolumeRoute, _ feedback: VolumeFeedback, dB: Double? = nil) -> String? {
            VolumeToast.message(for: VolumeOutcome(route: route, feedback: feedback, dB: dB))?.text
        }
        #expect(text(.receiver, .level(0.75, muted: false), dB: -20) == "Volume \u{2212}20 dB")
        #expect(text(.receiver, .level(0.75, muted: false), dB: -20.5) == "Volume \u{2212}20.5 dB")
        #expect(text(.receiver, .level(1, muted: false), dB: 3) == "Volume +3 dB")
        #expect(text(.receiver, .level(1, muted: false), dB: 0) == "Volume 0 dB")
        #expect(text(.receiver, .level(0.75, muted: true), dB: -20) == "Muted")
        #expect(text(.receiver, .sentKeys) == "Volume")
        #expect(text(.receiver, .unavailable(VolumeController.notAnsweringMessage)) == "Receiver isn't answering")
        #expect(text(.app, .level(0.5, muted: false)) == "Volume 50 %")
        #expect(text(.receiver, .level(0, muted: false), dB: -.infinity) == "Volume Min")
        // User decision: at the cap.
        #expect(VolumeToast.message(for: VolumeOutcome(route: .receiver, feedback: .level(1, muted: false), dB: 0,
                                                       cappedAt: 0))?.text == "Volume 0 dB (max)")
        #expect(VolumeToast.message(for: VolumeOutcome(route: .receiver, feedback: .level(0.9, muted: false), dB: -8,
                                                       cappedAt: -10))?.text == "Volume \u{2212}8 dB (max)")
        // QA minor 2 (second pass): above the cap, the receiver's own level.
        #expect(VolumeToast.message(for: VolumeOutcome(route: .receiver, feedback: .level(1, muted: false), dB: 5,
                                                       cappedAt: 0))?.text == "Volume +5 dB (max)")
        #expect(VolumeToast.message(for: VolumeOutcome(route: .receiver, feedback: .sentKeys, cappedAt: 0))?.text
                == "Volume")
        #expect(text(.keys, .sentKeys) == nil)
        #expect(VolumeToast.message(for: VolumeOutcome(route: .receiver, feedback: .level(1, muted: true)))?.symbol
                == VolumeToast.mutedSymbol)
        #expect(VolumeToast.message(for: VolumeOutcome(route: .receiver, feedback: .sentKeys))?.symbol
                == VolumeToast.volumeSymbol)
    }

    /// Step 13b: Show Volume. On, every message shows as before; off, only the `.unavailable` errors do.
    @Test func showVolumeRule() {
        let outcomes: [(VolumeOutcome, isError: Bool)] = [
            (VolumeOutcome(route: .receiver, feedback: .level(0.75, muted: false), dB: -20), false),
            (VolumeOutcome(route: .receiver, feedback: .level(1, muted: false), dB: 0, cappedAt: 0), false),
            (VolumeOutcome(route: .receiver, feedback: .level(0, muted: false), dB: -.infinity), false),
            (VolumeOutcome(route: .receiver, feedback: .level(0.75, muted: true), dB: -20), false),
            (VolumeOutcome(route: .receiver, feedback: .sentKeys), false),
            (VolumeOutcome(route: .app, feedback: .level(0.5, muted: false)), false),
            (VolumeOutcome(route: .system, feedback: .level(0.5, muted: true)), false),
            (VolumeOutcome(route: .receiver, feedback: .unavailable(VolumeController.notAnsweringMessage)), true),
            (VolumeOutcome(route: .unavailable, feedback: .unavailable(VolumeController.unavailableMessage)), true),
        ]
        for (outcome, isError) in outcomes {
            let on = VolumeToast.message(for: outcome, enabled: true)
            #expect(on == VolumeToast.message(for: outcome), "\(outcome)")
            #expect(on != nil, "\(outcome)")
            let off = VolumeToast.message(for: outcome, enabled: false)
            #expect(off == (isError ? on : nil), "\(outcome)")
        }
        #expect(VolumeToast.message(for: VolumeOutcome(route: .unavailable, feedback: .unavailable(VolumeController.unavailableMessage)),
                                    enabled: false) == VolumeToast.Message(text: "Volume can't be changed here",
                                                                           symbol: VolumeToast.errorSymbol))
        // SoundSource's keys show nothing either way.
        #expect(VolumeToast.message(for: VolumeOutcome(route: .keys, feedback: .sentKeys), enabled: true) == nil)
        #expect(VolumeToast.message(for: VolumeOutcome(route: .keys, feedback: .sentKeys), enabled: false) == nil)
    }
}

/// M7h step 10 (D44): `VolumeController` on a real `ReceiverController` over a fake Pioneer port.
struct VolumeControllerReceiverTests {
    final class Harness {
        let clock = FakeReceiverClock()
        let ports: FakeReceiverPorts
        let receiver: ReceiverController
        var controller: VolumeController!
        var mode: VolumeMode = .auto
        var maxDB = 0.0
        var launcherActive = true
        var time: TimeInterval = 0
        var appVolumes: [AppVolume] = []

        init() {
            ports = FakeReceiverPorts(clock: clock)
            let ports = ports
            receiver = ReceiverController(clock: clock, makeTransport: { ports.make(link: $0, codec: $1) })
            ports.replies[.pioneer] = [
                .queryVolume: ["VOL61"], .volumeUp: ["VOL62"], .volumeDown: ["VOL60"],
                .queryMute: ["MUT1"], .mute(true): ["MUT0"], .mute(false): ["MUT1"],
            ]
            weak var harness: Harness?
            controller = VolumeController(
                mode: { harness?.mode ?? .auto },
                isLauncherActive: { harness?.launcherActive ?? false },
                applyAppVolume: { harness?.appVolumes.append($0) },
                receiver: receiver,
                maxDB: { harness?.maxDB ?? 0 },
                soundSourceRunning: { false },
                systemSettable: { false },
                now: { harness?.time ?? 0 },
                sleep: { seconds in
                    harness?.time += seconds
                    await Task.yield()
                })
            harness = self
            receiver.onLinkUp = { harness?.controller.receiverLinkUp() }
        }

        var port: FakeReceiverTransport { ports.made.last! }

        /// What was written, without the wake CR.
        var commands: [String] {
            port.writes.map { String(decoding: $0.bytes, as: UTF8.self) }.filter { $0 != "\r" }
        }

        /// Set up and answering (the link-up probe got its reply).
        func ready() async {
            receiver.configure(brand: .pioneer, serialPort: nil)
            await controller.probeTask?.value
            #expect(controller.receiverReady)
        }

        func perform(_ action: VolumeAction) async -> VolumeOutcome? {
            var result: VolumeOutcome?
            controller.perform(action) { result = $0 }
            await controller.receiverTask?.value
            return result
        }
    }

    @Test func notReadyUntilTheReceiverAnswers() async {
        let harness = Harness()
        #expect(!harness.controller.receiverReady)
        harness.receiver.onLinkUp = nil   // the launch probe only
        harness.receiver.configure(brand: .pioneer, serialPort: nil)
        #expect(!harness.controller.receiverReady)   // set up and connected, no reply yet
        harness.controller.probeReceiverIfNeeded()
        await harness.controller.probeTask?.value
        #expect(harness.commands == ["?V\r"])
        #expect(harness.controller.receiverReady)
        #expect(harness.controller.consumesVolumeKeys())
    }

    @Test func upGoesToTheReceiverWithItsDB() async {
        let harness = Harness()
        await harness.ready()
        let outcome = await harness.perform(.up)
        #expect(harness.commands == ["?V\r", "VU\r"])
        #expect(outcome == VolumeOutcome(route: .receiver, feedback: .level(61.0 / 80, muted: false), dB: -19))
        #expect(harness.appVolumes.isEmpty)
        #expect(await harness.perform(.down)?.dB == -21)
    }

    /// The QA note from step 8b: presses while a command waits for its reply don't queue up; at most one waits.
    @Test func heldRepeatsCoalesce() async {
        let harness = Harness()
        await harness.ready()
        var answers = Array(repeating: 0, count: 7)
        for index in 0..<6 { harness.controller.perform(.up) { _ in answers[index] += 1 } }
        harness.controller.perform(.down) { _ in answers[6] += 1 }   // the latest replaces the waiting one
        #expect(harness.controller.isReceiverBusy)
        await harness.controller.receiverTask?.value
        #expect(harness.commands == ["?V\r", "VU\r", "VD\r"])
        #expect(answers == Array(repeating: 1, count: 7))   // every press is answered, once
        #expect(!harness.controller.isReceiverBusy)
        // After the release nothing more is sent.
        await harness.clock.sleep(for: .seconds(5))
        #expect(harness.commands.count == 3)
    }

    @Test func muteFromAnUnknownStateAsksFirst() async {
        let harness = Harness()
        await harness.ready()
        #expect(harness.receiver.state.muted == nil)
        let outcome = await harness.perform(.mute)
        #expect(harness.commands == ["?V\r", "?M\r", "MO\r"])
        #expect(outcome?.feedback == .level(0.75, muted: true))
        #expect(outcome.flatMap(VolumeToast.message(for:))?.text == "Muted")
    }

    @Test func muteFromAKnownStateSetsTheOpposite() async {
        let harness = Harness()
        await harness.ready()
        harness.port.onLine?("MUT0")   // muted at the receiver
        let outcome = await harness.perform(.mute)
        #expect(harness.commands == ["?V\r", "MF\r"])
        #expect(outcome?.feedback == .level(0.75, muted: false))
        #expect(await harness.perform(.mute)?.feedback == .level(0.75, muted: true))
        #expect(harness.commands.last == "MO\r")
    }

    /// A receiver that stops answering ends that press, then the next press takes D25's order; one that answers
    /// again is used from the next press after the probe.
    @Test func notAnsweringFallsBackAndRecovers() async {
        let harness = Harness()
        await harness.ready()
        harness.port.replies[Array("VU\r".utf8)] = nil
        var outcomes: [VolumeOutcome] = []
        harness.controller.perform(.up) { outcomes.append($0) }
        harness.controller.perform(.up) { outcomes.append($0) }   // waiting: dropped with the first
        await harness.controller.receiverTask?.value
        #expect(outcomes.map(\.feedback) == Array(repeating: .unavailable("Receiver isn't answering"), count: 2))
        #expect(harness.commands == ["?V\r", "VU\r"])
        #expect(!harness.controller.receiverReady)
        #expect(!harness.controller.consumesVolumeKeys())

        // Falls back to MMTVL's own volume (in front, no SoundSource, no settable output), without waiting.
        harness.time = VolumeController.probeInterval
        var fallback: VolumeOutcome?
        harness.controller.perform(.down) { fallback = $0 }
        #expect(fallback == VolumeOutcome(route: .app, feedback: .level(0.95, muted: false)))
        #expect(harness.appVolumes.count == 1)
        // That press asked the receiver again; it answered, so the next press goes there.
        await harness.controller.probeTask?.value
        #expect(harness.commands.last == "?V\r")
        #expect(harness.controller.receiverReady)
        harness.port.replies[Array("VU\r".utf8)] = ["VOL62"]
        #expect(await harness.perform(.up)?.route == .receiver)
    }

    @Test func probesAtMostEveryInterval() async {
        let harness = Harness()
        harness.ports.replies[.pioneer] = [:]   // never answers
        harness.receiver.onLinkUp = nil
        harness.receiver.configure(brand: .pioneer, serialPort: nil)
        harness.controller.probeReceiverIfNeeded()
        await harness.controller.probeTask?.value
        harness.time = 5
        harness.controller.probeReceiverIfNeeded()
        #expect(harness.controller.probeTask == nil)
        harness.time = VolumeController.probeInterval
        harness.controller.probeReceiverIfNeeded()
        await harness.controller.probeTask?.value
        #expect(harness.commands == ["?V\r", "?V\r"])
    }

    /// Forced routes never take the volume keys, ready receiver or not.
    @Test func forcedModesDontConsumeTheKeys() async {
        let harness = Harness()
        await harness.ready()
        harness.mode = .system
        #expect(!harness.controller.consumesVolumeKeys())
        harness.mode = .receiver
        #expect(harness.controller.consumesVolumeKeys())
    }

    @Test func forcedReceiverWithoutOneSaysSo() {
        let harness = Harness()
        harness.mode = .receiver
        var outcome: VolumeOutcome?
        harness.controller.perform(.up) { outcome = $0 }
        #expect(outcome?.feedback == .unavailable("Receiver isn't answering"))
    }

    // MARK: Review fixes

    /// Security low: a flood of presses while one is on its way keeps a bounded wait list; each is answered once.
    @Test func floodingPressesStayBounded() async {
        let harness = Harness()
        await harness.ready()
        var answers = Array(repeating: 0, count: 1001)
        let actions: [VolumeAction] = [.up, .down, .mute]
        for index in 0...1000 {
            harness.controller.perform(actions[index % 3]) { _ in answers[index] += 1 }
            #expect(harness.controller.waitingCount <= 2)
        }
        await harness.controller.receiverTask?.value
        #expect(answers.allSatisfy { $0 == 1 })
        #expect(harness.controller.waitingCount == 0)
        // The first (Vol+), then the latest waiting step (press 1000, Vol−) and one Mute (333 waiting: odd), asked first.
        #expect(harness.commands == ["?V\r", "VU\r", "VD\r", "?M\r", "MO\r"])
    }

    /// QA minor 1: waiting Mutes keep their parity; an odd number toggles once.
    @Test func threeMutesWhileBusyToggleOnce() async {
        let harness = Harness()
        await harness.ready()
        harness.port.onLine?("MUT1")   // not muted
        harness.controller.perform(.up)
        for _ in 0..<3 { harness.controller.perform(.mute) }
        await harness.controller.receiverTask?.value
        #expect(harness.commands == ["?V\r", "VU\r", "MO\r"])
        #expect(harness.receiver.state.muted == true)
    }

    @Test func threeMutesInARowEndMuted() async {
        let harness = Harness()
        await harness.ready()
        harness.port.onLine?("MUT1")
        for _ in 0..<3 { harness.controller.perform(.mute) }   // one on its way, two waiting: they cancel
        await harness.controller.receiverTask?.value
        #expect(harness.commands == ["?V\r", "MO\r"])
        #expect(harness.receiver.state.muted == true)
    }

    /// QA minor 1 (second pass): waiting slots run in the order they were filled.
    @Test func aMutePressedBeforeAStepRunsFirst() async {
        let harness = Harness()
        await harness.ready()
        harness.port.onLine?("MUT1")
        harness.controller.perform(.down)   // on its way
        harness.controller.perform(.mute)
        harness.controller.perform(.up)
        await harness.controller.receiverTask?.value
        #expect(harness.commands == ["?V\r", "VD\r", "MO\r", "VU\r"])
    }

    @Test func aWaitingMuteIsNeverReplaced() async {
        let harness = Harness()
        await harness.ready()
        harness.port.onLine?("MUT1")
        harness.controller.perform(.down)
        harness.controller.perform(.up)
        harness.controller.perform(.mute)
        harness.controller.perform(.up)
        await harness.controller.receiverTask?.value
        #expect(harness.commands == ["?V\r", "VD\r", "VU\r", "MO\r"])
        #expect(harness.receiver.state.muted == true)
    }

    /// User decision: Vol+ never steps above `receiverMaxDB`.
    @Test func upStopsAtTheCap() async {
        let harness = Harness()
        await harness.ready()
        harness.port.onLine?("VOL81")   // 0 dB, the default cap
        let outcome = await harness.perform(.up)
        #expect(harness.commands == ["?V\r"])   // nothing sent
        #expect(outcome == VolumeOutcome(route: .receiver, feedback: .level(1, muted: false), dB: 0, cappedAt: 0))
        #expect(outcome.flatMap(VolumeToast.message(for:))?.text == "Volume 0 dB (max)")
        // Down always goes.
        #expect(await harness.perform(.down)?.cappedAt == nil)
        #expect(harness.commands.last == "VD\r")
    }

    @Test func upBelowTheCapSends() async {
        let harness = Harness()
        harness.maxDB = -10
        await harness.ready()
        harness.port.onLine?("VOL70")   // −11 dB
        #expect(await harness.perform(.up)?.cappedAt == nil)
        #expect(harness.commands.last == "VU\r")
        harness.port.onLine?("VOL71")   // −10 dB: at the cap
        #expect(await harness.perform(.up)?.cappedAt == -10)
        #expect(harness.commands.last == "VU\r")
        #expect(harness.commands.count == 2)
        harness.port.onLine?("VOL75")   // above it (the receiver's own knob)
        let above = await harness.perform(.up)
        #expect(above?.cappedAt == -10)
        #expect(above.flatMap(VolumeToast.message(for:))?.text == "Volume \u{2212}6 dB (max)")
        #expect(await harness.perform(.down)?.cappedAt == nil)
        #expect(harness.commands.last == "VD\r")
    }

    /// QA minor 2: a transport that comes up is asked at once, so the receiver is ready without a press.
    @Test func readyAfterTheLinkComesUpWithoutAPress() async {
        let harness = Harness()
        harness.ports.available = false
        harness.receiver.configure(brand: .pioneer, serialPort: nil)
        harness.controller.probeReceiverIfNeeded()   // the launch probe: no port yet
        await harness.controller.probeTask?.value
        #expect(!harness.controller.receiverReady)
        harness.ports.available = true
        for _ in 0..<2000 where !harness.controller.receiverReady { await Task.yield() }
        #expect(harness.controller.receiverReady)
        #expect(harness.commands == ["?V\r"])
        harness.receiver.stop()
    }
}

/// QA minor 3: a network receiver closed for being idle and now unreachable holds a press for about 1.5 s, not 5 s.
struct VolumeControllerNetworkTests {
    final class Box { var outcome: VolumeOutcome? }

    @Test func unreachableAfterTheIdleCloseFailsQuickly() async {
        let clock = ManualReceiverClock()
        let ports = FakeReceiverPorts(clock: clock)
        ports.replies[.onkyo] = [.queryVolume: ["!1MVL28"]]
        let receiver = ReceiverController(clock: clock, makeTransport: { ports.make(link: $0, codec: $1) })
        let controller = VolumeController(mode: { .auto }, isLauncherActive: { false }, applyAppVolume: { _ in },
                                          receiver: receiver, soundSourceRunning: { false }, systemSettable: { false })
        receiver.configure(brand: .onkyo, link: .network(host: "192.168.1.20", port: nil))
        #expect(await receiver.request(.queryVolume) != nil)
        await clock.advance(by: ReceiverController.networkIdleTimeout)
        #expect(!receiver.isConnected)
        #expect(controller.receiverReady)   // closed for being idle: the next command opens it

        ports.startsReady = false   // and now it doesn't come up
        let box = Box()
        controller.perform(.up) { box.outcome = $0 }
        await clock.advance(by: .milliseconds(1400))
        #expect(box.outcome == nil)
        await clock.advance(by: .milliseconds(200))
        #expect(box.outcome?.feedback == .unavailable(VolumeController.notAnsweringMessage))
        #expect(!controller.isReceiverBusy)
        receiver.stop()
        await clock.advance(by: .seconds(1000))
    }

    /// Step 13e (build 25's Live TV skip): a press for a ready receiver never asks for the app list or CoreAudio (IPC
    /// on the main actor); without a receiver they're asked as before.
    @Test func aReadyReceiverSkipsTheAppListAndCoreAudio() async {
        let clock = ManualReceiverClock()
        let ports = FakeReceiverPorts(clock: clock)
        ports.replies[.onkyo] = [.queryVolume: ["!1MVL28"]]
        let receiver = ReceiverController(clock: clock, makeTransport: { ports.make(link: $0, codec: $1) })
        var queries = 0
        let controller = VolumeController(mode: { .auto }, isLauncherActive: { false }, applyAppVolume: { _ in },
                                          receiver: receiver,
                                          soundSourceRunning: { queries += 1; return false },
                                          systemSettable: { queries += 1; return false })
        receiver.configure(brand: .onkyo, link: .network(host: "192.168.1.20", port: nil))
        #expect(await receiver.request(.queryVolume) != nil)
        #expect(controller.receiverReady)
        controller.perform(.up)
        #expect(controller.isReceiverBusy)
        #expect(queries == 0)
        receiver.stop()
        await clock.advance(by: .seconds(1000))

        let plain = VolumeController(mode: { .auto }, isLauncherActive: { false }, applyAppVolume: { _ in },
                                     soundSourceRunning: { queries += 1; return false },
                                     systemSettable: { queries += 1; return false })
        plain.perform(.up)
        #expect(queries == 2)
    }

    /// Security (second pass): a host that accepts, answers the probe and closes. Probes don't count as activity and
    /// run at most every `probeInterval`, so the idle close still comes after 5 minutes and nothing reconnects after it.
    @Test func aHostThatAnswersAndClosesStillIdlesOut() async {
        /// Ready at once; answers `?V` with one valid line, then closes. Writes nothing else back.
        final class AnswerThenClose: ReceiverTransport {
            let name = "Fake host"
            var onLine: ((String) -> Void)?
            var onClose: (() -> Void)?
            private(set) var queries = 0

            func write(_ bytes: [UInt8]) -> Bool {
                guard bytes == Array("!1MVLQSTN\r".utf8) else { return true }
                queries += 1
                onLine?("!1MVL28")
                Task { @MainActor [weak self] in self?.onClose?() }
                return true
            }

            func close() {}
        }

        let clock = ManualReceiverClock()
        var made: [AnswerThenClose] = []
        let receiver = ReceiverController(clock: clock, makeTransport: { _, _ in
            let transport = AnswerThenClose()
            made.append(transport)
            return transport
        })
        let seconds = { Double(clock.now.components.seconds) + Double(clock.now.components.attoseconds) / 1e18 }
        let controller = VolumeController(mode: { .auto }, isLauncherActive: { false }, applyAppVolume: { _ in },
                                          receiver: receiver, soundSourceRunning: { false }, systemSettable: { false },
                                          now: seconds, sleep: { await clock.sleep(for: .seconds($0)) })
        receiver.onLinkUp = { [weak controller] in controller?.receiverLinkUp() }
        receiver.configure(brand: .onkyo, link: .network(host: "192.168.1.20", port: nil))

        for _ in 0..<31 { await clock.advance(by: .seconds(10)) }   // 310 s
        #expect(receiver.closedForIdle)
        #expect(!receiver.isConnected)
        let connects = made.count
        // At most one probe per interval, and a connection per probe (plus the reconnects in between).
        #expect(made.reduce(0) { $0 + $1.queries } <= 32)
        #expect(connects <= 70)
        await clock.advance(by: .seconds(1200))
        #expect(made.count == connects)   // nothing after the idle close
        receiver.stop()
        await clock.advance(by: .seconds(1000))
    }
}

/// M7h step 9c: the routes with a receiver over HDMI-CEC and the TV's own volume, and their toasts.
struct VolumeStepNineCTests {
    private func choose(_ mode: VolumeMode, receiver: Bool = false, cec: Bool = false, tv: Bool = false,
                        setUp: Bool = false, soundSource: Bool = false, settable: Bool = false,
                        active: Bool = false) -> VolumeRoute {
        VolumeRoute.choose(mode: mode, receiverReady: receiver, cecReceiverReady: cec, tvReady: tv,
                           receiverSetUp: setUp, soundSourceRunning: soundSource, systemSettable: settable,
                           launcherActive: active)
    }

    /// Coordinator decision (security L2): the TV only when no receiver is set up at all. A set-up receiver that
    /// isn't answering falls to keys, system or app, never the TV, in every mode.
    @Test func theTVOnlyWithoutASetUpReceiver() {
        #expect(choose(.auto, tv: true, setUp: true, soundSource: true, settable: true, active: true) == .keys)
        #expect(choose(.auto, tv: true, setUp: true, settable: true, active: true) == .system)
        #expect(choose(.auto, tv: true, setUp: true, active: true) == .app)
        #expect(choose(.auto, tv: true, setUp: true) == .unavailable)
        #expect(choose(.tv, tv: true, setUp: true) == .unavailable)
        #expect(choose(.tv, receiver: true, tv: true) == .unavailable)
        #expect(choose(.tv, cec: true, tv: true) == .unavailable)
        #expect(choose(.auto, tv: true, setUp: false, active: true) == .tv)
        #expect(choose(.tv, tv: true) == .tv)
    }

    /// auto = receiver (serial/network) → receiver over HDMI-CEC → TV → SoundSource → system → app.
    @Test func autoOrder() {
        #expect(choose(.auto, receiver: true, cec: true, tv: true, soundSource: true, settable: true, active: true) == .receiver)
        #expect(choose(.auto, cec: true, tv: true, soundSource: true, settable: true, active: true) == .cecReceiver)
        #expect(choose(.auto, tv: true, soundSource: true, settable: true, active: true) == .tv)
        #expect(choose(.auto, soundSource: true, settable: true, active: true) == .keys)
        #expect(choose(.auto, cec: true) == .cecReceiver)
        #expect(choose(.auto, tv: true) == .tv)
    }

    /// `receiver` covers every connection; `tv` only the TV; the other forced modes ignore all three.
    @Test func forcedModes() {
        #expect(choose(.receiver, cec: true) == .cecReceiver)
        #expect(choose(.receiver, receiver: true, cec: true) == .receiver)
        #expect(choose(.receiver, tv: true, soundSource: true, settable: true, active: true) == .unavailable)
        #expect(choose(.tv, tv: true) == .tv)
        #expect(choose(.tv, receiver: true, cec: true, tv: true) == .unavailable)
        #expect(choose(.tv, receiver: true, cec: true, soundSource: true, settable: true, active: true) == .unavailable)
        for mode in [VolumeMode.keys, .system, .app] {
            let without = choose(mode, settable: true, active: true)
            #expect(choose(mode, receiver: true, cec: true, tv: true, settable: true, active: true) == without, "\(mode)")
        }
        #expect(VolumeMode(rawValue: "tv") == .tv)
        var settings = AppSettings()
        settings.phoneRemoteVolume = "tv"
        #expect(settings.volumeMode == .tv)
    }

    @Test func percentFeedback() {
        #expect(VolumeFeedback.percent(45, muted: false) == .level(0.45, muted: false))
        #expect(VolumeFeedback.percent(45, muted: true) == .level(0.45, muted: true))
        #expect(VolumeFeedback.percent(nil, muted: true) == .level(0, muted: true))
        #expect(VolumeFeedback.percent(nil, muted: false) == .sentKeys)
        #expect(VolumeFeedback.percent(nil, muted: nil) == .sentKeys)
        #expect(VolumeFeedback.percent(150, muted: false) == .level(1, muted: false))
    }

    /// With a level: "Volume 45 %", "Muted". Without: "Volume Up", "Volume Down", "Mute". Errors always show.
    @Test func toasts() {
        func text(_ route: VolumeRoute, _ feedback: VolumeFeedback, _ action: VolumeAction?) -> String? {
            VolumeToast.message(for: VolumeOutcome(route: route, feedback: feedback, action: action))?.text
        }
        for route in [VolumeRoute.cecReceiver, .tv] {
            #expect(text(route, .sentKeys, .up) == "Volume Up")
            #expect(text(route, .sentKeys, .down) == "Volume Down")
            #expect(text(route, .sentKeys, .mute) == "Mute")
            #expect(text(route, .sentKeys, nil) == "Volume")
            #expect(text(route, .level(0.45, muted: false), .up) == "Volume 45 %")
            #expect(text(route, .level(0.13, muted: false), .down) == "Volume 13 %")
            #expect(text(route, .level(0.45, muted: true), .mute) == "Muted")
        }
        #expect(VolumeToast.message(for: VolumeOutcome(route: .cecReceiver, feedback: .sentKeys, action: .mute))?.symbol
                == VolumeToast.mutedSymbol)
        let error = VolumeOutcome(route: .tv, feedback: .unavailable(VolumeController.tvNotAnsweringMessage))
        #expect(VolumeToast.message(for: error, enabled: false)?.text == "TV isn't answering")
        #expect(VolumeToast.message(for: VolumeOutcome(route: .cecReceiver, feedback: .sentKeys, action: .up),
                                    enabled: false) == nil)
        // The serial receiver's toasts are unchanged by an action.
        #expect(text(.receiver, .sentKeys, .up) == "Volume")
    }
}

/// A TV for the volume route: answering or not; each press steps a 0…100 level, or (HDMI-CEC-like) reports none.
final class FakeVolumeTV: VolumeTV {
    var canChangeVolume = true
    var isAnsweringForVolume = false
    /// What the next check finds.
    var answers = true
    var level: Int? = 12
    var muted = false
    var fails = false
    private(set) var checks = 0
    private(set) var presses: [VolumeAction] = []

    func checkVolumeReadiness() async {
        checks += 1
        isAnsweringForVolume = answers
    }

    func changeVolume(_ action: VolumeAction) async -> TVVolumeResult {
        presses.append(action)
        if fails {
            isAnsweringForVolume = false
            return .failed
        }
        guard var level else { return .sent }
        switch action {
        case .up: level = min(100, level + 1)
        case .down: level = max(0, level - 1)
        case .mute: muted.toggle()
        }
        self.level = level
        return .level(level, muted: muted)
    }
}

/// M7h step 9c: `VolumeController` with a receiver over HDMI-CEC (a real `CECAudioSystem` on `FakeCECLink`) and a
/// fake TV.
struct VolumeControllerStepNineCTests {
    final class Harness {
        let log = PowerLog()
        let link: FakeCECLink
        let cec: CECAudioSystem
        let tv = FakeVolumeTV()
        let receiver = ReceiverController(clock: FakeReceiverClock(), makeTransport: { _, _ in nil })
        var controller: VolumeController!
        var mode: VolumeMode = .auto
        var tvEnabled = false
        var time: TimeInterval = 0
        var appVolumes: [AppVolume] = []

        init(cecEnabled: Bool = true) {
            link = FakeCECLink(log: log)
            weak var harness: Harness?
            cec = CECAudioSystem(link: link, now: { harness?.time ?? 0 }, sleep: { harness?.time += $0 })
            controller = VolumeController(
                mode: { harness?.mode ?? .auto },
                isLauncherActive: { true },
                applyAppVolume: { harness?.appVolumes.append($0) },
                receiver: receiver,
                cecReceiver: cec,
                tv: tv,
                tvVolumeEnabled: { harness?.tvEnabled ?? false },
                soundSourceRunning: { false },
                systemSettable: { false },
                now: { harness?.time ?? 0 },
                sleep: { seconds in
                    harness?.time += seconds
                    await Task.yield()
                })
            harness = self
        }

        /// The receiver over HDMI-CEC answered "on".
        func cecReady() async {
            link.receiverStatus = .on
            cec.configure(enabled: true)
            await cec.probeTask?.value
            #expect(controller.cecReceiverReady)
            log.events = []
        }

        func perform(_ action: VolumeAction) async -> VolumeOutcome? {
            var result: VolumeOutcome?
            controller.perform(action) { result = $0 }
            await controller.receiverTask?.value
            return result
        }
    }

    @Test func aReadyCECReceiverTakesTheKeysAndPresses() async {
        let harness = Harness()
        #expect(!harness.controller.consumesVolumeKeys())
        await harness.cecReady()
        #expect(harness.controller.consumesVolumeKeys())
        let up = await harness.perform(.up)
        #expect(up == VolumeOutcome(route: .cecReceiver, feedback: .sentKeys, action: .up))
        #expect(up.flatMap(VolumeToast.message(for:))?.text == "Volume Up")
        #expect(harness.log.events == ["cec.45:44:41", "cec.45:45", "cec.query.45:71"])
        #expect(harness.appVolumes.isEmpty)
        // A receiver that reports its level: the toast shows it, and the phone gets it.
        harness.link.queryReplies["45:71"] = [0x54, 0x7A, 0x2D]
        let down = await harness.perform(.down)
        #expect(down?.feedback == .level(0.45, muted: false))
        #expect(down.flatMap(VolumeToast.message(for:))?.text == "Volume 45 %")
        harness.link.queryReplies["45:71"] = [0x54, 0x7A, 0xAD]
        #expect(await harness.perform(.mute).flatMap(VolumeToast.message(for:))?.text == "Muted")
    }

    /// Step 10's queue rules: at most one waiting step (the latest), Mute never dropped; every press answered once.
    @Test func heldRepeatsCoalesceOnTheCECReceiver() async {
        let harness = Harness()
        await harness.cecReady()
        var answers = Array(repeating: 0, count: 7)
        for index in 0..<5 { harness.controller.perform(.up) { _ in answers[index] += 1 } }
        harness.controller.perform(.mute) { _ in answers[5] += 1 }
        harness.controller.perform(.down) { _ in answers[6] += 1 }
        #expect(harness.controller.waitingCount == 2)
        await harness.controller.receiverTask?.value
        let pressed = harness.log.events.filter { $0.hasPrefix("cec.45:44:") }
        // The step slot was filled first, so the latest step (Down) runs before the Mute.
        #expect(pressed == ["cec.45:44:41", "cec.45:44:42", "cec.45:44:43"])
        #expect(answers == Array(repeating: 1, count: 7))
        #expect(!harness.controller.isReceiverBusy)
    }

    @Test func aCECReceiverThatStopsAnsweringFallsBackAndIsAskedAgain() async {
        let harness = Harness()
        await harness.cecReady()
        harness.link.sendResults["45:44:41"] = .notAcknowledged
        #expect(await harness.perform(.up)?.feedback == .unavailable(VolumeController.notAnsweringMessage))
        #expect(!harness.controller.cecReceiverReady)
        // The next press takes MMTVL's own volume, and asks the receiver again (10 s after the last check).
        harness.time = VolumeController.probeInterval
        harness.link.sendResults = [:]
        #expect(await harness.perform(.down)?.route == .app)
        await harness.cec.probeTask?.value
        #expect(harness.controller.cecReceiverReady)
        #expect(await harness.perform(.up)?.route == .cecReceiver)
    }

    /// The dev Mac: the tunnel isn't available, so the launch probe finds nothing and presses take the next route.
    @Test func notAvailableFallsThrough() async {
        let harness = Harness()
        harness.link.availabilities = [.notAvailable]
        harness.cec.configure(enabled: true)
        await harness.cec.probeTask?.value
        #expect(!harness.controller.consumesVolumeKeys())
        #expect(await harness.perform(.up)?.route == .app)
        #expect(!harness.log.events.contains { $0.hasPrefix("cec.45:44") })
    }

    // MARK: TV volume (tvVolumeEnabled)

    @Test func tvVolumeOffNeverUsesTheTV() async {
        let harness = Harness()
        harness.tv.isAnsweringForVolume = true
        #expect(!harness.controller.consumesVolumeKeys())
        #expect(await harness.perform(.up)?.route == .app)
        #expect(harness.tv.presses.isEmpty)
        #expect(harness.tv.checks == 0)
        harness.mode = .tv
        #expect(await harness.perform(.up)?.feedback == .unavailable(VolumeController.tvNotAnsweringMessage))
    }

    @Test func tvVolumeOnGoesToAnAnsweringTV() async {
        let harness = Harness()
        harness.tvEnabled = true
        // Not checked yet: the press falls back and asks the TV.
        #expect(await harness.perform(.up)?.route == .app)
        await harness.controller.tvProbeTask?.value
        #expect(harness.tv.checks == 1)
        #expect(harness.controller.consumesVolumeKeys())
        let up = await harness.perform(.up)
        #expect(up == VolumeOutcome(route: .tv, feedback: .level(0.13, muted: false), action: .up))
        #expect(up.flatMap(VolumeToast.message(for:))?.text == "Volume 13 %")
        #expect(await harness.perform(.mute).flatMap(VolumeToast.message(for:))?.text == "Muted")
        // An HDMI-CEC TV (no level): "Volume Down".
        harness.tv.level = nil
        #expect(await harness.perform(.down).flatMap(VolumeToast.message(for:))?.text == "Volume Down")
        #expect(harness.tv.presses == [.up, .mute, .down])
    }

    @Test func aReadyReceiverWinsOverTheTV() async {
        let harness = Harness()
        harness.tvEnabled = true
        harness.tv.isAnsweringForVolume = true
        await harness.cecReady()
        #expect(await harness.perform(.up)?.route == .cecReceiver)
        #expect(harness.tv.presses.isEmpty)
        // Security L2: not even a forced `tv` mode uses the TV while a receiver is set up.
        harness.mode = .tv
        #expect(await harness.perform(.up)?.feedback == .unavailable(VolumeController.tvNotAnsweringMessage))
        #expect(harness.tv.presses.isEmpty)
    }

    /// Build 25 security L2: a network receiver with a brand but no usable address (its controller gets brand `none`,
    /// as `AppDelegate.configureReceiver` does) still counts as set up, so the TV never gets the volume buttons and
    /// the receiver's Maximum Volume can't be bypassed. With no receiver in the settings, the same TV takes them.
    @Test func aNetworkReceiverWithoutAnAddressStillKeepsTheTVOff() async {
        var settings = AppSettings()
        settings.receiverBrand = .pioneer
        settings.receiverConnection = .network
        settings.receiverHost = nil
        settings.tvVolumeEnabled = true
        #expect(settings.receiverIsSetUp)
        let tv = FakeVolumeTV()
        tv.isAnsweringForVolume = true
        let receiver = ReceiverController(clock: FakeReceiverClock(), makeTransport: { _, _ in nil })
        receiver.configure(brand: .none, link: .serial(path: nil))
        func controller(_ settings: AppSettings) -> VolumeController {
            VolumeController(mode: { .auto }, isLauncherActive: { true }, applyAppVolume: { _ in },
                             receiver: receiver, tv: tv, tvVolumeEnabled: { settings.tvVolumeEnabled },
                             receiverConfigured: { settings.receiverIsSetUp },
                             soundSourceRunning: { false }, systemSettable: { false })
        }
        let setUp = controller(settings)
        #expect(setUp.tvReady)
        #expect(setUp.receiverSetUp)
        #expect(!setUp.consumesVolumeKeys())
        var route: VolumeRoute?
        setUp.perform(.up) { route = $0.route }
        #expect(route != nil && route != .tv)
        #expect(tv.presses.isEmpty)
        // HDMI-CEC with no brand counts too.
        var overCEC = AppSettings()
        overCEC.receiverConnection = .cec
        #expect(overCEC.receiverIsSetUp)
        // No receiver at all: the TV takes the buttons.
        var none = settings
        none.receiverBrand = .none
        #expect(!none.receiverIsSetUp)
        let noReceiver = controller(none)
        #expect(!noReceiver.receiverSetUp)
        #expect(noReceiver.consumesVolumeKeys())
    }

    /// Security L2 and QA major: a set-up CEC receiver that isn't answering sends presses to MMTVL's own volume, never
    /// to the TV; each such press still asks the receiver (at most every 10 s), and once it answers the next press
    /// goes to it.
    @Test func aSetUpReceiverThatIsntAnsweringFallsBackAndIsAskedAgain() async {
        let harness = Harness()
        harness.tvEnabled = true
        harness.tv.isAnsweringForVolume = true
        harness.link.receiverStatus = nil
        harness.cec.configure(enabled: true)
        await harness.cec.probeTask?.value
        #expect(!harness.controller.cecReceiverReady)
        #expect(harness.controller.receiverSetUp)
        #expect(!harness.controller.consumesVolumeKeys())
        #expect(await harness.perform(.up)?.route == .app)
        #expect(harness.tv.presses.isEmpty)
        #expect(harness.tv.checks == 0)
        // It answers now; within the interval a press doesn't ask.
        harness.link.receiverStatus = .on
        harness.time = 5
        #expect(await harness.perform(.up)?.route == .app)
        #expect(harness.cec.probeTask == nil)
        #expect(harness.log.events.filter { $0 == "cec.status.receiver" }.count == 1)
        // After the interval, the fallback press asks; the next press goes to the receiver.
        harness.time = VolumeController.probeInterval
        #expect(await harness.perform(.up)?.route == .app)
        await harness.cec.probeTask?.value
        #expect(harness.log.events.filter { $0 == "cec.status.receiver" }.count == 2)
        #expect(harness.controller.cecReceiverReady)
        #expect(await harness.perform(.up)?.route == .cecReceiver)
        #expect(harness.tv.presses.isEmpty)
    }

    @Test func aTVThatFailsFallsBackAndIsCheckedAtMostEveryInterval() async {
        let harness = Harness()
        harness.tvEnabled = true
        harness.tv.isAnsweringForVolume = true
        harness.tv.fails = true
        #expect(await harness.perform(.up)?.feedback == .unavailable(VolumeController.tvNotAnsweringMessage))
        harness.tv.fails = false
        harness.tv.answers = false
        #expect(await harness.perform(.up)?.route == .app)
        await harness.controller.tvProbeTask?.value
        #expect(harness.tv.checks == 1)
        harness.time = 5
        _ = await harness.perform(.up)
        #expect(harness.controller.tvProbeTask == nil)
        #expect(harness.tv.checks == 1)
        harness.time = VolumeController.probeInterval
        harness.tv.answers = true
        _ = await harness.perform(.up)
        await harness.controller.tvProbeTask?.value
        #expect(harness.tv.checks == 2)
        #expect(await harness.perform(.up)?.route == .tv)
    }

    /// Turning TV volume on asks the TV at once, even within the interval.
    @Test func turningTVVolumeOnChecksAtOnce() async {
        let harness = Harness()
        harness.tvEnabled = true
        harness.controller.probeReceiverIfNeeded()
        await harness.controller.tvProbeTask?.value
        #expect(harness.tv.checks == 1)
        harness.tv.isAnsweringForVolume = false
        harness.controller.tvSettingsChanged()
        await harness.controller.tvProbeTask?.value
        #expect(harness.tv.checks == 2)
        harness.tvEnabled = false
        harness.tv.isAnsweringForVolume = false
        harness.controller.tvSettingsChanged()
        #expect(harness.controller.tvProbeTask == nil)
    }
}
