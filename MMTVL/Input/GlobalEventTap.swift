import AppKit
import CoreGraphics
import os

/// Sendable data pulled out of a `CGEvent` inside the tap callback.
nonisolated enum TapEvent: Equatable, Sendable {
    case key(code: UInt16, flags: UInt64, isRepeat: Bool)
    case media(subtype: Int16, data1: Int)
    /// L6: posted by MMTVL itself (`SyntheticInput.isOwn`, e.g. the `keys` volume route's keys): always passed
    /// through untouched.
    case own
    case disabled
    case other
}

/// NX_SYSDEFINED, the CG event type of media keys.
nonisolated private let systemDefinedEventType = CGEventType(rawValue: 14)!

extension TapEvent {
    nonisolated init(type: CGEventType, event: CGEvent) {
        if SyntheticInput.isOwn(event) {
            self = .own
            return
        }
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            self = .disabled
        case .keyDown:
            self = .key(
                code: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
                flags: event.flags.rawValue,
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            )
        case systemDefinedEventType:
            if let nsEvent = NSEvent(cgEvent: event) {
                self = .media(subtype: nsEvent.subtype.rawValue, data1: nsEvent.data1)
            } else {
                self = .other
            }
        default:
            self = .other
        }
    }
}

/// M7h L3a: what the tap does with a volume key.
nonisolated enum VolumeKeyDecision: Equatable, Sendable {
    /// macOS (or the app in front) handles it.
    case passThrough
    /// Taken; `perform` is the action to run (nil for a key-up, or a held Mute's repeat).
    case consume(perform: VolumeAction?)

    /// Consumed only while the volume route is the receiver (`routeReady`) and the tap runs in kiosk mode
    /// (`-windowed` has no tap; never taken there). Up/down act on key-down and repeats, mute on key-down only.
    static func decide(_ key: MediaKeyEvent.Volume, routeReady: Bool, isWindowed: Bool) -> VolumeKeyDecision {
        guard routeReady, !isWindowed else { return .passThrough }
        guard key.isKeyDown, !(key.action == .mute && key.isRepeat) else { return .consume(perform: nil) }
        return .consume(perform: key.action)
    }
}

/// M7h L3a (QA minor 4): a held volume key goes one way. Its key-down is decided (`VolumeKeyDecision`); its repeats
/// and key-up follow that, even if the receiver's readiness changes while it's held (so macOS never gets a key-up
/// without its key-down, or the reverse). QA minor 3: once the receiver isn't ready during a taken hold, the rest of
/// its repeats are dropped (consumed, no action) instead of going to another route; the next key-down decides again.
nonisolated struct VolumeKeyTracker: Equatable, Sendable {
    /// Keys whose key-down was taken and that aren't released yet.
    private(set) var taken: Set<VolumeAction> = []
    /// Taken keys whose repeats are dropped until the key-up.
    private(set) var dropping: Set<VolumeAction> = []

    /// `routeReady` is asked for a new key-down and for the repeats of a taken one, never for a key-up.
    mutating func decide(_ key: MediaKeyEvent.Volume, routeReady: () -> Bool, isWindowed: Bool) -> VolumeKeyDecision {
        if !key.isKeyDown {
            dropping.remove(key.action)
            return taken.remove(key.action) != nil ? .consume(perform: nil) : .passThrough
        }
        if key.isRepeat {
            guard taken.contains(key.action) else { return .passThrough }
            if key.action == .mute || dropping.contains(key.action) { return .consume(perform: nil) }
            guard routeReady() else {
                dropping.insert(key.action)
                return .consume(perform: nil)
            }
            return .consume(perform: key.action)
        }
        dropping.remove(key.action)
        let decision = VolumeKeyDecision.decide(key, routeReady: routeReady(), isWindowed: isWindowed)
        if decision == .passThrough { taken.remove(key.action) } else { taken.insert(key.action) }
        return decision
    }
}

/// C callback: can't capture context or be actor-isolated. It runs on the main run loop.
nonisolated private func globalEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tapEvent = TapEvent(type: type, event: event)
    // L6: our own synthetic events pass through untouched.
    if tapEvent == .own { return Unmanaged.passUnretained(event) }

    let tap = Unmanaged<GlobalEventTap>.fromOpaque(userInfo).takeUnretainedValue()
    let consume = MainActor.assumeIsolated { tap.decide(tapEvent) }
    return consume ? nil : Unmanaged.passUnretained(event)
}

/// The one active event tap (D17): consumes global bindings (Home) always, media keys only while the launcher is
/// frontmost, and (M7h L3a) the volume keys from any app while they go to the receiver. Requires Accessibility
/// (D4). Never logs keys (L6), except the volume keys it takes (which key, not a code).
final class GlobalEventTap {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "GlobalEventTap")
    private static let inputLogger = Logger(subsystem: "dev.mmtvl.launcher", category: "Input")

    private let inputRouter: InputRouter
    private let isWindowed: Bool
    private var volumeKeys = VolumeKeyTracker()
    private var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// M7c L8a: the kiosk lock is on (set by AppDelegate).
    var lockActive: () -> Bool = { false }
    /// M7h L3a: the volume keys go to the receiver now (`VolumeController.consumesVolumeKeys`; set by AppDelegate).
    var volumeKeysConsumed: () -> Bool = { false }
    /// M7h L3a: a taken volume key's action, on the main actor (`VolumeController.perform`, with the toast).
    var onVolume: (VolumeAction) -> Void = { _ in }
    /// Runs `onVolume` after the tap callback returns (tests run it at once).
    var schedule: (@escaping @MainActor @Sendable () -> Void) -> Void = { work in DispatchQueue.main.async(execute: work) }

    init(inputRouter: InputRouter, isWindowed: Bool = AppEnvironment.windowedMode) {
        self.inputRouter = inputRouter
        self.isWindowed = isWindowed
    }

    var isRunning: Bool {
        guard let port else { return false }
        return CGEvent.tapIsEnabled(tap: port)
    }

    /// Returns false if the tap can't be created (Accessibility not granted).
    @discardableResult
    func start() -> Bool {
        if port != nil {
            ensureEnabled()
            return true
        }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << systemDefinedEventType.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: globalEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Self.logger.error("Event tap could not be created (Accessibility not granted?)")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        runLoopSource = source
        Self.logger.info("Event tap started")
        return true
    }

    func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFMachPortInvalidate(port)
        self.port = nil
        runLoopSource = nil
    }

    /// Settings → Remote Buttons is learning a button and MMTVL is in front (`InputRouter.isActive`).
    private var isLearning: Bool {
        inputRouter.captureHandler != nil && inputRouter.isActive()
    }

    /// Re-enables the tap if the system disabled it (e.g. across sleep).
    func ensureEnabled() {
        guard let port, !CGEvent.tapIsEnabled(tap: port) else { return }
        Self.logger.info("Re-enabling event tap")
        CGEvent.tapEnable(tap: port, enable: true)
    }

    /// Returns true to consume the event. Must stay fast; real work is dispatched async.
    func decide(_ event: TapEvent) -> Bool {
        switch event {
        case .disabled:
            Self.logger.info("Event tap was disabled by the system; re-enabling")
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false

        case .key(let code, let flags, let isRepeat):
            let modifiers = KeyModifier.set(from: CGEventFlags(rawValue: flags))
            if isLearning {
                // M7 L8: learning a button. ⌘-combos pass through; repeats are swallowed.
                if modifiers.contains(.command) { return false }
                if !isRepeat {
                    let trigger = InputBinding.Trigger.key(keyCode: code, modifiers: Array(modifiers)).normalized
                    DispatchQueue.main.async { [inputRouter] in inputRouter.capture(trigger) }
                }
                return true
            }
            // M7c L8a: with another app in front, ⌘Tab and friends never reach the system. While MMTVL is active
            // the presentation options do this, and ⌘Q/⌘W must still reach MMTVL.
            if !NSApp.isActive && lockActive() && KioskLock.blocks(keyCode: code, modifiers: modifiers) {
                return true
            }
            // Non-global keys pass through; the local monitor handles them while we're active.
            guard let binding = inputRouter.bindings.binding(keyCode: code, modifiers: modifiers),
                  binding.isGlobal
            else { return false }
            if !isRepeat {
                let command = binding.command
                DispatchQueue.main.async { [inputRouter] in
                    inputRouter.dispatch(command, isGlobal: true)
                }
            }
            return true

        case .media(let subtype, let data1):
            // L3a: the volume keys first, from any app. Security low (pre-build 2): while Settings learns a button,
            // a new volume press never goes to the receiver (the learning capture comes first); a held one finishes
            // the way it started.
            if let volume = MediaKeyEvent.parseVolume(subtype: subtype, data1: data1) {
                let consumed: () -> Bool = isLearning ? { false } : volumeKeysConsumed
                switch volumeKeys.decide(volume, routeReady: consumed, isWindowed: isWindowed) {
                case .passThrough:
                    return false
                case .consume(let action):
                    if let action {
                        if !volume.isRepeat {
                            Self.inputLogger.info("Volume key \(action.rawValue, privacy: .public) → receiver")
                        }
                        schedule { [weak self] in self?.onVolume(action) }
                    }
                    return true
                }
            }
            if isLearning, let parsed = MediaKeyEvent.parse(subtype: subtype, data1: data1) {
                if parsed.isKeyDown && !parsed.isRepeat {
                    DispatchQueue.main.async { [inputRouter] in inputRouter.capture(.media(key: parsed.key)) }
                }
                return true
            }
            guard NSApp.isActive,
                  let parsed = MediaKeyEvent.parse(subtype: subtype, data1: data1),
                  let binding = inputRouter.bindings.binding(media: parsed.key)
            else { return false }
            if parsed.isKeyDown && !parsed.isRepeat {
                let command = binding.command
                let isGlobal = binding.isGlobal
                DispatchQueue.main.async { [inputRouter] in
                    inputRouter.dispatch(command, isGlobal: isGlobal)
                }
            }
            return true

        case .own, .other:
            return false
        }
    }
}
