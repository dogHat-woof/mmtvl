import Foundation
import Network
import Testing
@testable import MMTVL

struct MPVOptionsTests {
    private func value(_ name: String) -> String? {
        MPVOptions.all.first { $0.name == name }?.value
    }

    @Test func renderCallsDontWaitForFrameTiming() {
        #expect(value("video-timing-offset") == "0")
        #expect(MPVOptions.all.last?.name == "video-timing-offset")
    }

    @Test func keepsTheM4Buffers() {
        #expect(value("cache") == "yes")
        #expect(value("demuxer-max-back-bytes") == "512MiB")
        #expect(value("demuxer-max-bytes") == "256MiB")
    }

    @Test func bufferProfiles() {
        #expect(BufferProfile.tile.backBytes == "160MiB")
        #expect(BufferProfile.tile.forwardBytes == "64MiB")
        #expect(BufferProfile.full.backBytes == MPVOptions.backBuffer)
        #expect(BufferProfile.full.forwardBytes == MPVOptions.forwardBuffer)
    }

    // MARK: M7j L6: the loadfile command

    static let tunerURL = URL(string: "http://10.0.0.9:5004/auto/v5.1")!

    /// The whole constant per-file option string (security M2): deinterlacing, MPEG-TS only, no redirects.
    @Test func directLoadCommandHasPerFileDeinterlace() {
        #expect(MPVLoadCommand.make(url: Self.tunerURL, direct: true) == [
            "loadfile", "http://10.0.0.9:5004/auto/v5.1", "replace", "-1",
            "deinterlace=auto,demuxer=lavf,demuxer-lavf-format=mpegts,stream-lavf-o=max_redirects=0",
        ])
    }

    @Test func playlistLoadCommandIsUnchanged() {
        let url = URL(string: "http://127.0.0.1:50000/r/token/index.m3u8")!
        #expect(MPVLoadCommand.make(url: url, direct: false) == ["loadfile", url.absoluteString, "replace"])
    }

    /// M7j L6: an antenna stream that never played fails at once; one that played is reconnected once.
    @Test func directStreamsRetryOnlyAfterPlaying() {
        #expect(!MPVPlayerController.shouldRetry(direct: true, wasPlaying: false, used: 0))
        #expect(MPVPlayerController.shouldRetry(direct: true, wasPlaying: true, used: 0))
        #expect(!MPVPlayerController.shouldRetry(direct: true, wasPlaying: true, used: 1))
        // Playlist streams keep M4's two retries, playing or not.
        #expect(MPVPlayerController.shouldRetry(direct: false, wasPlaying: false, used: 0))
        #expect(MPVPlayerController.shouldRetry(direct: false, wasPlaying: true, used: 1))
        #expect(!MPVPlayerController.shouldRetry(direct: false, wasPlaying: false, used: 2))
    }
}

/// M7j L15, L9.
struct MPVLogTextTests {
    @Test func redactsURLs() {
        #expect(MPVLogText.redacted("[ffmpeg] http: HTTP error 503 for http://10.0.0.9:5004/auto/v4.1 now")
            == "[ffmpeg] http: HTTP error 503 for <url> now")
        #expect(MPVLogText.redacted("Opening https://cdn.example.com/live/user/pass/1.ts?token=abc")
            == "Opening <url>")
        // ffmpeg's tcp lines name the address too.
        #expect(MPVLogText.redacted("[ffmpeg] tcp: Connection to tcp://10.0.0.9:5004?timeout=15000000 failed: x")
            == "[ffmpeg] tcp: Connection to <url> failed: x")
        #expect(MPVLogText.redacted("[cplayer] Failed to recognize file format.") == "[cplayer] Failed to recognize file format.")
    }

    @Test func findsHTTPStatus() {
        #expect(MPVLogText.httpStatus(in: "http: HTTP error 503 Service Unavailable") == 503)
        #expect(MPVLogText.httpStatus(in: "[ffmpeg] HTTP error 404 Not Found") == 404)
        #expect(MPVLogText.httpStatus(in: "[ffmpeg] Failed to open the stream") == nil)
        #expect(MPVLogText.httpStatus(in: "HTTP error 5") == nil)
    }

    /// QA, step 5: a direct load's "HTTP error 503" line, then end-file with an error, leaves the status in the
    /// failed state `onFailure` reads (L9). `handle(_:)` is private and needs a core, so this follows its steps.
    @Test func failedStateKeepsHTTPStatus() {
        var state = PlayerState(phase: .loading, timeshift: nil)
        if let status = MPVLogText.httpStatus(in: "[ffmpeg] http: HTTP error 503 Service Unavailable") {
            state.httpStatus = status
        }
        state.videoFormat = VideoFormat(width: 1920, height: 1080, fps: 29.97, interlaced: true)
        let failed = PlayerState.failed(from: state)
        #expect(failed.phase == .failed)
        #expect(failed.httpStatus == 503)
        #expect(failed.timeshift == nil)
        #expect(failed.videoFormat == nil)
        // No status logged: none after the failure either.
        #expect(PlayerState.failed(from: PlayerState(phase: .loading, timeshift: nil)).httpStatus == nil)
    }

    /// M7j Q2: mpv's lines as `MPVHandle` passes them on (`[prefix] text`).
    @Test func decoderNoiseIsRecognized() {
        #expect(MPVLogText.isPreFrameDecoderNoise("[ffmpeg/video] mpeg2video: Invalid frame dimensions 0x0."))
        #expect(MPVLogText.isPreFrameDecoderNoise("[ffmpeg/video] mpeg2video: ac-tex damaged at 12 34"))
        #expect(MPVLogText.isPreFrameDecoderNoise("[ffmpeg/video] mpeg2video: Warning MVs not available"))
        #expect(MPVLogText.isPreFrameDecoderNoise("[ffmpeg/video] mpeg2video: concealing 120 DC, 120 AC, 120 MV errors in P frame"))
        #expect(MPVLogText.isPreFrameDecoderNoise("[ffmpeg/video] h264: non-existing PPS 0 referenced"))
        // Not decoder noise: HTTP and tcp errors (L9 reads the status from them), other decoder lines, other prefixes.
        #expect(!MPVLogText.isPreFrameDecoderNoise("[ffmpeg] http: HTTP error 503 Service Unavailable"))
        #expect(!MPVLogText.isPreFrameDecoderNoise("HTTP error 503 Service Unavailable"))
        #expect(!MPVLogText.isPreFrameDecoderNoise("[ffmpeg] tcp: Connection to <url> failed: Connection refused"))
        #expect(!MPVLogText.isPreFrameDecoderNoise("[ffmpeg/video] h264: Increasing reorder buffer to 1"))
        #expect(!MPVLogText.isPreFrameDecoderNoise("[ffmpeg/demuxer] mpegts: Invalid frame dimensions 0x0."))
        #expect(!MPVLogText.isPreFrameDecoderNoise(""))
    }

    /// M7j Q2: the player's count, without an mpv core.
    @Test func preFrameNoiseCountsUntilTheFirstFrame() {
        var noise = MPVLogText.PreFrameNoise()
        let line = "[ffmpeg/video] mpeg2video: Invalid frame dimensions 0x0."
        let first = noise.absorbs(line), second = noise.absorbs(line)
        let http = noise.absorbs("[ffmpeg] http: HTTP error 503 Service Unavailable")
        #expect(first && second && !http)
        #expect(noise.count == 2)
        // The first frame: one report, then such lines stay at notice.
        let report = noise.finish(), again = noise.finish(), afterFrame = noise.absorbs(line)
        #expect(report == 2)
        #expect(again == nil)
        #expect(!afterFrame)
        // The next load counts again; one without noise reports nothing.
        noise.reset()
        #expect(noise.count == 0)
        let quiet = noise.finish()
        #expect(quiet == nil)
        noise.reset()
        let counted = noise.absorbs(line), last = noise.finish()
        #expect(counted)
        #expect(last == 1)
    }
}

/// Security M2 (user decision 2026-11-15, "block both"): a real mpv core loads from loopback listener A, which
/// redirects to listener B or serves a playlist naming B. As an antenna stream (the per-file options) B gets no
/// request; as a playlist stream (no options) it does, which shows the setup would see one. The cores use
/// `vo=null`, `ao=null`: nothing is drawn or heard.
@Suite(.serialized)
struct MPVDirectStreamTests {
    nonisolated enum Answer: Sendable {
        case redirect, hlsPlaylist, plainPlaylist

        func response(naming target: UInt16) -> String {
            let next = "http://127.0.0.1:\(target)/next.ts"
            switch self {
            case .redirect:
                return "HTTP/1.1 302 Found\r\nLocation: \(next)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            case .hlsPlaylist:
                return Self.ok("application/vnd.apple.mpegurl",
                               "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:1\n#EXTINF:2.0,\n\(next)\n")
            case .plainPlaylist:
                return Self.ok("audio/x-mpegurl", "#EXTM3U\n#EXTINF:-1,Next\n\(next)\n")
            }
        }

        private static func ok(_ type: String, _ body: String) -> String {
            "HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        }
    }

    /// Counts requests on 127.0.0.1 and answers each with `answer`, then closes.
    nonisolated final class LoopbackServer: @unchecked Sendable {
        private let listener: NWListener
        private let lock = NSLock()
        private var _requests = 0
        private let answer: @Sendable () -> String
        private let queue = DispatchQueue(label: "MPVDirectStreamTests.server")

        init(answer: @escaping @Sendable () -> String) throws {
            self.answer = answer
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: queue)
        }

        var port: UInt16? { listener.port.map(\.rawValue).flatMap { $0 == 0 ? nil : $0 } }
        var requests: Int { lock.withLock { _requests } }

        private func accept(_ connection: NWConnection) {
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
                guard let self, let data, !data.isEmpty else {
                    connection.cancel()
                    return
                }
                self.lock.withLock { self._requests += 1 }
                connection.send(content: Data(self.answer().utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }

        func stop() { listener.cancel() }
    }

    /// The events of one core, from its event queue.
    nonisolated final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var _ended = false
        func record(_ event: MPVEvent) {
            if case .endFile(let reason, _) = event, reason == .eof || reason == .error {
                lock.withLock { _ended = true }
            }
        }
        var ended: Bool { lock.withLock { _ended } }
    }

    /// MPVHandle lives for the app's lifetime (its wakeup callback holds it unretained), so the test cores are kept.
    nonisolated(unsafe) static var cores: [MPVHandle] = []

    private func wait(seconds: Double, until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
    }

    /// Plays A once; returns how many requests A and B got.
    private func play(_ answer: Answer, direct: Bool) async throws -> (first: Int, second: Int) {
        let second = try LoopbackServer { "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" }
        defer { second.stop() }
        await wait(seconds: 5) { second.port != nil }
        let target = try #require(second.port)
        let first = try LoopbackServer { answer.response(naming: target) }
        defer { first.stop() }
        await wait(seconds: 5) { first.port != nil }
        let port = try #require(first.port)
        let url = try #require(URL(string: "http://127.0.0.1:\(port)/auto/v5.1"))

        let events = Events()
        let core = try MPVHandle(options: [("vo", "null"), ("ao", "null"), ("audio", "no"), ("idle", "yes"),
                                           ("ytdl", "no"), ("input-default-bindings", "no"), ("network-timeout", "3")],
                                 onEvent: { events.record($0) })
        Self.cores.append(core)
        core.command(MPVLoadCommand.make(url: url, direct: direct))
        await wait(seconds: 10) { events.ended || second.requests > 0 }
        // A playlist entry would load after the playlist itself ends.
        await wait(seconds: 1) { second.requests > 0 }
        core.command(["stop"])
        return (first.requests, second.requests)
    }

    @Test(arguments: [Answer.redirect, .hlsPlaylist, .plainPlaylist])
    func directStreamFetchesNothingElse(_ answer: Answer) async throws {
        let direct = try await play(answer, direct: true)
        #expect(direct.first >= 1)
        #expect(direct.second == 0)
    }

    /// The control: without the per-file options mpv does follow A to B, so the test above can see a request.
    @Test(arguments: [Answer.redirect, .hlsPlaylist, .plainPlaylist])
    func playlistStreamFollowsToTheSecondListener(_ answer: Answer) async throws {
        let playlist = try await play(answer, direct: false)
        #expect(playlist.first >= 1)
        #expect(playlist.second >= 1)
    }
}
