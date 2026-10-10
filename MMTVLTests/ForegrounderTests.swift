import Foundation
import Testing
@testable import MMTVL

/// A fake system: each rung may or may not make MMTVL frontmost.
final class ForegroundRecorder {
    let selfPID: pid_t = 100
    var frontPID: pid_t? = 200
    var tried: [Foregrounder.Rung] = []
    /// The rung that makes MMTVL frontmost; nil = none works.
    var workingRung: Foregrounder.Rung?

    func make(windowed: Bool = false, sleep: @escaping (Duration) async -> Void = { _ in }) -> Foregrounder {
        Foregrounder(
            windowed: windowed,
            selfPID: selfPID,
            frontmostPID: { self.frontPID },
            frontmostBundleID: { "tv.plex.htpc" },
            activate: { self.record(.activate) },
            axFrontmost: { self.record(.axFrontmost); return true },
            hideFrontApp: { self.record(.hideFrontApp); return true },
            sleep: sleep
        )
    }

    private func record(_ rung: Foregrounder.Rung) {
        tried.append(rung)
        if rung == workingRung { frontPID = selfPID }
    }
}

struct ForegrounderTests {
    @Test func stopsAtTheFirstRungThatWorks() async {
        let recorder = ForegroundRecorder()
        recorder.workingRung = .axFrontmost
        let succeeded = await recorder.make().bringForward(reason: "test")
        #expect(succeeded)
        #expect(recorder.tried == [.activate, .axFrontmost])
    }

    @Test func activateAloneIsEnough() async {
        let recorder = ForegroundRecorder()
        recorder.workingRung = .activate
        #expect(await recorder.make().bringForward(reason: "test"))
        #expect(recorder.tried == [.activate])
    }

    @Test func triesEveryRungAndFails() async {
        let recorder = ForegroundRecorder()
        let succeeded = await recorder.make().bringForward(reason: "test")
        #expect(!succeeded)
        #expect(recorder.tried == [.activate, .axFrontmost, .hideFrontApp])
    }

    @Test func windowedNeverHides() async {
        let recorder = ForegroundRecorder()
        let succeeded = await recorder.make(windowed: true).bringForward(reason: "test")
        #expect(!succeeded)
        #expect(recorder.tried == [.activate])
    }

    @Test func aNewerCallCancelsTheOlder() async {
        let recorder = ForegroundRecorder()
        var foregrounder: Foregrounder!
        var nested: Task<Bool, Never>?
        var firstSleep = true
        foregrounder = recorder.make(sleep: { _ in
            // The second call starts while the first waits after its first rung.
            if firstSleep {
                firstSleep = false
                recorder.workingRung = .activate
                nested = Task { await foregrounder.bringForward(reason: "second") }
                _ = await nested?.value
            }
        })
        let first = await foregrounder.bringForward(reason: "first")
        #expect(!first)
        #expect(await nested?.value == true)
        #expect(recorder.tried == [.activate, .activate])
    }
}
