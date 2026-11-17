import Foundation

/// M7n step 3a: the full-screen player's playback statistics, one notice line every `PlaybackStats.period` (category
/// `MPV`). Numbers and mpv's decoder name only, never a URL, host, token or title.
nonisolated enum PlaybackStats {
    static let period: TimeInterval = 10
    /// A render call longer than this counts as slow (a 60 Hz frame is 16.7 ms).
    static let slowRenderNanos: UInt64 = 12_000_000

    /// mpv's counters; nil when mpv doesn't report one.
    struct Counters: Equatable, Sendable {
        var frameDrops: Int64?
        var decoderFrameDrops: Int64?
        var delayedFrames: Int64?
        var mistimedFrames: Int64?
    }

    /// One reading of mpv's properties.
    struct Sample: Equatable, Sendable {
        var decoder: String?
        /// `container-fps`: the stream's rate.
        var containerFPS: Double?
        /// `estimated-vf-fps`: the rate after the filters (bwdif makes 29.97 fps 1080i 59.94).
        var filteredFPS: Double?
        var counters = Counters()
        var avsync: Double?
        var displayFPS: Double?
    }

    /// The draws of `MPVVideoLayer` in one period: how many, the longest `mpv_render_context_render` call, how many
    /// took longer than `slowRenderNanos`; how many update callbacks mpv made (a new frame to draw), the longest wait
    /// from a callback to the draw after it, and the longest gap between two draws (the visible stutter).
    struct RenderTimings: Equatable, Sendable {
        var draws = 0
        var longestNanos: UInt64 = 0
        var slowDraws = 0
        var updates = 0
        var longestUpdateToDrawNanos: UInt64 = 0
        var longestDrawGapNanos: UInt64 = 0

        mutating func record(nanos: UInt64) {
            draws += 1
            if nanos > longestNanos { longestNanos = nanos }
            if nanos > PlaybackStats.slowRenderNanos { slowDraws += 1 }
        }
    }

    /// The layer's recorder, behind its lock: mpv's update callback (on mpv's thread) and `draw` (on main) feed it,
    /// the stats timer takes a period's timings. Times are `CLOCK_UPTIME_RAW` nanoseconds.
    struct RenderRecorder: Equatable, Sendable {
        var timings = RenderTimings()
        /// The first update callback not yet followed by a draw.
        var pendingUpdateSince: UInt64?
        var lastDrawAt: UInt64?

        /// mpv's render update callback: a frame (or redraw) is ready.
        mutating func update(at now: UInt64) {
            timings.updates += 1
            if pendingUpdateSince == nil { pendingUpdateSince = now }
        }

        /// A draw that rendered, started at `start`, whose render call took `renderNanos`.
        mutating func draw(at start: UInt64, renderNanos: UInt64) {
            timings.record(nanos: renderNanos)
            if let pending = pendingUpdateSince {
                timings.longestUpdateToDrawNanos = max(timings.longestUpdateToDrawNanos, start &- min(pending, start))
                pendingUpdateSince = nil
            }
            if let last = lastDrawAt {
                timings.longestDrawGapNanos = max(timings.longestDrawGapNanos, start &- min(last, start))
            }
            lastDrawAt = start
        }

        /// The period's timings, and a new period. `restart` (a new stats period: a load, a seek) also forgets the
        /// last draw, so the gap across the restart isn't counted.
        mutating func take(restart: Bool) -> RenderTimings {
            defer {
                timings = RenderTimings()
                if restart { lastDrawAt = nil }
            }
            return timings
        }
    }

    /// vo_libmpv's render-stuck lines (`MPVLogText.renderStuckText`), up to ~5 a second while draws stall: counted
    /// for the stats line; only the first of each load is logged.
    struct RenderStuckCounter: Equatable, Sendable {
        private(set) var count = 0
        private var logged = false

        /// One line; true when it's the first of the load (log it).
        mutating func note() -> Bool {
            count += 1
            defer { logged = true }
            return !logged
        }

        /// A new load: its first line is logged again. The count runs on until `take`.
        mutating func newLoad() { logged = false }

        /// The count since the last take, for the stats line.
        mutating func take() -> Int {
            defer { count = 0 }
            return count
        }
    }

    /// The growth of a counter since the last line. A counter that went down (mpv reset it for a new file) counts
    /// from zero.
    static func delta(_ current: Int64?, since previous: Int64?) -> Int64? {
        guard let current else { return nil }
        guard let previous, current >= previous else { return current }
        return current - previous
    }

    /// "Stats (player 1): decoder videotoolbox, 59.94 fps, filtered 59.94 fps, dropped 0, decoder dropped 0,
    /// delayed 3, mistimed 0, avsync -0.012 s, display 60.00 fps, 600 updates, 598 draws, 0 stuck, longest render
    /// 9.8 ms, 2 over 12 ms, longest update to draw 4.1 ms, longest gap 33.4 ms". `stuck`: mpv's "mpv_render_context_render()
    /// not being called or stuck" lines in the period (its video output gave up waiting for a draw, ~0.2 s each).
    /// Unknown values are "?"; the display rate only when mpv reports one.
    static func line(player: Int, sample: Sample, previous: Counters, render: RenderTimings, stuck: Int) -> String {
        func count(_ current: Int64?, _ last: Int64?) -> String { delta(current, since: last).map { "\($0)" } ?? "?" }
        func rate(_ fps: Double?) -> String { fps.map { String(format: "%.2f fps", $0) } ?? "? fps" }
        func ms(_ nanos: UInt64) -> String { String(format: "%.1f ms", Double(nanos) / 1_000_000) }
        let avsync = sample.avsync.map { String(format: "%.3f s", $0) } ?? "?"
        let display = sample.displayFPS.map { String(format: ", display %.2f fps", $0) } ?? ""
        let c = sample.counters, p = previous
        return "Stats (player \(player)): decoder \(sample.decoder ?? "?"), \(rate(sample.containerFPS))"
            + ", filtered \(rate(sample.filteredFPS))"
            + ", dropped \(count(c.frameDrops, p.frameDrops))"
            + ", decoder dropped \(count(c.decoderFrameDrops, p.decoderFrameDrops))"
            + ", delayed \(count(c.delayedFrames, p.delayedFrames))"
            + ", mistimed \(count(c.mistimedFrames, p.mistimedFrames))"
            + ", avsync \(avsync)\(display)"
            + ", \(render.updates) updates, \(render.draws) draws, \(stuck) stuck"
            + ", longest render \(ms(render.longestNanos))"
            + ", \(render.slowDraws) over 12 ms, longest update to draw \(ms(render.longestUpdateToDrawNanos))"
            + ", longest gap \(ms(render.longestDrawGapNanos))"
    }

    /// Reads mpv's properties. Off the main thread: a property read waits for mpv's core.
    static func read(_ mpv: MPVHandle) -> Sample {
        Sample(decoder: mpv.string("hwdec-current"),
               containerFPS: mpv.double("container-fps"),
               filteredFPS: mpv.double("estimated-vf-fps"),
               counters: Counters(frameDrops: mpv.int64("frame-drop-count"),
                                  decoderFrameDrops: mpv.int64("decoder-frame-drop-count"),
                                  delayedFrames: mpv.int64("vo-delayed-frame-count"),
                                  mistimedFrames: mpv.int64("mistimed-frame-count")),
               avsync: mpv.double("avsync"),
               displayFPS: mpv.double("display-fps").flatMap { $0.isFinite && $0 > 0 ? $0 : nil })
    }
}
