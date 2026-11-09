/// The Siri Remote's bindable buttons (M7h L2, D43). Siri isn't one: it's reserved (double-press toggles trackpad mode, L5).
/// Raw values name them in `key-bindings.json`: `{"siriRemote":{"button":"tv"}}`.
nonisolated enum SiriRemoteButton: String, Codable, Hashable, Sendable, CaseIterable {
    case tv, back, playPause, volumeUp, volumeDown, mute, power, up, down, left, right, select

    /// HID usage pages the remote's buttons arrive on (M7e probe, confirmed seized on the mini in M7h step 1).
    static let consumerPage: UInt32 = 0x0C
    static let genericDesktopPage: UInt32 = 0x01

    /// The button for a HID element's usage page and usage; nil for anything else (Siri included).
    static func from(usagePage: UInt32, usage: UInt32) -> SiriRemoteButton? {
        switch (usagePage, usage) {
        case (consumerPage, 0x60): .tv
        case (genericDesktopPage, 0x86): .back
        case (consumerPage, 0xCD): .playPause
        case (consumerPage, 0xE9): .volumeUp
        case (consumerPage, 0xEA): .volumeDown
        case (consumerPage, 0xE2): .mute
        case (consumerPage, 0x30): .power
        case (consumerPage, 0x42): .up
        case (consumerPage, 0x43): .down
        case (consumerPage, 0x44): .left
        case (consumerPage, 0x45): .right
        case (consumerPage, 0x80): .select
        default: nil
        }
    }

    /// The Siri button (Consumer 0x04, 1 while held).
    static func isSiri(usagePage: UInt32, usage: UInt32) -> Bool {
        usagePage == consumerPage && usage == 0x04
    }
}
