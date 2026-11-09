import Foundation
import Testing
@testable import MMTVL

/// M7h step 9c: the receiver over HDMI-CEC on a fake tunnel (`FakeCECLink`). Nothing here touches IOKit.
struct CECAudioSystemTests {
    let log = PowerLog()
    let link: FakeCECLink

    init() {
        link = FakeCECLink(log: log)
    }

    final class Clock {
        var time: TimeInterval = 0
    }

    private func make(_ clock: Clock = Clock()) -> CECAudioSystem {
        CECAudioSystem(link: link, now: { clock.time }, sleep: { clock.time += $0 })
    }

    private static let name: [UInt8] = [0x54, 0x47] + Array("VSX-01TXH".utf8)

    /// Configured over HDMI-CEC; the configure-time probe has finished.
    private func ready(_ clock: Clock = Clock()) async -> CECAudioSystem {
        link.receiverStatus = .on
        link.queryReplies["45:46"] = Self.name
        let system = make(clock)
        system.configure(enabled: true)
        await system.probeTask?.value
        log.events = []
        return system
    }

    // MARK: Ready, standby, no answer

    @Test func readyWhenItAnswersOnAndNamedOnce() async {
        let system = await ready()
        #expect(system.isAnswering)
        #expect(system.power == .on)
        #expect(system.name == "VSX-01TXH")
        #expect(system.availability == .ready)
        // Ready: no more probes, and the name isn't asked again.
        system.probeIfNeeded()
        #expect(system.probeTask == nil)
        #expect(log.events.isEmpty)
    }

    @Test func configureProbesPowerStatusThenTheName() async {
        link.receiverStatus = .standbyToOn
        link.queryReplies["45:46"] = Self.name
        let system = make()
        system.configure(enabled: true)
        await system.probeTask?.value
        #expect(log.events == ["cec.status.receiver", "cec.query.45:46"])
        #expect(system.isAnswering)   // 2 (standby → on) counts as on
    }

    @Test func standbyOrNoAnswerIsNotReady() async {
        for status in [CECPowerStatus.standby, .onToStandby] {
            link.receiverStatus = status
            let system = make()
            system.configure(enabled: true)
            await system.probeTask?.value
            #expect(!system.isAnswering, "\(status)")
            #expect(system.power == status)
        }
        link.receiverStatus = nil
        log.events = []
        let system = make()
        system.configure(enabled: true)
        await system.probeTask?.value
        #expect(!system.isAnswering)
        #expect(system.power == nil)
        // No answer: the name isn't asked.
        #expect(log.events == ["cec.status.receiver"])
    }

    @Test func probesAtMostEveryTenSeconds() async {
        let clock = Clock()
        link.receiverStatus = nil
        let system = make(clock)
        system.configure(enabled: true)
        await system.probeTask?.value
        clock.time = 9.9
        system.probeIfNeeded()
        #expect(system.probeTask == nil)
        #expect(log.events == ["cec.status.receiver"])
        clock.time = 10
        link.receiverStatus = .on
        system.probeIfNeeded()
        await system.probeTask?.value
        #expect(system.isAnswering)
        #expect(log.events.filter { $0 == "cec.status.receiver" }.count == 2)
    }

    @Test func notEnabledSendsNothing() async {
        let system = make()
        system.configure(enabled: false)
        system.probeIfNeeded()
        #expect(system.probeTask == nil)
        #expect(await system.press(.up) == .notSent)
        #expect(await !system.powerOff())
        #expect(await !system.powerOn())
        system.noteDisplayChange()
        await Task.yield()
        #expect(log.events.isEmpty)
    }

    /// After a hot-plug, a receiver that isn't answering is asked again once the tunnel reads ready.
    @Test func aHotPlugThatLeavesTheTunnelReadyProbesAgain() async throws {
        let clock = Clock()
        link.receiverStatus = nil
        let system = make(clock)
        system.configure(enabled: true)
        await system.probeTask?.value
        link.receiverStatus = .on
        clock.time = 30
        system.noteDisplayChange()
        for _ in 0..<20 where system.probeTask == nil { await Task.yield() }
        await system.probeTask?.value
        #expect(system.isAnswering)
        // Not ready (no display): nothing sent.
        link.availabilities = [.noDisplay]
        link.resetChecks()
        link.receiverStatus = nil
        system.configure(enabled: true)
        await system.probeTask?.value
        let before = log.events.count
        clock.time = 60
        system.noteDisplayChange()
        for _ in 0..<20 { await Task.yield() }
        #expect(system.probeTask == nil)
        #expect(log.events.count == before)
        #expect(system.availability == .noDisplay)
    }

    // MARK: Presses

    @Test func pressIsPressedThenReleasedThenGiveAudioStatus() async {
        let system = await ready()
        link.queryReplies["45:71"] = [0x54, 0x7A, 0x2D]
        #expect(await system.press(.up) == .sent(CECAudioStatus(muted: false, volume: 45)))
        #expect(log.events == ["cec.45:44:41", "cec.45:45", "cec.query.45:71"])
        #expect(link.queryTimeouts.last == .milliseconds(300))
        log.events = []
        link.queryReplies["45:71"] = [0x5F, 0x7A, 0xAC]   // broadcast, muted
        #expect(await system.press(.mute) == .sent(CECAudioStatus(muted: true, volume: 44)))
        #expect(log.events == ["cec.45:44:43", "cec.45:45", "cec.query.45:71"])
        log.events = []
        #expect(await system.press(.down) == .sent(CECAudioStatus(muted: true, volume: 44)))
        #expect(log.events.first == "cec.45:44:42")
    }

    /// The Pioneer case: after 3 presses in a row without a Report Audio Status, it isn't asked again until the
    /// next configure.
    @Test func stopsAskingForTheLevelAfterThreeUnansweredPresses() async {
        let system = await ready()
        for _ in 0..<3 { #expect(await system.press(.up) == .sent(nil)) }
        #expect(log.events.filter { $0 == "cec.query.45:71" }.count == 3)
        #expect(!system.asksAudioStatus)
        log.events = []
        #expect(await system.press(.down) == .sent(nil))
        #expect(log.events == ["cec.45:44:42", "cec.45:45"])
        system.configure(enabled: true)
        #expect(system.asksAudioStatus)
    }

    @Test func anAnswerResetsTheCount() async {
        let system = await ready()
        for _ in 0..<2 { _ = await system.press(.up) }
        link.queryReplies["45:71"] = [0x54, 0x7A, 0x10]
        _ = await system.press(.up)
        link.queryReplies["45:71"] = nil
        for _ in 0..<2 { _ = await system.press(.up) }
        #expect(system.asksAudioStatus)
    }

    @Test func aPressNotAcknowledgedMakesItNotReady() async {
        let system = await ready()
        link.sendResults["45:44:41"] = .notAcknowledged
        #expect(await system.press(.up) == .notSent)
        #expect(!system.isAnswering)
        // Security M1: the Pressed may have gone out, so Released follows; Give Audio Status doesn't.
        #expect(log.events == ["cec.45:44:41", "cec.45:45"])
    }

    @Test func busyOrUnavailable() async {
        let system = await ready()
        // corercd's send in progress: this press is lost, but the receiver stays ready.
        link.sendResults["45:44:41"] = .busy
        #expect(await system.press(.up) == .notSent)
        #expect(system.isAnswering)
        #expect(log.events == ["cec.45:44:41"])   // nothing was written: no Released
        // Build 25 security L1: corercd started a send while our Pressed was in the TX buffer. It may go out with
        // that send, so Released follows; the receiver stays ready.
        log.events = []
        link.sendResults["45:44:41"] = .collided
        #expect(await system.press(.up) == .notSent)
        #expect(system.isAnswering)
        #expect(log.events == ["cec.45:44:41", "cec.45:45"])
        // The dev Mac: the tunnel isn't available, so nothing goes out and it isn't ready.
        link.sendResults["45:44:41"] = .unavailable(.notAvailable)
        #expect(await system.press(.up) == .notSent)
        #expect(!system.isAnswering)
    }

    // MARK: Power and Test

    @Test func powerOffIsStandbyAndOnIsPowerOnFunction() async {
        let system = await ready()
        #expect(await system.powerOff())
        #expect(await system.powerOn())
        #expect(log.events == ["cec.45:36", "cec.45:44:6D", "cec.45:45"])
        log.events = []
        link.sendResults["45:44:6D"] = .notAcknowledged
        #expect(await !system.powerOn())
        // Security M1: released even so.
        #expect(log.events == ["cec.45:44:6D", "cec.45:45"])
    }

    @Test func testAsksPowerStatusThenTheName() async {
        let system = make()
        link.receiverStatus = .on
        link.queryReplies["45:46"] = Self.name
        let on = await system.test()
        #expect(on == CECReceiverTest(power: .on, name: "VSX-01TXH"))
        #expect(on.line == "On · VSX-01TXH")
        #expect(log.events == ["cec.status.receiver", "cec.query.45:46"])
        // Not set up over HDMI-CEC (Find Receiver): the answers aren't kept.
        #expect(!system.isAnswering)
        #expect(system.name == nil)

        link.receiverStatus = .standby
        #expect(await system.test().line == "Standby · VSX-01TXH")
        link.queryReplies["45:46"] = nil
        #expect(await system.test().line == "Standby")
        link.receiverStatus = nil
        log.events = []
        let none = await system.test()
        #expect(none.line == "No answer")
        #expect(!none.answered)
        #expect(log.events == ["cec.status.receiver"])
    }

    @Test func testUpdatesAReceiverSetUpOverCEC() async {
        link.receiverStatus = nil
        let system = make()
        system.configure(enabled: true)
        await system.probeTask?.value
        #expect(!system.isAnswering)
        link.receiverStatus = .on
        link.queryReplies["45:46"] = Self.name
        _ = await system.test()
        #expect(system.isAnswering)
        #expect(system.name == "VSX-01TXH")
    }

    @Test func powerReceiverConformance() async {
        let system = await ready()
        #expect(system.isSetUp)
        #expect(await system.send(.powerOff))
        #expect(await !system.send(.volumeUp))
        #expect(await !system.send(.queryPower))
        #expect(log.events == ["cec.45:36"])
        system.configure(enabled: false)
        #expect(!system.isSetUp)
    }

    // MARK: Review fixes

    /// Security M1: Released follows every Pressed that may have gone out (sent, not acknowledged, timed out, or
    /// written while another send started: `.collided`, build 25 security L1), not one that never left (`.busy`:
    /// another send in progress before anything was written; tunnel unavailable; failed).
    @Test func releasedFollowsAnyPressedThatMayHaveGoneOut() async {
        for (result, released) in [(CECSendResult.timedOut, true), (.notAcknowledged, true), (.sent, true),
                                   (.collided, true),
                                   (.busy, false), (.unavailable(.notAvailable), false), (.failed, false)] {
            log.events = []
            let system = await ready()
            link.sendResults["45:44:42"] = result
            _ = await system.press(.down)
            #expect(log.events.contains("cec.45:45") == released, "\(result)")
            #expect(log.events.first == "cec.45:44:42")
        }
    }

    /// Security M1: a Released that isn't sent is tried once more, 100 ms later (press and power-on).
    @Test func aReleasedThatIsntSentIsRetriedOnce() async {
        let clock = Clock()
        let system = await ready(clock)
        link.sendSequences["45:45"] = [.busy]
        _ = await system.press(.up)
        #expect(log.events.prefix(3) == ["cec.45:44:41", "cec.45:45", "cec.45:45"])
        #expect(clock.time == CECAudioSystem.releaseRetryDelay)
        // Twice not sent: only one retry.
        log.events = []
        link.sendSequences["45:45"] = [.busy, .timedOut, .sent]
        link.sendResults["45:44:6D"] = .timedOut
        #expect(await !system.powerOn())
        #expect(log.events == ["cec.45:44:6D", "cec.45:45", "cec.45:45"])
    }

    /// Security L1: while ready, a press re-checks the power status (after the press) once the last answer is older
    /// than 60 s; a standby answer makes it not ready.
    @Test func aStaleReadyReceiverIsCheckedAfterAPress() async {
        let clock = Clock()
        let system = await ready(clock)
        clock.time = 59
        _ = await system.press(.up)
        #expect(system.probeTask == nil)
        #expect(!log.events.contains("cec.status.receiver"))
        clock.time = 61
        link.receiverStatus = .standby
        log.events = []
        #expect(await system.press(.up) == .sent(nil))
        await system.probeTask?.value
        // After the press's own frames.
        #expect(log.events == ["cec.45:44:41", "cec.45:45", "cec.query.45:71", "cec.status.receiver"])
        #expect(!system.isAnswering)
        #expect(system.power == .standby)
    }

    /// QA minor: a check on its way when MMTVL turns the receiver off can't make it ready with a late "on".
    @Test func aLateOnAnswerAfterTurnedOffIsIgnored() async {
        let clock = Clock()
        link.receiverStatus = nil
        let system = make(clock)
        system.configure(enabled: true)
        await system.probeTask?.value
        link.receiverStatus = .on
        clock.time = 10
        system.probeIfNeeded()
        let inFlight = system.probeTask
        #expect(inFlight != nil)
        system.noteTurnedOff()
        #expect(system.probeTask == nil)
        await inFlight?.value
        #expect(!system.isAnswering)
        #expect(system.power == .standby)
    }
}

/// Step 9c review fixes on the TV over HDMI-CEC: Released, the stale re-check and the power-off.
struct HDMICECVolumeTests {
    let log = PowerLog()
    let clock = FakeReceiverClock()

    private func tv(_ link: FakeCECLink) async -> HDMICEC {
        let tv = HDMICEC(link: link, clock: clock, physicalAddress: { nil })
        tv.configure(brand: .cec)
        link.status = .on
        _ = await tv.powerStatus()
        log.events = []
        return tv
    }

    /// Security M1, the TV's call site (`.collided`: build 25 security L1).
    @Test func releasedFollowsAnyPressedThatMayHaveGoneOut() async {
        for (result, released) in [(CECSendResult.timedOut, true), (.notAcknowledged, true), (.sent, true),
                                   (.collided, true),
                                   (.busy, false), (.unavailable(.notAvailable), false)] {
            let link = FakeCECLink(log: log)
            let tv = await tv(link)
            link.sendResults["40:44:41"] = result
            #expect(await tv.sendVolumeKey(.volumeUp) == (result == .sent), "\(result)")
            #expect(log.events == (released ? ["cec.40:44:41", "cec.40:45"] : ["cec.40:44:41"]), "\(result)")
        }
    }

    @Test func aReleasedThatIsntSentIsRetriedOnce() async {
        let link = FakeCECLink(log: log)
        let tv = await tv(link)
        link.sendSequences["40:45"] = [.busy]
        let start = clock.now
        #expect(await tv.sendVolumeKey(.mute))
        #expect(log.events == ["cec.40:44:43", "cec.40:45", "cec.40:45"])
        #expect(clock.now - start == HDMICEC.releaseRetryDelay)
    }

    /// Security L1, the TV: after 60 s, a press re-checks the power status; standby → not ready for volume.
    @Test func aStaleReadyTVIsCheckedAfterAPress() async {
        let link = FakeCECLink(log: log)
        let tv = await tv(link)
        #expect(tv.isAnsweringForVolume)
        clock.now += .seconds(59)
        #expect(await tv.sendVolumeKey(.volumeUp))
        #expect(tv.recheckTask == nil)
        clock.now += .seconds(2)
        link.status = .standby
        log.events = []
        #expect(await tv.sendVolumeKey(.volumeUp))
        await tv.recheckTask?.value
        #expect(log.events == ["cec.40:44:41", "cec.40:45", "cec.status"])
        #expect(!tv.isAnsweringForVolume)
    }

    /// QA minor: MMTVL's CEC power-off forgets the "on" answer, so TV volume isn't ready until the TV answers again.
    @Test func powerOffClearsTheTVsReadiness() async {
        let link = FakeCECLink(log: log)
        let tv = await tv(link)
        let volume = VolumeController(mode: { .auto }, isLauncherActive: { true }, applyAppVolume: { _ in }, tv: tv,
                                      tvVolumeEnabled: { true }, soundSourceRunning: { false },
                                      systemSettable: { false }, now: { 0 })
        #expect(volume.consumesVolumeKeys())
        #expect(await tv.powerOff())
        #expect(!tv.isAnsweringForVolume)
        log.events = []
        var outcome: VolumeOutcome?
        volume.perform(.up) { outcome = $0 }
        await volume.receiverTask?.value
        #expect(outcome?.route == .app)
        #expect(!log.events.contains("cec.40:44:41"))
    }
}
