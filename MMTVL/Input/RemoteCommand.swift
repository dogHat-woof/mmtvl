/// Every input source is normalized into these commands by `InputRouter` (D3).
/// String-backed so `key-bindings.json` can name them.
nonisolated enum RemoteCommand: String, Codable, Hashable, Sendable, CaseIterable {
    case up, down, left, right, select, back, home, playPause, fastForward, rewind
}
