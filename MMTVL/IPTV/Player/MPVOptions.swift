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

    /// Applied in order with mpv_set_option_string before mpv_initialize. A failing option is logged and skipped.
    static let all: [(name: String, value: String)] = [
        ("vo", "libmpv"), ("hwdec", "videotoolbox"), ("ytdl", "no"),
        ("input-default-bindings", "no"), ("input-media-keys", "no"), ("media-controls", "no"),
        ("idle", "yes"), ("keep-open", "no"),
        ("cache", "yes"), ("demuxer-max-bytes", forwardBuffer), ("demuxer-max-back-bytes", backBuffer),
        ("network-timeout", "15"),
        // M7c L29: one connection per HLS playlist; a second parallel one only adds a TLS handshake at start.
        ("demuxer-lavf-o", "http_multiple=0"),
        // M6 L7: render calls run on the main thread; don't block them for frame timing.
        ("video-timing-offset", "0"),
    ]
}

nonisolated enum LibraryVersions {
    /// `(major << 16) | minor`.
    static var mpvClientAPI: UInt { UInt(mpv_client_api_version()) }
}
