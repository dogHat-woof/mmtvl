import Foundation
import Libmpv
import os

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
        // M7n step 3a: warnings from every module, plus vo_libmpv's verbose lines (its render-stuck line), for
        // `logLevel` "terminal-default"; `MPVHandle` passes on only warnings, errors and that line.
        ("msg-level", messageLevels),
        // M6 L7: render calls run on the main thread; don't block them for frame timing.
        ("video-timing-offset", "0"),
    ]

    /// M7n step 3a: the Live TV cores' `mpv_request_log_messages` level: the per-module levels of `msg-level`.
    static let logLevel = "terminal-default"
    static let messageLevels = "all=warn,vo/libmpv=v"

    /// `all`, then the experiment switches' options (M7n step 3a). With no switch set, exactly `all`.
    static func all(adding switches: MPVSwitches) -> [(name: String, value: String)] {
        all + switches.options
    }
}

/// M7n step 3a: hidden `defaults` switches for the stutter experiments (Release builds too), off by default; removed or
/// turned into the fix in step 4. `defaults write dev.mmtvl.launcher <key> …`, then relaunch MMTVL.
nonisolated struct MPVSwitches: Sendable {
    /// The mpv options to append, in a fixed order.
    var options: [(name: String, value: String)] = []
    /// One line per key that is set: what was applied, or why it was ignored. Never an unvalidated value.
    var notes: [String] = []

    static let hwdecCodecsKey = "mpvHwdecCodecs"
    static let openGLPBOKey = "mpvOpenGLPBO"
    static let videoSyncKey = "mpvVideoSync"
    static let displayFPSKey = "mpvDisplayFPS"
    static let maxStringLength = 64
    static let displayFPSRange = 1.0...240.0

    /// `value(key)` is `UserDefaults.object(forKey:)` (tests pass a dictionary's lookup).
    static func parse(_ value: (String) -> Any?) -> MPVSwitches {
        var switches = MPVSwitches()
        switches.addString(value(hwdecCodecsKey), key: hwdecCodecsKey, option: "hwdec-codecs")
        if let raw = value(openGLPBOKey) {
            if let on = bool(raw) {
                if on { switches.options.append(("opengl-pbo", "yes")) }
                switches.notes.append("\(openGLPBOKey) = \(on ? "YES" : "NO") (opengl-pbo\(on ? "=yes" : " unchanged"))")
            } else {
                switches.notes.append("\(openGLPBOKey) ignored: not a bool")
            }
        }
        switches.addString(value(videoSyncKey), key: videoSyncKey, option: "video-sync")
        if let raw = value(displayFPSKey) {
            if let fps = number(raw), displayFPSRange.contains(fps) {
                let text = "\(fps)"
                switches.options.append(("display-fps-override", text))
                switches.notes.append("\(displayFPSKey) = \(text) (display-fps-override)")
            } else {
                switches.notes.append("\(displayFPSKey) ignored: not a number in 1…240")
            }
        }
        return switches
    }

    /// Only `[a-z0-9,_-]`, 1…64 characters: a short mpv option value, safe to log.
    static func isOptionString(_ text: String) -> Bool {
        !text.isEmpty && text.count <= maxStringLength
            && text.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || ",_-".unicodeScalars.contains($0) }
    }

    private mutating func addString(_ raw: Any?, key: String, option: String) {
        guard let raw else { return }
        guard let text = raw as? String, Self.isOptionString(text) else {
            notes.append("\(key) ignored: not a short option string ([a-z0-9,_-], at most \(Self.maxStringLength))")
            return
        }
        options.append((option, text))
        notes.append("\(key) = \(text) (\(option))")
    }

    /// `-bool YES` is an NSNumber; `-string yes` a string.
    private static func bool(_ raw: Any) -> Bool? {
        if let text = raw as? String {
            switch text.lowercased() {
            case "yes", "true", "1": return true
            case "no", "false", "0": return false
            default: return nil
            }
        }
        guard let number = raw as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
        switch number.doubleValue {
        case 0: return false
        case 1: return true
        default: return nil
        }
    }

    /// `-float 59.94` / `-int 60` are NSNumbers; `-string 60` a string. Booleans aren't numbers.
    private static func number(_ raw: Any) -> Double? {
        if let text = raw as? String {
            return Double(text.trimmingCharacters(in: .whitespaces)).flatMap { $0.isFinite ? $0 : nil }
        }
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        return value.isFinite ? value : nil
    }

    /// Read from `UserDefaults.standard` at the first player's creation and logged once (category `MPV`); the same
    /// switches go to every player of the run.
    static let fromDefaults: MPVSwitches = {
        let switches = parse { UserDefaults.standard.object(forKey: $0) }
        let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "MPV")
        for note in switches.notes { logger.notice("Switch \(note, privacy: .public)") }
        return switches
    }()
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
