import Foundation
import Libmpv
import os

nonisolated enum MPVEvent: Sendable, Equatable {
    enum EndReason: Sendable, Equatable { case eof, stop, quit, error, redirect, other }
    case fileLoaded, playbackRestart
    case endFile(EndReason, error: Int32)
    case shutdown
    /// Requested at "warn"; text with URLs redacted.
    case log(level: String, text: String)
}

/// A libmpv core (D6). Thread-safe like the API it wraps; events are drained on a private queue.
nonisolated final class MPVHandle: @unchecked Sendable {
    enum MPVError: Error { case create, initialize(Int32) }

    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "MPV")

    let handle: OpaquePointer
    private let queue = DispatchQueue(label: "dev.mmtvl.launcher.mpv-events")
    private let onEvent: @Sendable (MPVEvent) -> Void

    /// mpv_create, options, mpv_request_log_messages("warn"), mpv_initialize, wakeup callback.
    /// `onEvent` runs on the private event queue; the owner hops to the main actor.
    init(options: [(name: String, value: String)], onEvent: @escaping @Sendable (MPVEvent) -> Void) throws {
        guard let handle = mpv_create() else { throw MPVError.create }
        self.handle = handle
        self.onEvent = onEvent
        for option in options {
            let status = mpv_set_option_string(handle, option.name, option.value)
            if status < 0 {
                Self.logger.error("Option \(option.name, privacy: .public) failed: \(String(cString: mpv_error_string(status)), privacy: .public)")
            }
        }
        mpv_request_log_messages(handle, "warn")
        let status = mpv_initialize(handle)
        guard status >= 0 else {
            mpv_terminate_destroy(handle)
            throw MPVError.initialize(status)
        }
        // The handle lives for the app's lifetime (L7), so an unretained pointer is safe.
        // The callback must not call any mpv function: it only schedules the drain.
        mpv_set_wakeup_callback(handle, { context in
            guard let context else { return }
            let me = Unmanaged<MPVHandle>.fromOpaque(context).takeUnretainedValue()
            me.queue.async { me.drain() }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    /// strdup'd NULL-terminated argv; logs failures (args[0] only, never a URL).
    func command(_ args: [String]) {
        var cStrings: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        cStrings.append(nil)
        defer { cStrings.forEach { free($0) } }
        let status = cStrings.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) {
                mpv_command(handle, $0)
            }
        }
        if status < 0 {
            Self.logger.error("Command \(args.first ?? "?", privacy: .public) failed: \(String(cString: mpv_error_string(status)), privacy: .public)")
        }
    }

    /// mpv_get_property_string + mpv_free.
    func string(_ name: String) -> String? {
        guard let value = mpv_get_property_string(handle, name) else { return nil }
        defer { mpv_free(value) }
        return String(cString: value)
    }

    /// MPV_FORMAT_DOUBLE.
    func double(_ name: String) -> Double? {
        var value = 0.0
        let status = mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &value)
        return status >= 0 ? value : nil
    }

    func setString(_ name: String, _ value: String) {
        let status = mpv_set_property_string(handle, name, value)
        if status < 0 {
            Self.logger.error("Setting \(name, privacy: .public) failed: \(String(cString: mpv_error_string(status)), privacy: .public)")
        }
    }

    /// On the event queue: the only thread that calls mpv_wait_event.
    private func drain() {
        while let event = mpv_wait_event(handle, 0)?.pointee {
            switch event.event_id {
            case MPV_EVENT_NONE:
                return
            case MPV_EVENT_FILE_LOADED:
                onEvent(.fileLoaded)
            case MPV_EVENT_PLAYBACK_RESTART:
                onEvent(.playbackRestart)
            case MPV_EVENT_END_FILE:
                guard let data = event.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee else { continue }
                let reason: MPVEvent.EndReason = switch data.reason {
                case MPV_END_FILE_REASON_EOF: .eof
                case MPV_END_FILE_REASON_STOP: .stop
                case MPV_END_FILE_REASON_QUIT: .quit
                case MPV_END_FILE_REASON_ERROR: .error
                case MPV_END_FILE_REASON_REDIRECT: .redirect
                default: .other
                }
                onEvent(.endFile(reason, error: data.error))
            case MPV_EVENT_SHUTDOWN:
                onEvent(.shutdown)
            case MPV_EVENT_LOG_MESSAGE:
                guard let message = event.data?.assumingMemoryBound(to: mpv_event_log_message.self).pointee else { continue }
                let prefix = String(cString: message.prefix)
                let text = String(cString: message.text).trimmingCharacters(in: .whitespacesAndNewlines)
                onEvent(.log(level: String(cString: message.level), text: MPVLogText.redacted("[\(prefix)] \(text)")))
            default:
                continue
            }
        }
    }
}
