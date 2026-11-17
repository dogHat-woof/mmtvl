import Foundation
import Libmpv

/// The demuxer cache sizes of a player: full screen or a Multiview window (M6 L6).
nonisolated enum BufferProfile: Sendable, Equatable {
    case full, tile
    /// Values for the mpv properties demuxer-max-back-bytes / demuxer-max-bytes.
    var backBytes: String { self == .full ? MPVOptions.backBuffer : MPVOptions.tileBackBuffer }
    var forwardBytes: String { self == .full ? MPVOptions.forwardBuffer : MPVOptions.tileForwardBuffer }
}

/// The mpv options for the Live TV players (D7, D22, M4 L8, M6 L6/L7).
nonisolated enum MPVOptions {
    static let backBuffer = "512MiB"
    static let forwardBuffer = "256MiB"
    /// About 5 minutes of rewind at 4 Mb/s per Multiview window (M6 L6).
    static let tileBackBuffer = "160MiB"
    static let tileForwardBuffer = "64MiB"

    /// MR step 2 (security review): none of mpv's built-in Lua scripts, no user scripts, no config files. Without a
    /// Lua state LuaJIT never generates code, so the hardened runtime needs no JIT exception. Names as mpv 0.41
    /// (MPVKit 1.0.0) takes them; `MPVScriptsOffTests` reads each back from a real core, since a renamed option is
    /// only logged by `MPVHandle` and would start Lua again (the process is then killed at core creation).
    static let scriptsOff: [(name: String, value: String)] = [
        ("config", "no"), ("ytdl", "no"), ("osc", "no"),
        ("load-stats-overlay", "no"), ("load-console", "no"), ("load-auto-profiles", "no"), ("load-select", "no"),
        ("load-positioning", "no"), ("load-commands", "no"), ("load-context-menu", "no"), ("load-scripts", "no"),
    ]

    /// Applied in order with mpv_set_option_string before mpv_initialize. A failing option is logged and skipped.
    static let all: [(name: String, value: String)] = [
        ("vo", "libmpv"), ("hwdec", "videotoolbox"),
    ] + scriptsOff + [
        ("input-default-bindings", "no"), ("input-media-keys", "no"), ("media-controls", "no"),
        ("idle", "yes"), ("keep-open", "no"),
        ("cache", "yes"), ("demuxer-max-bytes", forwardBuffer), ("demuxer-max-back-bytes", backBuffer),
        ("network-timeout", "15"),
        // M7c L29: one connection per HLS playlist; a second parallel one only adds a TLS handshake at start.
        ("demuxer-lavf-o", "http_multiple=0"),
        // M7n step 3a: warnings from every module, plus vo_libmpv's verbose lines (its render-stuck line), for
        // `logLevel` "terminal-default"; `MPVHandle` passes on only warnings, errors and that line.
        ("msg-level", messageLevels),
        // M7n step 4a: one frame per refresh, audio resampled to match; the rate is set per screen at runtime
        // (`display-fps-override`, `DisplayRefresh`), without which mpv falls back to audio timing.
        ("video-sync", "display-resample"),
        // M6 L7: render calls run on the main thread; don't block them for frame timing.
        ("video-timing-offset", "0"),
    ]

    /// M7n step 3a: the Live TV cores' `mpv_request_log_messages` level: the per-module levels of `msg-level`.
    static let logLevel = "terminal-default"
    static let messageLevels = "all=warn,vo/libmpv=v"
}

/// The `loadfile` command for a Live TV stream (M7j L6). mpv 0.38+ takes per-file options as the 4th argument, after
/// the index (-1 = none), and restores them when the file ends, so they never reach the next stream on the core.
nonisolated enum MPVLoadCommand {
    /// An antenna stream's per-file options. Constants only, never built from tuner data (security M2):
    /// - `deinterlace=auto`: ATSC 1.0 1080i is deinterlaced (`bwdif`), progressive frames are left alone.
    /// - `demuxer=lavf,demuxer-lavf-format=mpegts`: read as MPEG-TS only, so neither mpv's playlist demuxer nor
    ///   ffmpeg's HLS demuxer runs, and nothing a playlist names is fetched.
    /// - `stream-lavf-o=max_redirects=0`: ffmpeg's http protocol (FFmpeg 8.1.2 in MPVKit 1.0.0) follows no redirect.
    static let directOptions = "deinterlace=auto,demuxer=lavf,demuxer-lavf-format=mpegts,stream-lavf-o=max_redirects=0"

    static func make(url: URL, direct: Bool) -> [String] {
        direct ? ["loadfile", url.absoluteString, "replace", "-1", directOptions]
               : ["loadfile", url.absoluteString, "replace"]
    }
}

nonisolated enum LibraryVersions {
    /// `(major << 16) | minor`.
    static var mpvClientAPI: UInt { UInt(mpv_client_api_version()) }
}
