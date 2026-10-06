import Foundation

/// Steadies the live edge for the behind-live display.
///
/// mpv's cache-end jumps forward by a whole HLS segment (about 4 s) each time one downloads, while the playhead moves
/// smoothly. Raw `cache-end − position` is therefore a sawtooth, and the "−m:ss" badge counted down for a few seconds
/// and jumped back. The live edge advances in real time, so this tracks the most recent peak of `cache-end − now`
/// and moves the edge with the clock in between. While playing, the reported lag (edge − position) also ignores
/// changes under `hysteresis`, so segment and poll jitter never flip the label between two seconds.
nonisolated struct LiveEdgeSmoother: Sendable {
    /// Longer than a segment, so a peak is always in the window.
    static let window: TimeInterval = 12
    static let hysteresis: Double = 0.75

    private var peaks: [(time: TimeInterval, offset: Double)] = []
    private var reportedLag: Double?

    /// A new stream: its timeline starts over.
    mutating func reset() {
        peaks = []
        reportedLag = nil
    }

    /// `now` is a monotonic clock in seconds. `steady` is true while playing at normal speed; while paused the lag
    /// grows every second and is reported as is.
    mutating func liveEdge(cacheEnd: Double, position: Double, now: TimeInterval, steady: Bool) -> Double {
        peaks.append((now, cacheEnd - now))
        peaks.removeAll { now - $0.time > Self.window }
        let edge = now + (peaks.map(\.offset).max() ?? cacheEnd - now)
        let lag = edge - position
        if steady, let reportedLag, abs(lag - reportedLag) < Self.hysteresis {
            return position + reportedLag
        }
        reportedLag = lag
        return edge
    }
}
