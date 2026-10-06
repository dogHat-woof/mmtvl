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
        let source = makeSource()
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = []
            post(event)
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
