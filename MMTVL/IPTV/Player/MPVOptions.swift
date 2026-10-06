import Libmpv

/// The mpv options for the Live TV player (D7, D22, L8).
nonisolated enum MPVOptions {
    static let backBuffer = "512MiB"
    static let forwardBuffer = "256MiB"

    /// Applied in order with mpv_set_option_string before mpv_initialize. A failing option is logged and skipped.
    static let all: [(name: String, value: String)] = [
        ("vo", "libmpv"), ("hwdec", "videotoolbox"), ("ytdl", "no"),
        ("input-default-bindings", "no"), ("input-media-keys", "no"), ("media-controls", "no"),
        ("idle", "yes"), ("keep-open", "no"),
        ("cache", "yes"), ("demuxer-max-bytes", forwardBuffer), ("demuxer-max-back-bytes", backBuffer),
        ("network-timeout", "15"),
    ]
}

nonisolated enum LibraryVersions {
    /// `(major << 16) | minor`.
    static var mpvClientAPI: UInt { UInt(mpv_client_api_version()) }
}
