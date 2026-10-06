import AppKit
import AudioToolbox
import CoreAudio
import os

/// `settings.json` `phoneRemoteVolume` (L8). Unknown values read as `.auto`.
nonisolated enum VolumeMode: String, Sendable { case auto, keys, system, app }

/// Where a phone volume button goes (D25).
nonisolated enum VolumeRoute: Equatable, Sendable { case keys, system, app, unavailable }

extension VolumeRoute {
    /// L8. auto: SoundSource → keys; settable → system; active → app; else unavailable.
    static func choose(mode: VolumeMode, soundSourceRunning: Bool, systemSettable: Bool, launcherActive: Bool) -> VolumeRoute {
        switch mode {
        case .auto:
            if soundSourceRunning { return .keys }
            if systemSettable { return .system }
            return launcherActive ? .app : .unavailable
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
    case sentKeys
    case unavailable(String)
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

/// Performs phone volume buttons on the route chosen by `VolumeRoute.choose` (D25, L8).
final class VolumeController {
    static let soundSourceBundleID = "com.rogueamoeba.soundsource"
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "PhoneRemote")

    private let mode: () -> VolumeMode
    private let isLauncherActive: () -> Bool
    private let applyAppVolume: (AppVolume) -> Void
    private(set) var appVolume = AppVolume()

    init(mode: @escaping () -> VolumeMode, isLauncherActive: @escaping () -> Bool,
         applyAppVolume: @escaping (AppVolume) -> Void) {
        self.mode = mode
        self.isLauncherActive = isLauncherActive
        self.applyAppVolume = applyAppVolume
    }

    func perform(_ action: VolumeAction) -> VolumeFeedback {
        let soundSourceRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == Self.soundSourceBundleID
        }
        let route = VolumeRoute.choose(mode: mode(), soundSourceRunning: soundSourceRunning,
                                       systemSettable: SystemVolume.isSettable, launcherActive: isLauncherActive())
        Self.logger.info("Volume \(action.rawValue, privacy: .public) via \(String(describing: route), privacy: .public)")

        switch route {
        case .keys:
            guard SyntheticInput.canPost else { return .unavailable("Allow Accessibility for MMTVL on the Mac") }
            let key: Int32 = switch action {
            case .up: SyntheticInput.NXKey.soundUp
            case .down: SyntheticInput.NXKey.soundDown
            case .mute: SyntheticInput.NXKey.mute
            }
            SyntheticInput.postMediaKey(key)
            return .sentKeys

        case .system:
            switch action {
            case .up, .down:
                SystemVolume.setLevel(SystemVolume.step(SystemVolume.level() ?? 0.5, action))
                SystemVolume.setMuted(false)
            case .mute:
                SystemVolume.setMuted(!(SystemVolume.isMuted() ?? false))
            }
            return .level(Double(SystemVolume.level() ?? 0), muted: SystemVolume.isMuted() ?? false)

        case .app:
            appVolume.apply(action)
            applyAppVolume(appVolume)
            return .level(Double(appVolume.level) / 100, muted: appVolume.muted)

        case .unavailable:
            return .unavailable("Volume can't be changed here")
        }
    }
}
