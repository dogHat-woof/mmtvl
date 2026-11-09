import AppKit
import AudioToolbox
import CoreAudio
import os

/// `settings.json` `phoneRemoteVolume` (L8; M7h D44 adds `receiver`, step 9c `tv`). Unknown values read as `.auto`.
nonisolated enum VolumeMode: String, Sendable { case auto, receiver, tv, keys, system, app }

/// Where a volume button goes (D25, D44): the phone's, the Siri Remote's and (L3a) the volume keys. Step 9c:
/// `cecReceiver` (a receiver over HDMI-CEC) and `tv` (the TV's own volume, opt-in).
nonisolated enum VolumeRoute: Equatable, Sendable { case receiver, cecReceiver, tv, keys, system, app, unavailable }

extension VolumeRoute {
    /// D44 (amends D25's L8; step 9c). auto: a ready receiver (serial or network) → receiver; a ready receiver over
    /// HDMI-CEC → cecReceiver; a ready TV (`tvReady` includes Volume Buttons Change TV Volume) with **no receiver set
    /// up at all** (`receiverSetUp`, any connection; coordinator decision on security L2: a set-up receiver that isn't
    /// answering never sends its presses to the TV, so its Maximum Volume can't be bypassed) → tv; SoundSource → keys;
    /// settable → system; active → app; else unavailable. Forced modes ignore the others; `receiver` covers every
    /// connection; `receiver` or `tv` without one ready is unavailable, and so is `tv` with a receiver set up.
    static func choose(mode: VolumeMode, receiverReady: Bool, cecReceiverReady: Bool = false, tvReady: Bool = false,
                       receiverSetUp: Bool = false, soundSourceRunning: Bool, systemSettable: Bool,
                       launcherActive: Bool) -> VolumeRoute {
        let tvAllowed = tvReady && !(receiverSetUp || receiverReady || cecReceiverReady)
        switch mode {
        case .auto:
            if receiverReady { return .receiver }
            if cecReceiverReady { return .cecReceiver }
            if tvAllowed { return .tv }
            if soundSourceRunning { return .keys }
            if systemSettable { return .system }
            return launcherActive ? .app : .unavailable
        case .receiver:
            if receiverReady { return .receiver }
            return cecReceiverReady ? .cecReceiver : .unavailable
        case .tv:
            return tvAllowed ? .tv : .unavailable
        case .keys:
            return .keys
        case .system:
            return systemSettable ? .system : .unavailable
        case .app:
            return launcherActive ? .app : .unavailable
        }
    }
}

nonisolated enum VolumeFeedback: Equatable, Sendable {
    /// 0…1.
    case level(Double, muted: Bool)
    /// Sent, the level isn't known: SoundSource's keys, a receiver that reports no dB (Onkyo), or (step 9c) a CEC
    /// receiver or TV that doesn't report its volume.
    case sentKeys
    case unavailable(String)
}

extension VolumeFeedback {
    /// The bottom of `receiverLevel`'s scale: −80 dB reads 0, 0 dB reads 1 (Denon's and Marantz's absolute 0–80).
    static let receiverFloorDB = -80.0

    /// M7h step 10: the receiver's reported dB as the phone's 0…1 level, linear from −80 dB (0) to 0 dB (1), clamped
    /// (louder than 0 dB reads 1; −∞ reads 0). Muted with no dB known reads `.level(0, muted: true)` (the phone shows
    /// "Muted" and not the level); neither known → `.sentKeys`.
    static func receiver(dB: Double?, muted: Bool?) -> VolumeFeedback {
        let level = dB.map { min(1, max(0, ($0 - receiverFloorDB) / -receiverFloorDB)) }
        if muted == true { return .level(level ?? 0, muted: true) }
        if let level { return .level(level, muted: false) }
        return .sentKeys
    }

    /// Step 9c: a 0…100 level (CEC Report Audio Status, VIERA) as the phone's 0…1; muted with no level reads
    /// `.level(0, muted: true)`; neither known → `.sentKeys`.
    static func percent(_ volume: Int?, muted: Bool?) -> VolumeFeedback {
        let level = volume.map { min(1, max(0, Double($0) / 100)) }
        if muted == true { return .level(level ?? 0, muted: true) }
        if let level { return .level(level, muted: false) }
        return .sentKeys
    }
}

/// What `VolumeController.perform` did: for the phone (`feedback`) and the L8 toast (`VolumeToast`).
nonisolated struct VolumeOutcome: Equatable, Sendable {
    var route: VolumeRoute
    var feedback: VolumeFeedback
    /// The receiver's volume after the command, when it reported dB (`-.infinity` at the bottom of its scale).
    var dB: Double?
    /// Step 10 (user decision): Vol+ at or above `receiverMaxDB` sent nothing; the cap.
    var cappedAt: Double?
    /// Step 9c: the press, for "Volume Up" / "Volume Down" / "Mute" when the level isn't known (CEC receiver, TV).
    var action: VolumeAction?
}

/// M7h L8: the toast for the Siri Remote's volume buttons and the volume keys.
nonisolated enum VolumeToast {
    struct Message: Equatable, Sendable {
        var text: String
        var symbol: String
    }

    static let volumeSymbol = "speaker.wave.2.fill"
    static let mutedSymbol = "speaker.slash.fill"
    static let errorSymbol = "exclamationmark.triangle"

    /// The receiver: "Muted", "Volume −20 dB", "Volume Min" (−∞), "Volume 0 dB (max)" / "Volume +5 dB (max)" (at or
    /// above the cap: the receiver's level), "Volume" (no dB). Other routes: "Muted", "Volume 50 %". Step 9c, a CEC
    /// receiver or the TV without a level: "Volume Up", "Volume Down", "Mute". SoundSource's keys show none
    /// (SoundSource shows its own).
    static func message(for outcome: VolumeOutcome) -> Message? {
        switch outcome.feedback {
        case .unavailable(let text):
            return Message(text: text, symbol: errorSymbol)
        case .level(_, muted: true):
            return Message(text: "Muted", symbol: mutedSymbol)
        case .level(let level, muted: false):
            if outcome.route == .receiver {
                if let cap = outcome.cappedAt {
                    return Message(text: "Volume \(format(dB: outcome.dB ?? cap)) (max)", symbol: volumeSymbol)
                }
                return Message(text: outcome.dB.map { "Volume \(format(dB: $0))" } ?? "Volume", symbol: volumeSymbol)
            }
            let percent = (min(1, max(0, level)) * 100).rounded()
            return Message(text: "Volume \(String(format: "%.0f", percent)) %", symbol: volumeSymbol)
        case .sentKeys:
            switch outcome.route {
            case .receiver:
                return Message(text: "Volume", symbol: volumeSymbol)
            case .cecReceiver, .tv:
                return switch outcome.action {
                case .up: Message(text: "Volume Up", symbol: volumeSymbol)
                case .down: Message(text: "Volume Down", symbol: volumeSymbol)
                case .mute: Message(text: "Mute", symbol: mutedSymbol)
                case nil: Message(text: "Volume", symbol: volumeSymbol)
                }
            default:
                return nil
            }
        }
    }

    /// Step 13b: the toast to show for a press, or nil. With Show Volume off (`enabled == false`) the level and Muted
    /// messages are hidden; `.unavailable` messages always show, since they say why a press did nothing.
    static func message(for outcome: VolumeOutcome, enabled: Bool) -> Message? {
        if !enabled {
            guard case .unavailable = outcome.feedback else { return nil }
        }
        return message(for: outcome)
    }

    /// "−20 dB", "−20.5 dB", "0 dB", "+3 dB" (a real minus sign); "Min" for −∞. Never converts to an `Int`, so any
    /// value is safe (security, step 10).
    static func format(dB: Double) -> String {
        guard dB.isFinite else { return dB == -.infinity ? "Min" : "\u{2014} dB" }
        let magnitude = abs(dB)
        if magnitude < 0.05 { return "0 dB" }
        let number = String(format: magnitude == magnitude.rounded() ? "%.0f" : "%.1f", magnitude)
        return (dB < 0 ? "\u{2212}" : "+") + number + " dB"
    }
}

/// MMTVL's own playback volume (L9): mpv and the YouTube page. In memory only.
nonisolated struct AppVolume: Equatable, Sendable {
    static let step = 5

    /// 0…100.
    var level = 100
    var muted = false

    /// up/down ±5 clamped to 0…100 and unmute; mute toggles.
    mutating func apply(_ action: VolumeAction) {
        switch action {
        case .up:
            level = min(100, level + Self.step)
            muted = false
        case .down:
            level = max(0, level - Self.step)
            muted = false
        case .mute:
            muted.toggle()
        }
    }
}

/// The CoreAudio default output device. Reads the device on every call (HDMI may come and go).
nonisolated enum SystemVolume {
    static let steps: Float32 = 16

    /// VirtualMainVolume exists and is settable.
    static var isSettable: Bool {
        guard let device = defaultOutputDevice() else { return false }
        return isSettable(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
    }

    static func level() -> Float32? {
        guard let device = defaultOutputDevice() else { return nil }
        return get(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, as: Float32.self)
    }

    /// Clamped 0…1.
    static func setLevel(_ level: Float32) {
        guard let device = defaultOutputDevice(),
              isSettable(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        else { return }
        set(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, min(1, max(0, level)))
    }

    static func isMuted() -> Bool? {
        guard let device = defaultOutputDevice(),
              let value = get(device, kAudioDevicePropertyMute, as: UInt32.self)
        else { return nil }
        return value != 0
    }

    /// No-op if the mute property is missing or unsettable.
    static func setMuted(_ muted: Bool) {
        guard let device = defaultOutputDevice(), isSettable(device, kAudioDevicePropertyMute) else { return }
        set(device, kAudioDevicePropertyMute, UInt32(muted ? 1 : 0))
    }

    /// Up/down by 1/16 clamped to 0…1, snapped to the nearest 1/16.
    static func step(_ level: Float32, _ action: VolumeAction) -> Float32 {
        let current = (level * steps).rounded()
        let next: Float32
        switch action {
        case .up: next = current + 1
        case .down: next = current - 1
        case .mute: next = current
        }
        return min(steps, max(0, next)) / steps
    }

    // MARK: CoreAudio

    private static func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func outputAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    private static func isSettable(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = outputAddress(selector)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private static func get<T>(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, as type: T.Type) -> T? {
        var address = outputAddress(selector)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }

    private static func set<T>(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: T) {
        var address = outputAddress(selector)
        var value = value
        _ = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value)
    }
}

/// Step 9c: one press on the TV's own volume. Pure.
nonisolated enum TVVolumeResult: Equatable, Sendable {
    /// The TV's level (0…100) and mute afterwards (VIERA).
    case level(Int, muted: Bool)
    /// Sent; the level isn't known (HDMI-CEC).
    case sent
    /// The TV didn't answer or refused.
    case failed
}

/// Step 9c: the TV's own volume, for Volume Buttons Change TV Volume (`tvVolumeEnabled`): a network VIERA
/// (`TVController`) or HDMI-CEC (`HDMICEC`), through `VolumeTVSelector`.
protocol VolumeTV: AnyObject {
    /// Set up enough to send volume to (a VIERA with an address, or the HDMI-CEC brand).
    var canChangeVolume: Bool { get }
    /// Answered at the last check (cached: the event tap never waits). VIERA: the 1 s connection check reached it;
    /// HDMI-CEC: the last power status was "on".
    var isAnsweringForVolume: Bool { get }
    /// The read-only check behind `isAnsweringForVolume`.
    func checkVolumeReadiness() async
    func changeVolume(_ action: VolumeAction) async -> TVVolumeResult
}

extension TVController: VolumeTV {
    var canChangeVolume: Bool { isConfigured }
    var isAnsweringForVolume: Bool { isConfigured && lastCheckAnswered }

    func checkVolumeReadiness() async {
        _ = await isOn()
    }

    func changeVolume(_ action: VolumeAction) async -> TVVolumeResult {
        guard let result = await stepVolume(action) else { return .failed }
        return .level(result.volume, muted: result.muted)
    }
}

extension HDMICEC: VolumeTV {
    var canChangeVolume: Bool { isConfigured }
    var isAnsweringForVolume: Bool { isConfigured && lastPowerStatus?.isOn == true }

    func checkVolumeReadiness() async {
        _ = await powerStatus()
    }

    func changeVolume(_ action: VolumeAction) async -> TVVolumeResult {
        let key: CECVolumeKey = switch action {
        case .up: .volumeUp
        case .down: .volumeDown
        case .mute: .mute
        }
        return await sendVolumeKey(key) ? .sent : .failed
    }
}

/// Step 9c: HDMI-CEC when `tvBrand` is `cec`, else the network TV (like `PowerTVSelector`).
final class VolumeTVSelector: VolumeTV {
    private let network: (any VolumeTV)?
    private let cec: (any VolumeTV)?

    init(network: (any VolumeTV)?, cec: (any VolumeTV)?) {
        self.network = network
        self.cec = cec
    }

    private var current: (any VolumeTV)? {
        if let cec, cec.canChangeVolume { return cec }
        return network
    }

    var canChangeVolume: Bool { current?.canChangeVolume ?? false }
    var isAnsweringForVolume: Bool { current?.isAnsweringForVolume ?? false }
    func checkVolumeReadiness() async { await current?.checkVolumeReadiness() }
    func changeVolume(_ action: VolumeAction) async -> TVVolumeResult { await current?.changeVolume(action) ?? .failed }
}

/// Performs volume buttons on the route `VolumeRoute.choose` picks (D25, D44, L8): the phone's, the Siri Remote's
/// and the volume keys the event tap takes (L3a). The receiver is ready while `ReceiverController.isAnswering`.
/// Its commands run one at a time, each waiting for its reply. Presses that come meanwhile wait, bounded (QA minor 1,
/// security low): the latest Vol+/Vol− only (a newer one replaces it, and the replaced press is answered at once with
/// the receiver's last known state), so a held key moves the receiver at the pace it answers and stops within a
/// step of the release; and the Mute presses by parity (never replaced: two cancel, three toggle once), answered
/// through the latest one. A command that gets no reply ends the press ("Receiver isn't answering") and the waiting
/// ones with it, and the next press takes the next route. Waiting presses run in the order their slots were filled.
/// A press that falls back asks the receiver again (`queryVolume`), and so does a transport coming up
/// (`receiverLinkUp`; later, if a probe ran within `probeInterval`), so one that answers again is used from then on.
/// Probes from any source run at most every `probeInterval`, and never count as activity for the network link's idle
/// close (security, step 10). Vol+ never goes above `maxDB` (user decision).
/// Step 9c: a receiver over HDMI-CEC (`CECAudioSystem`, ready while `isAnswering`) and the TV's own volume
/// (`VolumeTV`, only with `tvVolumeEnabled`) are devices too, with the same queue rules (the queue runs on the device
/// its first press went to); each is asked again after a press that fell back, at most every `probeInterval`.
final class VolumeController {
    typealias Completion = (VolumeOutcome) -> Void

    static let soundSourceBundleID = "com.rogueamoeba.soundsource"
    static let notAnsweringMessage = "Receiver isn't answering"
    /// Step 9c.
    static let tvNotAnsweringMessage = "TV isn't answering"
    static let unavailableMessage = "Volume can't be changed here"
    /// How often a receiver that isn't answering is asked again by presses, at most.
    static let probeInterval: TimeInterval = 10
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Volume")

    /// Where the queue's presses go (step 9c).
    private enum Device: Equatable {
        case receiver, cecReceiver, tv

        var route: VolumeRoute {
            switch self {
            case .receiver: .receiver
            case .cecReceiver: .cecReceiver
            case .tv: .tv
            }
        }
    }

    /// Presses waiting for the receiver command on its way.
    private struct Waiting {
        var step: (action: VolumeAction, completion: Completion)?
        /// An odd number of Mute presses is waiting.
        var muteToggles = false
        var muteCompletion: Completion?
        /// QA minor 1: the Mute slot was filled before the step slot (it runs first).
        var muteFirst = false

        var isEmpty: Bool { step == nil && muteCompletion == nil }
        var count: Int { (step == nil ? 0 : 1) + (muteCompletion == nil ? 0 : 1) }
    }

    private let mode: () -> VolumeMode
    private let isLauncherActive: () -> Bool
    private let applyAppVolume: (AppVolume) -> Void
    private let receiver: ReceiverController?
    private let maxDB: () -> Double
    private let cecReceiver: CECAudioSystem?
    private let tv: (any VolumeTV)?
    private let tvVolumeEnabled: () -> Bool
    private let receiverConfigured: () -> Bool
    private let soundSourceRunning: () -> Bool
    private let systemSettable: () -> Bool
    private let now: () -> TimeInterval
    private let sleep: (TimeInterval) async -> Void
    private(set) var appVolume = AppVolume()

    /// A receiver (or, step 9c, CEC receiver or TV) command is on its way or waiting for its reply.
    private(set) var isReceiverBusy = false
    /// The device the running queue sends to.
    private var queueDevice = Device.receiver
    private var waiting = Waiting()
    private var lastProbeAt: TimeInterval?
    private var lastTVProbeAt: TimeInterval?
    /// The last TV check's answer, for its log line (logged when it changes; nil before the first).
    private var lastTVProbeAnswered: Bool?
    /// The receiver's commands, while `isReceiverBusy` (tests await it).
    private(set) var receiverTask: Task<Void, Never>?
    /// The query of a receiver that isn't answering, or whose link just came up (tests await it).
    private(set) var probeTask: Task<Void, Never>?
    /// A link came up within `probeInterval` of the last probe: its probe waits for the interval's end.
    private(set) var deferredProbeTask: Task<Void, Never>?
    /// Step 9c: the TV's readiness check (tests await it).
    private(set) var tvProbeTask: Task<Void, Never>?

    /// Tests: how many presses are waiting (at most 2).
    var waitingCount: Int { waiting.count }

    init(mode: @escaping () -> VolumeMode, isLauncherActive: @escaping () -> Bool,
         applyAppVolume: @escaping (AppVolume) -> Void,
         receiver: ReceiverController? = nil,
         maxDB: @escaping () -> Double = { AppSettings().receiverMaxDB },
         cecReceiver: CECAudioSystem? = nil,
         tv: (any VolumeTV)? = nil,
         tvVolumeEnabled: @escaping () -> Bool = { false },
         receiverConfigured: @escaping () -> Bool = { false },
         soundSourceRunning: @escaping () -> Bool = { VolumeController.isSoundSourceRunning() },
         systemSettable: @escaping () -> Bool = { SystemVolume.isSettable },
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         sleep: @escaping (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.mode = mode
        self.isLauncherActive = isLauncherActive
        self.applyAppVolume = applyAppVolume
        self.receiver = receiver
        self.maxDB = maxDB
        self.cecReceiver = cecReceiver
        self.tv = tv
        self.tvVolumeEnabled = tvVolumeEnabled
        self.receiverConfigured = receiverConfigured
        self.soundSourceRunning = soundSourceRunning
        self.systemSettable = systemSettable
        self.now = now
        self.sleep = sleep
    }

    static func isSoundSourceRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == soundSourceBundleID }
    }

    /// D44: a receiver is set up and answering (`ReceiverController.isAnswering`).
    var receiverReady: Bool { receiver?.isAnswering == true }

    /// Step 9c: a receiver over HDMI-CEC answered "on" (`CECAudioSystem.isAnswering`).
    var cecReceiverReady: Bool { cecReceiver?.isAnswering == true }

    /// Step 9c: a receiver is set up over any connection (serial, network or HDMI-CEC), answering or not. The TV never
    /// gets the volume buttons then (coordinator decision on security L2). Build 25 security L2: from the settings
    /// (`receiverConfigured`, `AppSettings.receiverIsSetUp`), so a network receiver without a usable address (whose
    /// controller has brand `none`) still counts; the controllers' own state counts too.
    var receiverSetUp: Bool {
        receiverConfigured() || receiver.map { $0.brand != .none } == true || cecReceiver?.isEnabled == true
    }

    /// Step 9c: Volume Buttons Change TV Volume is on, and the TV answered its last check.
    var tvReady: Bool {
        guard let tv, tvVolumeEnabled(), tv.canChangeVolume else { return false }
        return tv.isAnsweringForVolume
    }

    /// L3a: the event tap takes the volume keys while they'd go to the receiver (step 9c: or the CEC receiver, or the
    /// TV). Cheap (no CoreAudio or app list, cached readiness): those come first in every order that has them. When
    /// none is ready, they're asked again (`probeInterval`). Step 18 widens this to the software route.
    func consumesVolumeKeys() -> Bool {
        let route = VolumeRoute.choose(mode: mode(), receiverReady: receiverReady, cecReceiverReady: cecReceiverReady,
                                       tvReady: tvReady, receiverSetUp: receiverSetUp, soundSourceRunning: false,
                                       systemSettable: false, launcherActive: false)
        let consumed = route == .receiver || route == .cecReceiver || route == .tv
        if !consumed { probeReceiverIfNeeded() }
        return consumed
    }

    /// Runs `action` on the chosen route. `completion` gets the outcome once: at once, except on the receiver (and the
    /// CEC receiver and the TV), after its reply (or `ReceiverController.replyTimeout` without one).
    func perform(_ action: VolumeAction, completion: @escaping Completion = { _ in }) {
        let mode = mode()
        // Step 13e: a ready receiver or TV comes first in every order that has it, so the app list and CoreAudio
        // (IPC on the main actor) are only asked when none is.
        let deviceRoute = VolumeRoute.choose(mode: mode, receiverReady: receiverReady, cecReceiverReady: cecReceiverReady,
                                             tvReady: tvReady, receiverSetUp: receiverSetUp, soundSourceRunning: false,
                                             systemSettable: false, launcherActive: false)
        let route = [.receiver, .cecReceiver, .tv].contains(deviceRoute) ? deviceRoute
            : VolumeRoute.choose(mode: mode, receiverReady: receiverReady, cecReceiverReady: cecReceiverReady,
                                 tvReady: tvReady, receiverSetUp: receiverSetUp,
                                 soundSourceRunning: soundSourceRunning(), systemSettable: systemSettable(),
                                 launcherActive: isLauncherActive())
        Self.logger.debug("Volume \(action.rawValue, privacy: .public) via \(String(describing: route), privacy: .public)")

        switch route {
        case .receiver:
            performOnDevice(.receiver, action, completion: completion)
            return

        case .cecReceiver:
            performOnDevice(.cecReceiver, action, completion: completion)
            return

        case .tv:
            performOnDevice(.tv, action, completion: completion)
            return

        case .keys:
            guard SyntheticInput.canPost else {
                completion(VolumeOutcome(route: .keys, feedback: .unavailable("Allow Accessibility for MMTVL on the Mac")))
                break
            }
            let key: Int32 = switch action {
            case .up: SyntheticInput.NXKey.soundUp
            case .down: SyntheticInput.NXKey.soundDown
            case .mute: SyntheticInput.NXKey.mute
            }
            SyntheticInput.postMediaKey(key)
            completion(VolumeOutcome(route: .keys, feedback: .sentKeys))

        case .system:
            switch action {
            case .up, .down:
                SystemVolume.setLevel(SystemVolume.step(SystemVolume.level() ?? 0.5, action))
                SystemVolume.setMuted(false)
            case .mute:
                SystemVolume.setMuted(!(SystemVolume.isMuted() ?? false))
            }
            completion(VolumeOutcome(route: .system, feedback: .level(Double(SystemVolume.level() ?? 0),
                                                                       muted: SystemVolume.isMuted() ?? false)))

        case .app:
            appVolume.apply(action)
            applyAppVolume(appVolume)
            completion(VolumeOutcome(route: .app, feedback: .level(Double(appVolume.level) / 100, muted: appVolume.muted)))

        case .unavailable:
            let message = switch mode {
            case .receiver: Self.notAnsweringMessage
            case .tv: Self.tvNotAnsweringMessage
            default: Self.unavailableMessage
            }
            completion(VolumeOutcome(route: .unavailable, feedback: .unavailable(message)))
        }
        probeReceiverIfNeeded()
    }

    /// Asks a set-up receiver that isn't answering for its volume (a reply makes it ready), at most every
    /// `probeInterval`, and only when the mode would use it. Also run once at launch, and (QA major, step 9c) after
    /// every press that went somewhere other than the set-up receiver (keys, system, app, unavailable). Step 9c: also a receiver over
    /// HDMI-CEC (its power status) and, with Volume Buttons Change TV Volume on, the TV (its connection check or
    /// power status), each at most every `probeInterval`, only when the mode would use it.
    func probeReceiverIfNeeded() {
        let mode = mode()
        if mode == .auto || mode == .receiver { cecReceiver?.probeIfNeeded() }
        probeTVIfNeeded(mode: mode)
        guard let receiver, !receiver.isAnswering, !probedRecently else { return }
        startProbe(kind: .probe)
    }

    /// Step 9c: Volume Buttons Change TV Volume or the TV settings changed: the TV is asked at once (when on).
    func tvSettingsChanged() {
        lastTVProbeAt = nil
        lastTVProbeAnswered = nil
        probeTVIfNeeded(mode: mode())
    }

    private func probeTVIfNeeded(mode: VolumeMode) {
        guard mode == .auto || mode == .tv, let tv, tvVolumeEnabled(), tv.canChangeVolume, !tv.isAnsweringForVolume,
              tvProbeTask == nil, !isReceiverBusy
        else { return }
        // The TV is used only when no receiver is set up (security L2).
        if receiverSetUp { return }
        if let lastTVProbeAt, now() - lastTVProbeAt < Self.probeInterval { return }
        lastTVProbeAt = now()
        tvProbeTask = Task { [weak self] in
            await tv.checkVolumeReadiness()
            guard let self else { return }
            tvProbeTask = nil
            let answering = tv.isAnsweringForVolume
            if answering != lastTVProbeAnswered {
                lastTVProbeAnswered = answering
                Self.logger.notice("TV volume: the TV \(answering ? "answers; volume goes to it when no receiver is ready" : "doesn't answer; volume takes the next route", privacy: .public)")
            }
        }
    }

    /// QA minor 2: the receiver's transport came up (`ReceiverController.onLinkUp`): ask it, so a receiver that comes
    /// back is ready before the next press. Within `probeInterval` of the last probe it waits for the interval's end
    /// (security: a link that keeps dropping and reconnecting isn't asked on every reconnect). A passive probe: it
    /// doesn't keep the link from its idle close, and runs only while the link is open.
    func receiverLinkUp() {
        guard probedRecently, let lastProbeAt else {
            startProbe(kind: .passiveProbe)
            return
        }
        guard deferredProbeTask == nil else { return }
        let delay = lastProbeAt + Self.probeInterval - now()
        deferredProbeTask = Task { [weak self, sleep] in
            await sleep(delay)
            guard let self else { return }
            deferredProbeTask = nil
            receiverLinkUp()
        }
    }

    private var probedRecently: Bool {
        guard let lastProbeAt else { return false }
        return now() - lastProbeAt < Self.probeInterval
    }

    private func startProbe(kind: ReceiverRequestKind) {
        guard let receiver, receiver.brand != .none, !isReceiverBusy, probeTask == nil else { return }
        // A passive probe never opens anything, so it's only worth sending on an open link.
        if kind == .passiveProbe, !receiver.isConnected { return }
        let mode = mode()
        guard mode == .auto || mode == .receiver else { return }
        lastProbeAt = now()
        probeTask = Task { [weak self] in
            _ = await receiver.request(.queryVolume, readyTimeout: ReceiverController.volumeReadyTimeout, kind: kind)
            self?.probeTask = nil
        }
    }

    // MARK: The queue (D44; step 9c: every device)

    private func performOnDevice(_ device: Device, _ action: VolumeAction, completion: @escaping Completion) {
        guard !isReceiverBusy else {
            wait(action, completion: completion)
            return
        }
        isReceiverBusy = true
        queueDevice = device
        receiverTask = Task { [weak self] in
            await self?.runQueue(action, completion: completion)
        }
    }

    /// Bounded: one waiting Vol+/Vol− (the latest) and one Mute completion with the parity.
    private func wait(_ action: VolumeAction, completion: @escaping Completion) {
        if waiting.isEmpty { waiting.muteFirst = action == .mute }
        switch action {
        case .up, .down:
            if let replaced = waiting.step { replaced.completion(currentOutcome(for: replaced.action)) }
            waiting.step = (action, completion)
        case .mute:
            waiting.muteCompletion?(currentOutcome(for: .mute))
            waiting.muteToggles.toggle()
            waiting.muteCompletion = completion
        }
    }

    private func runQueue(_ action: VolumeAction, completion: Completion) async {
        var outcome = await run(action)
        completion(outcome)
        while !waiting.isEmpty {
            let next = waiting
            waiting = Waiting()
            if next.muteFirst { outcome = await runWaitingMute(next, after: outcome) }
            if let step = next.step {
                if !outcome.isNotAnswering { outcome = await run(step.action) }
                step.completion(outcome)
            }
            if !next.muteFirst { outcome = await runWaitingMute(next, after: outcome) }
        }
        isReceiverBusy = false
    }

    /// The waiting Mute presses: one toggle for an odd number, none for an even one. Not answering (`previous`): the
    /// waiting presses end too, rather than wait another timeout each.
    private func runWaitingMute(_ next: Waiting, after previous: VolumeOutcome) async -> VolumeOutcome {
        guard let muteCompletion = next.muteCompletion else { return previous }
        var outcome = previous
        var toggled = false
        if !outcome.isNotAnswering && next.muteToggles {
            outcome = await run(.mute)
            toggled = true
        }
        muteCompletion(outcome.isNotAnswering || toggled ? outcome : currentOutcome(for: .mute))
        return outcome
    }

    /// One press on the queue's device.
    private func run(_ action: VolumeAction) async -> VolumeOutcome {
        switch queueDevice {
        case .receiver: await runOnReceiver(action)
        case .cecReceiver: await runOnCECReceiver(action)
        case .tv: await runOnTV(action)
        }
    }

    /// The last known state for a press that didn't run (replaced, or an even number of Mutes).
    private func currentOutcome(for action: VolumeAction) -> VolumeOutcome {
        switch queueDevice {
        case .receiver: currentOutcome()
        case .cecReceiver, .tv: VolumeOutcome(route: queueDevice.route, feedback: .sentKeys, action: action)
        }
    }

    // MARK: Receiver (D44)

    /// Up/down step the receiver; mute sets it explicitly from the last known state (asked first when not known).
    private func runOnReceiver(_ action: VolumeAction) async -> VolumeOutcome {
        guard let receiver else { return notAnswering() }
        let command: ReceiverCommand
        switch action {
        case .up:
            // User decision: never above the cap. A brand that reports no dB (Onkyo) can't be capped; a cap between
            // two of the receiver's steps can be passed by less than one step.
            let cap = maxDB()
            if let dB = receiver.state.volume?.dB, dB >= cap {
                return VolumeOutcome(route: .receiver, feedback: .receiver(dB: dB, muted: receiver.state.muted), dB: dB,
                                     cappedAt: cap)
            }
            command = .volumeUp
        case .down:
            command = .volumeDown
        case .mute:
            if receiver.state.muted == nil, await request(.queryMute) == nil { return notAnswering() }
            command = .mute(!(receiver.state.muted ?? false))
        }
        guard await request(command) != nil else { return notAnswering() }
        return currentOutcome()
    }

    /// QA minor 3: a press waits `volumeReadyTimeout` for a connection, not the 5 s other commands may.
    private func request(_ command: ReceiverCommand) async -> ReceiverStatus? {
        await receiver?.request(command, readyTimeout: ReceiverController.volumeReadyTimeout)
    }

    /// The receiver's last known volume and mute.
    private func currentOutcome() -> VolumeOutcome {
        let dB = receiver?.state.volume?.dB
        return VolumeOutcome(route: .receiver, feedback: .receiver(dB: dB, muted: receiver?.state.muted), dB: dB)
    }

    private func notAnswering(route: VolumeRoute = .receiver) -> VolumeOutcome {
        Self.logger.notice("Receiver isn't answering; volume takes the next route until it does")
        return VolumeOutcome(route: route, feedback: .unavailable(Self.notAnsweringMessage))
    }

    // MARK: Step 9c: the receiver over HDMI-CEC, and the TV

    /// Pressed + Released, then the level when the receiver reports it. Maximum Volume doesn't apply (no dB).
    private func runOnCECReceiver(_ action: VolumeAction) async -> VolumeOutcome {
        guard let cecReceiver else { return notAnswering(route: .cecReceiver) }
        switch await cecReceiver.press(action) {
        case .notSent:
            return notAnswering(route: .cecReceiver)
        case .sent(let status):
            return VolumeOutcome(route: .cecReceiver,
                                 feedback: .percent(status?.volume, muted: status.map(\.muted)), action: action)
        }
    }

    private func runOnTV(_ action: VolumeAction) async -> VolumeOutcome {
        let result = await tv?.changeVolume(action) ?? .failed
        switch result {
        case .failed:
            Self.logger.notice("TV isn't answering; volume takes the next route until it does")
            return VolumeOutcome(route: .tv, feedback: .unavailable(Self.tvNotAnsweringMessage))
        case .sent:
            return VolumeOutcome(route: .tv, feedback: .sentKeys, action: action)
        case .level(let volume, let muted):
            return VolumeOutcome(route: .tv, feedback: .percent(volume, muted: muted), action: action)
        }
    }
}

private extension VolumeOutcome {
    /// The press on a device failed (receiver, CEC receiver or TV): the waiting presses end with it.
    var isNotAnswering: Bool {
        if case .unavailable = feedback { true } else { false }
    }
}
