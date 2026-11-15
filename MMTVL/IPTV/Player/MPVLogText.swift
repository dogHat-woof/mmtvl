import Foundation

/// mpv's log lines (M7j L15, L9): what may be logged of them, and the HTTP status a failed load reported.
nonisolated enum MPVLogText {
    /// Replaces every URL (`<scheme>://…` up to whitespace) with "<url>": playlist stream URLs carry the account's
    /// token, and antenna stream URLs (and ffmpeg's `tcp://` lines) the tuner's address.
    static func redacted(_ text: String) -> String {
        text.replacing(/[A-Za-z][A-Za-z0-9+.\-]*:\/\/\S+/, with: "<url>")
    }

    /// The status in ffmpeg's "HTTP error 503 Service Unavailable" line, else nil.
    static func httpStatus(in text: String) -> Int? {
        guard let match = text.firstMatch(of: /HTTP error ([0-9]{3})/) else { return nil }
        return Int(match.1)
    }

    /// What ffmpeg's video decoders say about a stream joined mid-GOP (strings from MPVKit 1.0.0's libavcodec,
    /// FFmpeg n8.1.2), lowercased. An antenna MPEG-2 stream logs ~100 "Invalid frame dimensions 0x0." per zap.
    private static let decoderNoise = [
        "invalid frame dimensions",
        "ac-tex damaged",
        "warning mvs not available",
        "concealing ",
        "slice mismatch",
        "missing reference picture",
        "missing picture start code",
        "skipped mb in i-frame",
        "motion_type at",
        "invalid mquant",
        "non-existing pps",
        "decode_slice_header error",
        "no frame!",
        "first frame is no keyframe",
    ]

    /// Whether the line is a video decoder's complaint about missing references, as mpv logs it before the first
    /// frame of a stream joined mid-GOP (Q2, user decision 2026-11-15). Only `[ffmpeg/video]` lines, so HTTP,
    /// tcp and demuxer errors never match.
    static func isPreFrameDecoderNoise(_ text: String) -> Bool {
        guard text.hasPrefix("[ffmpeg/video] ") else { return false }
        let lowered = text.lowercased()
        return decoderNoise.contains { lowered.contains($0) }
    }

    /// Counts one load's decoder noise until its first frame (Q2): `absorbs` says whether a line goes to debug
    /// instead of notice; `finish` (the first frame, the load ending or being replaced) gives the count to log once.
    struct PreFrameNoise {
        private(set) var count = 0
        private var finished = false

        /// A new load: count again.
        mutating func reset() {
            count = 0
            finished = false
        }

        /// Whether this line is counted and logged at debug. After the first frame such lines stay at notice.
        mutating func absorbs(_ text: String) -> Bool {
            guard !finished, MPVLogText.isPreFrameDecoderNoise(text) else { return false }
            count += 1
            return true
        }

        /// The count to log, once, when the load reached its first frame or ended; nil when there was none.
        mutating func finish() -> Int? {
            guard !finished else { return nil }
            finished = true
            return count > 0 ? count : nil
        }
    }
}
