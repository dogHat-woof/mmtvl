/// Turns analog stick samples into a held direction, with hysteresis so it doesn't flicker.
nonisolated enum ThumbstickDirection {
    static let pressThreshold: Float = 0.6
    static let releaseThreshold: Float = 0.3

    /// Direction held after this sample. Keeps `current` while its axis magnitude is ≥ releaseThreshold
    /// (in the same sign). Otherwise picks the dominant axis if its magnitude is ≥ pressThreshold.
    /// y > 0 = up, x > 0 = right.
    static func resolve(x: Float, y: Float, current: RemoteCommand?) -> RemoteCommand? {
        switch current {
        case .right where x >= releaseThreshold: return .right
        case .left where x <= -releaseThreshold: return .left
        case .up where y >= releaseThreshold: return .up
        case .down where y <= -releaseThreshold: return .down
        default: break
        }
        if abs(x) >= abs(y) {
            guard abs(x) >= pressThreshold else { return nil }
            return x > 0 ? .right : .left
        } else {
            guard abs(y) >= pressThreshold else { return nil }
            return y > 0 ? .up : .down
        }
    }
}
