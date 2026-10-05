/// Every input source is normalized into these commands by `InputRouter` (D3).
nonisolated enum RemoteCommand: Hashable, Sendable {
    case up, down, left, right, select, back, home, playPause
}
