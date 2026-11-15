import Foundation

/// M7j L8, L9: why an antenna channel isn't playing, as Live TV says it (full screen, or a Multiview window's text).
nonisolated enum AntennaProblem: Equatable, Sendable {
    /// Every tuner of the device is busy (the count is the device's `TunerCount`).
    case allTunersInUse(Int)
    case scanning
    case noSignal
    case unknownChannel
    case unreachable
    case unknown

    var message: String {
        switch self {
        case .allTunersInUse(let count): AntennaDiagnosis.busyMessage(tunerCount: count)
        case .scanning: "The tuner is scanning for channels"
        case .noSignal: "No signal on this channel"
        case .unknownChannel: "This channel is no longer on the tuner"
        case .unreachable: AntennaSource.unreachableMessage
        case .unknown: LiveTVModel.playbackErrorMessage
        }
    }

    /// For the log (category `Antenna`, L15): never an address, DeviceID or URL.
    var logText: String {
        switch self {
        case .allTunersInUse(let count): "all \(count) tuners in use"
        case .scanning: "the tuner is scanning"
        case .noSignal: "no signal"
        case .unknownChannel: "not on the tuner"
        case .unreachable: "the tuner isn't answering"
        case .unknown: "unknown"
        }
    }
}

/// M7j L9: asks the tuner why a stream failed, without taking a tuner (`status.json`, `lineup_status.json`).
nonisolated enum AntennaDiagnosis {
    /// What Live TV does after an antenna stream failed (`IPTVLibrary.diagnose`).
    enum Outcome: Equatable, Sendable {
        /// The tuners were searched for or the lineup read again, and the channel is still there: play it once more.
        case retry(Channel)
        case show(AntennaProblem)
    }

    /// L9: "Both antenna tuners are in use" for two; "All N antenna tuners are in use" for more; one tuner says so.
    static func busyMessage(tunerCount: Int) -> String {
        switch tunerCount {
        case 2: "Both antenna tuners are in use"
        case ...1: "The antenna tuner is in use"
        default: "All \(tunerCount) antenna tuners are in use"
        }
    }

    /// L9 (a)–(d) on one device, in that order: every tuner busy → `.allTunersInUse`; `status.json` unanswered →
    /// `.unreachable`; a scan running → `.scanning`; `httpStatus` 404 → `.unknownChannel`; 503 or none (with a free
    /// tuner) → `.noSignal`; anything else → `.unknown`. The caller decides on a retry (`.unreachable`,
    /// `.unknownChannel`).
    ///
    /// `httpStatus` may be stale (step 5's QA: a late mpv log line from a replaced load can land on the next one),
    /// so it never decides first: the tuners' own state does. A stale 503 can only turn into "No signal" with a
    /// free tuner, which is also what no status says; a stale 404 only costs a lineup read and one more try.
    static func diagnose(device: HDHomeRunDevice, httpStatus: Int?, http: HDHomeRunHTTP) async -> AntennaProblem {
        guard let tuners = await http.tunerStatus(of: device) else { return .unreachable }
        if !tuners.isEmpty, HDHomeRunTunerStatus.busyCount(tuners) == tuners.count {
            return .allTunersInUse(device.tunerCount)
        }
        if await http.lineupStatus(of: device)?.scanInProgress == true { return .scanning }
        switch httpStatus {
        case 404: return .unknownChannel
        case nil, 503: return .noSignal
        default: return .unknown
        }
    }
}
