import Foundation
import os

// M7h step 9c: the receiver over HDMI-CEC (Settings → Audio & TV → Receiver → Connection → HDMI-CEC), logical
// address 5 (the audio system), through the tunnel `HDMICEC` uses (one serial queue for every frame). Step 14b's
// probe 2 on the Pioneer: Volume Up/Down/Mute as User Control Pressed `45:44:41/42/43` + Released `45:45` step it one
// notch or toggle mute; Give Device Power Status `45:8F` → `54:90:<s>` and Give OSD Name `45:46` → `54:47:<name>`
// detect and name it; Give Audio Status `45:71` gets no answer from the Pioneer, but other brands report
// `5F:7A`/`54:7A`, so it's asked after each press until 3 presses in a row go unanswered. Ready (`isAnswering`) = a
// power status "on" (0 or 2) answered since `configure`; standby or no answer = not ready. It's asked at
// `configure`, after an HDMI hot-plug that leaves the tunnel ready, and after a press that took another route, at
// most every `probeInterval`. Nothing here sends while the tunnel isn't ready (`CECTunnel` checks every send and
// logs why).

/// Test Connection's (and Find Receiver's) answer from a receiver over HDMI-CEC. Pure.
nonisolated struct CECReceiverTest: Equatable, Sendable {
    /// nil: no answer.
    var power: CECPowerStatus?
    /// The receiver's OSD name ("VSX-01TXH").
    var name: String?

    var answered: Bool { power != nil }

    /// "On · VSX-01TXH", "Standby · VSX-01TXH", "On", "No answer".
    var line: String {
        guard let power else { return "No answer" }
        let state = power.isOn ? "On" : "Standby"
        guard let name else { return state }
        return "\(state) · \(name)"
    }
}

/// One volume press on a receiver over HDMI-CEC. Pure.
nonisolated enum CECVolumePress: Equatable, Sendable {
    /// Pressed was acknowledged (and Released sent); the receiver's Report Audio Status when it answered.
    case sent(CECAudioStatus?)
    /// Pressed wasn't sent or wasn't acknowledged.
    case notSent
}

/// Main actor. Every effect goes through `CECLink`; tests fake it.
final class CECAudioSystem {
    static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "CEC")

    /// Readiness checks run at most this often (step 10's rule).
    static let probeInterval: TimeInterval = 10
    /// Give Audio Status's answer must come within this after a press.
    static let audioStatusWait: Duration = .milliseconds(300)
    static let nameWait: Duration = .seconds(1)
    /// After this many presses in a row without a Report Audio Status, it isn't asked again until `configure`.
    static let audioStatusAttempts = 3
    /// Step 9c (security M1): a Released that wasn't sent is tried once more after this.
    static let releaseRetryDelay: TimeInterval = 0.1
    /// Step 9c (security L1): while ready, a press re-checks the power status when the last answer is older than this.
    static let readyRecheckInterval: TimeInterval = 60
    /// After MMTVL's power-on, the receiver is asked this long later (it needs a moment to come up), once without the
    /// `probeInterval` wait.
    static let powerOnProbeDelay: TimeInterval = 5

    /// `receiverConnection` is `cec`.
    private(set) var isEnabled = false
    /// The last power status answer since `configure`; nil before one, or when the last check got none.
    private(set) var power: CECPowerStatus?
    /// The OSD name, once the receiver gave it.
    private(set) var name: String?
    /// The tunnel's state at the last check (read-only), for Settings.
    private(set) var availability: CECAvailability?
    /// Ready for volume: answered "on" since `configure`, and the last press was acknowledged.
    private(set) var isAnswering = false
    /// Give Audio Status is still asked after each press.
    private(set) var asksAudioStatus = true
    private var pressesWithoutStatus = 0
    private var askedName = false
    /// The first check's outcome after `configure` is logged even when it's "no answer".
    private var loggedSinceConfigure = false
    private var lastProbeAt: TimeInterval?
    /// When the last power status answer arrived (security L1).
    private var lastStatusAt: TimeInterval?
    private var generation = 0
    /// The readiness check (tests await it).
    private(set) var probeTask: Task<Void, Never>?
    /// A hot-plug within `probeInterval` of the last check: its check waits for the interval's end.
    private(set) var deferredProbeTask: Task<Void, Never>?
    /// The check `powerOnProbeDelay` after MMTVL's power-on (tests await it).
    private(set) var powerOnProbeTask: Task<Void, Never>?
    /// Settings → Audio & TV → Receiver → Status follows it.
    var onStatusChange: () -> Void = {}

    private let link: any CECLink
    private let now: () -> TimeInterval
    private let sleep: (TimeInterval) async -> Void

    init(link: any CECLink,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         sleep: @escaping (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.link = link
        self.now = now
        self.sleep = sleep
    }

    /// From `settings.json` (`receiverConnection` `cec`), at launch and whenever a receiver setting changes. Forgets
    /// what the receiver said; when enabled, asks it for its power status (read-only).
    func configure(enabled: Bool) {
        generation += 1
        isEnabled = enabled
        power = nil
        name = nil
        isAnswering = false
        asksAudioStatus = true
        pressesWithoutStatus = 0
        askedName = false
        loggedSinceConfigure = false
        lastProbeAt = nil
        lastStatusAt = nil
        probeTask = nil
        deferredProbeTask?.cancel()
        deferredProbeTask = nil
        powerOnProbeTask?.cancel()
        powerOnProbeTask = nil
        onStatusChange()
        if enabled {
            Self.logger.notice("CEC: receiver over HDMI-CEC (address 5)")
            probeIfNeeded()
        }
    }

    // MARK: Readiness

    /// Asks a receiver that isn't ready for its power status, at most every `probeInterval`.
    func probeIfNeeded() {
        guard isEnabled, !isAnswering, probeTask == nil, !probedRecently else { return }
        startProbe()
    }

    /// After an HDMI hot-plug (the tunnel's device was dropped by `HDMICEC.noteDisplayChange`): once the tunnel reads
    /// ready, a receiver that isn't answering is asked again (after the interval's end, if one ran within it).
    func noteDisplayChange() {
        guard isEnabled else { return }
        let current = generation
        Task { [weak self, link] in
            let state = await link.availability()
            guard let self, current == generation else { return }
            setAvailability(state)
            guard state == .ready, !isAnswering else { return }
            probeSoon()
        }
    }

    private var probedRecently: Bool {
        guard let lastProbeAt else { return false }
        return now() - lastProbeAt < Self.probeInterval
    }

    private func probeSoon() {
        guard probedRecently, let lastProbeAt else {
            probeIfNeeded()
            return
        }
        guard deferredProbeTask == nil else { return }
        let delay = lastProbeAt + Self.probeInterval - now()
        let current = generation
        deferredProbeTask = Task { [weak self, sleep] in
            await sleep(delay)
            guard let self, current == generation else { return }
            deferredProbeTask = nil
            probeIfNeeded()
        }
    }

    private func startProbe() {
        lastProbeAt = now()
        let current = generation
        probeTask = Task { [weak self, link] in
            let status = await link.powerStatus(of: .audioSystem)
            let state = await link.availability()
            guard let self, current == generation else { return }
            setAvailability(state)
            apply(status)
            if status != nil, !askedName {
                askedName = true
                let name = await Self.queryName(link)
                guard current == generation else { return }
                if let name { setName(name) }
            }
            probeTask = nil
        }
    }

    private func apply(_ status: CECPowerStatus?) {
        if status != nil { lastStatusAt = now() }
        let wasAnswering = isAnswering
        let previous = power
        power = status
        isAnswering = status?.isOn == true
        if wasAnswering != isAnswering || previous != status || !loggedSinceConfigure {
            loggedSinceConfigure = true
            switch status {
            case .some(let status) where status.isOn:
                Self.logger.notice("CEC: the receiver is on; volume goes to it over HDMI-CEC")
            case .some:
                Self.logger.notice("CEC: the receiver is in standby; volume takes the next route")
            case nil:
                // Why nothing was sent, when the tunnel isn't ready (its own line says the details).
                let reason = switch availability {
                case .notAvailable: " (HDMI-CEC not available, nothing sent)"
                case .noDisplay: " (no HDMI display, nothing sent)"
                case .ready, nil: ""
                }
                Self.logger.notice("CEC: the receiver didn't answer\(reason, privacy: .public); volume takes the next route")
            }
            onStatusChange()
        }
    }

    private func setAvailability(_ state: CECAvailability) {
        guard state != availability else { return }
        availability = state
        onStatusChange()
    }

    private func setName(_ name: String) {
        guard name != self.name else { return }
        self.name = name
        Self.logger.notice("CEC: the receiver is \(name, privacy: .public)")
        onStatusChange()
    }

    private static func queryName(_ link: any CECLink) async -> String? {
        await link.query(.giveOSDName, reply: .audioSystemOSDName, timeout: nameWait).flatMap(CECOSDName.parseReply)
    }

    // MARK: Volume

    /// One Vol± or Mute: User Control Pressed, then Released; then (until 3 presses in a row went unanswered) Give
    /// Audio Status, with `audioStatusWait` for the answer. A Pressed that isn't acknowledged makes the receiver not
    /// ready (another send in progress, before or during our write, doesn't). A Pressed that may have gone out is always followed by Released
    /// (security M1), and a ready receiver's power status older than `readyRecheckInterval` is checked again after the
    /// press (security L1).
    func press(_ action: VolumeAction) async -> CECVolumePress {
        guard isEnabled else { return .notSent }
        let current = generation
        let key: CECVolumeKey = switch action {
        case .up: .volumeUp
        case .down: .volumeDown
        case .mute: .mute
        }
        let pressed = await link.send(.volumeKey(key, to: .audioSystem))
        // Security M1: a Pressed that may have gone out is always released.
        if pressed.mayHaveGoneOut { await release() }
        guard pressed == .sent else {
            if current == generation, pressed != .busy, pressed != .collided, isAnswering {
                isAnswering = false
                Self.logger.notice("CEC: the receiver didn't take the volume key (\(String(describing: pressed), privacy: .public)); volume takes the next route until it answers")
                onStatusChange()
            }
            return .notSent
        }
        // Security L1: a receiver that went to standby on its own (its remote, the TV's) stops being ready; checked
        // once the press is done (after Give Audio Status too), so the press isn't delayed.
        defer { if current == generation { recheckIfStale() } }
        guard current == generation, asksAudioStatus else { return .sent(nil) }
        let reply = await link.query(.giveAudioStatus, reply: .reportAudioStatus, timeout: Self.audioStatusWait)
        guard current == generation else { return .sent(nil) }
        if let status = reply.flatMap(CECAudioStatus.parseReply) {
            pressesWithoutStatus = 0
            return .sent(status)
        }
        pressesWithoutStatus += 1
        if pressesWithoutStatus >= Self.audioStatusAttempts {
            asksAudioStatus = false
            Self.logger.notice("CEC: the receiver doesn't report its volume (no Report Audio Status after \(Self.audioStatusAttempts, privacy: .public) presses); not asking again until the receiver settings change")
        }
        return .sent(nil)
    }

    /// Released to the receiver; when it isn't sent, once more after `releaseRetryDelay` (security M1).
    private func release() async {
        let first = await link.send(.released(to: .audioSystem))
        guard first != .sent else { return }
        Self.logger.notice("CEC: Released to the receiver: \(String(describing: first), privacy: .public); trying once more")
        await sleep(Self.releaseRetryDelay)
        let second = await link.send(.released(to: .audioSystem))
        if second != .sent {
            Self.logger.notice("CEC: Released to the receiver: \(String(describing: second), privacy: .public)")
        }
    }

    /// Security L1: while ready, asks the power status again when the last answer is older than
    /// `readyRecheckInterval` (a standby answer makes it not ready).
    private func recheckIfStale() {
        guard isEnabled, isAnswering, probeTask == nil else { return }
        if let lastStatusAt, now() - lastStatusAt < Self.readyRecheckInterval { return }
        startProbe()
    }

    // MARK: Power (L14) and Settings

    /// Step 9c (coordinator decision): MMTVL turned the receiver off (its own `45:36`, or a CEC TV's `4F:36`). It's
    /// not ready at once, so volume takes the next route; and it isn't asked again for `probeInterval` (a check while
    /// it's still going down could read "on").
    func noteTurnedOff() {
        guard isEnabled else { return }
        // QA minor: a check already on its way can't make it ready again with a late "on".
        generation += 1
        probeTask = nil
        deferredProbeTask?.cancel()
        deferredProbeTask = nil
        powerOnProbeTask?.cancel()
        powerOnProbeTask = nil
        lastProbeAt = now()
        let wasAnswering = isAnswering
        isAnswering = false
        power = .standby
        if wasAnswering { Self.logger.notice("CEC: MMTVL turned the receiver off; volume takes the next route") }
        onStatusChange()
    }

    /// Step 9c (coordinator decision): after MMTVL's power-on, the receiver is asked again `powerOnProbeDelay`
    /// later, without waiting out `probeInterval` (once).
    func noteTurnedOn() {
        guard isEnabled else { return }
        powerOnProbeTask?.cancel()
        let current = generation
        powerOnProbeTask = Task { [weak self, sleep] in
            await sleep(Self.powerOnProbeDelay)
            guard let self, !Task.isCancelled, current == generation else { return }
            powerOnProbeTask = nil
            lastProbeAt = nil
            probeIfNeeded()
        }
    }

    /// `45:36`: Standby to the receiver alone.
    func powerOff() async -> Bool {
        guard isEnabled else { return false }
        return await link.send(.audioSystemStandby) == .sent
    }

    /// `45:44:6D` + `45:45`: Power On Function (unverified on the Pioneer).
    func powerOn() async -> Bool {
        guard isEnabled else { return false }
        let pressed = await link.send(.audioSystemPowerOn)
        if pressed.mayHaveGoneOut { await release() }
        return pressed == .sent
    }

    /// Test Connection and Find Receiver (read-only): Give Device Power Status, then (when it answered) Give OSD Name.
    /// Works whether or not the receiver is set up over HDMI-CEC (Find Receiver asks before it is); when it is, the
    /// answers update the ready state and the name.
    func test() async -> CECReceiverTest {
        let current = generation
        let status = await link.powerStatus(of: .audioSystem)
        let name = status == nil ? nil : await Self.queryName(link)
        let state = await link.availability()
        if isEnabled, current == generation {
            setAvailability(state)
            apply(status)
            if let name {
                askedName = true
                setName(name)
            }
        }
        return CECReceiverTest(power: status, name: name)
    }
}
