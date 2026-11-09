/// Parses system-defined (NX_SYSDEFINED) media key events.
nonisolated enum MediaKeyEvent {
    struct Parsed: Equatable, Sendable {
        var key: MediaKey
        var isKeyDown: Bool
        var isRepeat: Bool
    }

    /// NX_SUBTYPE_AUX_CONTROL_BUTTONS
    static let auxControlButtonsSubtype: Int16 = 8

    /// nil unless subtype == 8 and the key code is PLAY(16)/NEXT(17)/PREVIOUS(18)/FAST(19)/REWIND(20).
    /// Volume/mute/brightness return nil, so they pass through.
    static func parse(subtype: Int16, data1: Int) -> Parsed? {
        guard subtype == auxControlButtonsSubtype else { return nil }
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyState = (data1 & 0xFF00) >> 8
        let key: MediaKey
        switch keyCode {
        case 16: key = .playPause     // NX_KEYTYPE_PLAY
        case 17: key = .next          // NX_KEYTYPE_NEXT
        case 18: key = .previous      // NX_KEYTYPE_PREVIOUS
        case 19: key = .fastForward   // NX_KEYTYPE_FAST
        case 20: key = .rewind        // NX_KEYTYPE_REWIND
        default: return nil
        }
        return Parsed(key: key, isKeyDown: keyState == 0xA, isRepeat: data1 & 0x1 != 0)
    }

    /// M7h L3a: a volume key, for the event tap's volume path only (`parse` still returns nil for these).
    struct Volume: Equatable, Sendable {
        var action: VolumeAction
        var isKeyDown: Bool
        var isRepeat: Bool
    }

    /// nil unless subtype == 8 and the key code is SOUND_UP(0)/SOUND_DOWN(1)/MUTE(7).
    static func parseVolume(subtype: Int16, data1: Int) -> Volume? {
        guard subtype == auxControlButtonsSubtype else { return nil }
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyState = (data1 & 0xFF00) >> 8
        let action: VolumeAction
        switch keyCode {
        case 0: action = .up      // NX_KEYTYPE_SOUND_UP
        case 1: action = .down    // NX_KEYTYPE_SOUND_DOWN
        case 7: action = .mute    // NX_KEYTYPE_MUTE
        default: return nil
        }
        return Volume(action: action, isKeyDown: keyState == 0xA, isRepeat: data1 & 0x1 != 0)
    }
}
