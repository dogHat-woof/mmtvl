import AppKit
import CoreGraphics
import os

/// Sendable data pulled out of a `CGEvent` inside the tap callback.
nonisolated enum TapEvent: Sendable {
    case key(code: UInt16, flags: UInt64, isRepeat: Bool)
    case media(subtype: Int16, data1: Int)
    case disabled
    case other
}

/// NX_SYSDEFINED, the CG event type of media keys.
nonisolated private let systemDefinedEventType = CGEventType(rawValue: 14)!

/// C callback: can't capture context or be actor-isolated. It runs on the main run loop.
nonisolated private func globalEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    // L6: our own synthetic events pass through untouched.
    if SyntheticInput.isOwn(event) { return Unmanaged.passUnretained(event) }

    let tapEvent: TapEvent
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        tapEvent = .disabled
    case .keyDown:
        tapEvent = .key(
            code: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
            flags: event.flags.rawValue,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        )
    case systemDefinedEventType:
        if let nsEvent = NSEvent(cgEvent: event) {
            tapEvent = .media(subtype: nsEvent.subtype.rawValue, data1: nsEvent.data1)
        } else {
            tapEvent = .other
        }
    default:
        tapEvent = .other
    }

    let tap = Unmanaged<GlobalEventTap>.fromOpaque(userInfo).takeUnretainedValue()
    let consume = MainActor.assumeIsolated { tap.decide(tapEvent) }
    return consume ? nil : Unmanaged.passUnretained(event)
}

/// The one active event tap (D17): consumes global bindings (Home) always, and media keys
/// only while the launcher is frontmost. Requires Accessibility (D4). Never logs keys (L6).
final class GlobalEventTap {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "GlobalEventTap")

    private let inputRouter: InputRouter
    private var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(inputRouter: InputRouter) {
        self.inputRouter = inputRouter
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
            if inputRouter.captureHandler != nil && NSApp.isActive {
                // M7 L8: learning a button. ⌘-combos pass through; repeats are swallowed.
                if modifiers.contains(.command) { return false }
                if !isRepeat {
                    let trigger = InputBinding.Trigger.key(keyCode: code, modifiers: Array(modifiers)).normalized
                    DispatchQueue.main.async { [inputRouter] in inputRouter.capture(trigger) }
                }
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
            if inputRouter.captureHandler != nil && NSApp.isActive,
               let parsed = MediaKeyEvent.parse(subtype: subtype, data1: data1) {
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

        case .other:
            return false
        }
    }
}
