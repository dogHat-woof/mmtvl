import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// Posts tagged synthetic events (L6). Needs post-event access (the Accessibility grant, D4).
nonisolated enum SyntheticInput {
    /// "MMTVL" in ASCII; stored in kCGEventSourceUserData of every event we post.
    static let marker: Int64 = 0x4D4D54564C

    /// NX_KEYTYPE_* (ev_keymap.h).
    enum NXKey {
        static let soundUp: Int32 = 0, soundDown: Int32 = 1, mute: Int32 = 7
        static let play: Int32 = 16, next: Int32 = 17, previous: Int32 = 18
    }

    /// NX_SUBTYPE_AUX_CONTROL_BUTTONS.
    private static let auxControlButtonsSubtype: Int16 = 8

    /// CGPreflightPostEventAccess().
    static var canPost: Bool { CGPreflightPostEventAccess() }

    /// CGRequestPostEventAccess(); shows the system prompt once.
    static func requestAccess() {
        _ = CGRequestPostEventAccess()
    }

    /// True for events this process posted: userData == marker, or source PID == our PID.
    static func isOwn(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
            || event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid())
    }

    /// keyDown + keyUp with no modifier flags.
    static func postKey(_ keyCode: CGKeyCode) {
        postKey(keyCode, flags: [])
    }

    /// keyDown + keyUp with `flags` (e.g. `.maskCommand`, M7b L21). With `pid`, posted to that app only.
    static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags, toPid pid: pid_t? = nil) {
        let source = makeSource()
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = flags
            if let pid {
                event.setIntegerValueField(.eventSourceUserData, value: marker)
                event.postToPid(pid)
            } else {
                post(event)
            }
        }
    }

    /// System-defined subtype 8, down then up (Hammerspoon recipe; see the M5 plan's Research).
    static func postMediaKey(_ key: Int32) {
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state) << 8),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: auxControlButtonsSubtype,
                data1: (Int(key) << 16) | (state << 8),
                data2: -1
            )?.cgEvent else { continue }
            post(event)
        }
    }

    /// Text in ≤ 20-UTF-16-unit chunks: per chunk, virtualKey 0 keyDown with the Unicode string, then keyUp.
    static func type(_ text: String) {
        let source = makeSource()
        for chunk in chunks(text) {
            let utf16 = Array(chunk.utf16)
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                post(event)
            }
        }
    }

    /// `count` × postKey(kVK_Delete).
    static func deleteBackward(_ count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            postKey(CGKeyCode(kVK_Delete))
        }
    }

    // MARK: Mouse (M7b phone trackpad, L12)

    /// The current pointer position (global, top-left origin).
    static var pointerLocation: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// The active displays' bounds, in the same coordinate space as `pointerLocation`.
    static func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return displays.prefix(Int(count)).map(CGDisplayBounds)
    }

    static func movePointer(to point: CGPoint, delta: CGVector) {
        // M7h security: never post (or convert) a non-finite position.
        guard point.x.isFinite, point.y.isFinite,
              let event = CGEvent(mouseEventSource: makeSource(), mouseType: .mouseMoved,
                                  mouseCursorPosition: point, mouseButton: .left)
        else { return }
        event.setIntegerValueField(.mouseEventDeltaX, value: PointerMath.eventDelta(delta.dx))
        event.setIntegerValueField(.mouseEventDeltaY, value: PointerMath.eventDelta(delta.dy))
        post(event)
    }

    /// Down then up at `point`; `clickCount` 2/3 makes double/triple clicks.
    static func click(_ button: PointerButton, at point: CGPoint, clickCount: Int64) {
        let source = makeSource()
        let types: [CGEventType] = button == .left ? [.leftMouseDown, .leftMouseUp] : [.rightMouseDown, .rightMouseUp]
        let mouseButton: CGMouseButton = button == .left ? .left : .right
        for type in types {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point,
                                      mouseButton: mouseButton)
            else { continue }
            event.setIntegerValueField(.mouseEventClickState, value: clickCount)
            post(event)
        }
    }

    /// Pixel scrolling; positive wheel1 scrolls up (content moves down).
    static func scroll(wheel1: Int32, wheel2: Int32) {
        guard wheel1 != 0 || wheel2 != 0,
              let event = CGEvent(scrollWheelEvent2Source: makeSource(), units: .pixel, wheelCount: 2,
                                  wheel1: wheel1, wheel2: wheel2, wheel3: 0)
        else { return }
        post(event)
    }

    /// Splits at Character boundaries, each chunk's utf16.count ≤ maxUTF16.
    /// A single Character longer than maxUTF16 (rare emoji sequences) becomes its own chunk.
    static func chunks(_ text: String, maxUTF16: Int = 20) -> [String] {
        var result: [String] = []
        var current = ""
        var currentCount = 0
        for character in text {
            let count = character.utf16.count
            if currentCount > 0 && currentCount + count > maxUTF16 {
                result.append(current)
                current = ""
                currentCount = 0
            }
            current.append(character)
            currentCount += count
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func makeSource() -> CGEventSource? {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.userData = marker
        return source
    }

    private static func post(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cghidEventTap)
    }
}
