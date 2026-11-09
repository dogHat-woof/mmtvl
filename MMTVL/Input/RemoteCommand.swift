/// Every input source is normalized into these commands by `InputRouter` (D3).
/// String-backed so `key-bindings.json` can name them.
nonisolated enum RemoteCommand: String, Codable, Hashable, Sendable, CaseIterable {
    case up, down, left, right, select, back, home, playPause, fastForward, rewind
    /// M7 (D27). Keep this order: `allCases` is the order of Settings → Remote Buttons.
    case menu, channelUp, channelDown
    /// M7h L2: volume (receiver first, D44) and the power button (D45; `powerMenu` is a long press of Power).
    case volumeUp, volumeDown, mute, power, powerMenu

    /// Settings → Remote Buttons.
    var title: String {
        switch self {
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .select: "Select"
        case .back: "Back"
        case .home: "Home"
        case .playPause: "Play/Pause"
        case .fastForward: "Fast Forward"
        case .rewind: "Rewind"
        case .menu: "Menu"
        case .channelUp: "Channel Up"
        case .channelDown: "Channel Down"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .mute: "Mute"
        case .power: "Power"
        case .powerMenu: "Power Menu"
        }
    }
}
