import Foundation

/// Rewind math from mpv's `demuxer-cache-state` (D7, L8).
nonisolated struct Timeshift: Equatable, Sendable {
    /// mpv plays 10–14 s behind cache-end; that counts as live.
    static let liveSlack: Double = 15
    /// Jump-to-live target below cache-end.
    static let liveOffset: Double = 10

    /// time-pos
    var position: Double
    /// Start of the seekable range containing position (else the smallest start).
    var rangeStart: Double
    /// "cache-end". Seek targets use it: mpv can't seek past what is cached.
    var cacheEnd: Double
    /// The live edge for display: `LiveEdgeSmoother`'s steady estimate, else cache-end.
    var liveEdge: Double

    init(position: Double, rangeStart: Double, cacheEnd: Double, liveEdge: Double? = nil) {
        self.position = position
        self.rangeStart = rangeStart
        self.cacheEnd = cacheEnd
        self.liveEdge = liveEdge ?? cacheEnd
    }

    var behindLive: Double { max(0, liveEdge - position - Self.liveSlack) }
    var isLive: Bool { behindLive < 1 }
    var buffered: Double { max(0, cacheEnd - rangeStart) }
    var livePosition: Double { cacheEnd - Self.liveOffset }

    /// position + delta, clamped to [rangeStart + 1, livePosition] (if that range is empty, livePosition).
    func target(seekingBy delta: Double) -> Double {
        let low = rangeStart + 1
        let high = livePosition
        guard low <= high else { return high }
        return min(max(position + delta, low), high)
    }

    /// nil when the JSON lacks cache-end or seekable-ranges is empty.
    static func parse(cacheStateJSON: String, timePos: Double) -> Timeshift? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(cacheStateJSON.utf8)) as? [String: Any],
              let cacheEnd = (object["cache-end"] as? NSNumber)?.doubleValue,
              let ranges = object["seekable-ranges"] as? [[String: Any]]
        else { return nil }
        let parsed: [(start: Double, end: Double)] = ranges.compactMap { range in
            guard let start = (range["start"] as? NSNumber)?.doubleValue,
                  let end = (range["end"] as? NSNumber)?.doubleValue
            else { return nil }
            return (start, end)
        }
        guard !parsed.isEmpty else { return nil }
        let containing = parsed.first { $0.start <= timePos && timePos <= $0.end }
        let rangeStart = containing?.start ?? parsed.map(\.start).min()!
        return Timeshift(position: timePos, rangeStart: rangeStart, cacheEnd: cacheEnd)
    }

    /// "LIVE" when isLive, else "−m:ss" (or "−h:mm:ss"), using U+2212 minus.
    var label: String {
        guard !isLive else { return "LIVE" }
        let total = Int(behindLive.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "\u{2212}%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "\u{2212}%d:%02d", minutes, seconds)
    }
}
