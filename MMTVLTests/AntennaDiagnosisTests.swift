import Foundation
import Testing
@testable import MMTVL

/// M7j L9: why an antenna stream failed, from the tuner's `status.json` and `lineup_status.json` (fake tuner).
struct AntennaDiagnosisTests {
    private func diagnose(status: String?, lineupStatus: String? = AntennaFixtures.lineupStatusJSON(scanning: false),
                          httpStatus: Int?) async -> AntennaProblem {
        let tuner = FakeTuner()
        tuner.setStatus(status)
        tuner.setLineupStatus(lineupStatus)
        let http = HDHomeRunHTTP(fetch: { url, _, _ in tuner.fetch(url) })
        return await AntennaDiagnosis.diagnose(device: AntennaFixtures.device(), httpStatus: httpStatus, http: http)
    }

    @Test func allBusyIsTunersInUse() async {
        let problem = await diagnose(status: AntennaFixtures.statusJSON(busy: 2), httpStatus: 503)
        #expect(problem == .allTunersInUse(2))
        #expect(problem.message == "Both antenna tuners are in use")
        // Busy wins over a 404 and a scan: the tuners' own state decides first.
        #expect(await diagnose(status: AntennaFixtures.statusJSON(busy: 2),
                               lineupStatus: AntennaFixtures.lineupStatusJSON(scanning: true),
                               httpStatus: 404) == .allTunersInUse(2))
    }

    @Test func scanIsScanning() async {
        let problem = await diagnose(status: AntennaFixtures.statusJSON(busy: 0),
                                     lineupStatus: AntennaFixtures.lineupStatusJSON(scanning: true), httpStatus: 503)
        #expect(problem == .scanning)
        #expect(problem.message == "The tuner is scanning for channels")
    }

    @Test func notFoundIsUnknownChannel() async {
        let problem = await diagnose(status: AntennaFixtures.statusJSON(busy: 1), httpStatus: 404)
        #expect(problem == .unknownChannel)
        #expect(problem.message == "This channel is no longer on the tuner")
    }

    @Test func freeTunerAnd503IsNoSignal() async {
        let problem = await diagnose(status: AntennaFixtures.statusJSON(busy: 1), httpStatus: 503)
        #expect(problem == .noSignal)
        #expect(problem.message == "No signal on this channel")
        // No status logged: the same, with a free tuner. An unanswered lineup_status.json isn't a scan.
        #expect(await diagnose(status: AntennaFixtures.statusJSON(busy: 0), httpStatus: nil) == .noSignal)
        #expect(await diagnose(status: AntennaFixtures.statusJSON(busy: 0), lineupStatus: nil,
                               httpStatus: 503) == .noSignal)
    }

    @Test func otherStatusIsUnknown() async {
        let problem = await diagnose(status: AntennaFixtures.statusJSON(busy: 0), httpStatus: 500)
        #expect(problem == .unknown)
        #expect(problem.message == "Can't play this channel")
    }

    @Test func unreachableStatusIsUnreachable() async {
        let problem = await diagnose(status: nil, httpStatus: 503)
        #expect(problem == .unreachable)
        #expect(problem.message == "The antenna tuner isn't answering")
        // A body that isn't status.json counts as no answer.
        #expect(await diagnose(status: "<html>", httpStatus: nil) == .unreachable)
    }

    @Test func busyMessageSaysBothForTwo() {
        #expect(AntennaDiagnosis.busyMessage(tunerCount: 2) == "Both antenna tuners are in use")
        #expect(AntennaDiagnosis.busyMessage(tunerCount: 4) == "All 4 antenna tuners are in use")
        #expect(AntennaDiagnosis.busyMessage(tunerCount: 1) == "The antenna tuner is in use")
        #expect(AntennaProblem.allTunersInUse(3).message == "All 3 antenna tuners are in use")
    }

    /// L15: the log text never names the tuner.
    @Test func logTextHasNoAddress() {
        let problems: [AntennaProblem] = [.allTunersInUse(2), .scanning, .noSignal, .unknownChannel, .unreachable,
                                          .unknown]
        for problem in problems {
            #expect(!problem.logText.contains(AntennaFixtures.host))
            #expect(!problem.logText.contains(AntennaFixtures.deviceID))
        }
    }
}
