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

    /// Re-review L2: the last retry still happens normally, but not after the relay refused a URI or a redirect for
    /// the stream; the retry before it still does. Antenna streams are unaffected.
    @Test func noDirectRetryAfterARelayRefusal() {
        #expect(MPVPlayerController.maxRetries == 2)
        #expect(MPVPlayerController.shouldRetry(direct: false, wasPlaying: true, used: 1, relayRefused: false))
        #expect(!MPVPlayerController.shouldRetry(direct: false, wasPlaying: true, used: 1, relayRefused: true))
        #expect(!MPVPlayerController.shouldRetry(direct: false, wasPlaying: false, used: 1, relayRefused: true))
        #expect(MPVPlayerController.shouldRetry(direct: false, wasPlaying: false, used: 0, relayRefused: true))
        #expect(MPVPlayerController.shouldRetry(direct: true, wasPlaying: true, used: 0, relayRefused: true))
        // Even after a refusal, a relay that's gone never hands the stream to mpv directly.
        #expect(MPVPlayerController.loadRoute(antenna: false, relayServes: false, isWebURL: true, relayHasRun: false,
                                              relayRefused: true) == .refuse)
    }

    /// Pre-release lows (a): the last retry (`used: maxRetries - 1` → the `maxRetries`th load) goes through the relay
    /// like the others while it runs; nothing in the route depends on the retry count.
    @Test func everyPlaylistRetryGoesThroughARunningRelay() {
        let last = MPVPlayerController.maxRetries - 1
        #expect(MPVPlayerController.shouldRetry(direct: false, wasPlaying: true, used: last, relayRefused: false))
        #expect(MPVPlayerController.loadRoute(antenna: false, relayServes: true, isWebURL: true, relayHasRun: true,
                                              relayRefused: false) == .relay)
        // The relay stopped after it ran: the load fails rather than go straight to the provider.
        #expect(MPVPlayerController.loadRoute(antenna: false, relayServes: false, isWebURL: true, relayHasRun: true,
                                              relayRefused: false) == .refuse)
        // The relay never started: direct, as before.
        #expect(MPVPlayerController.loadRoute(antenna: false, relayServes: false, isWebURL: true, relayHasRun: false,
                                              relayRefused: false) == .direct)
        // URLs the relay doesn't carry (rtsp, udp) still go to mpv.
        #expect(MPVPlayerController.loadRoute(antenna: false, relayServes: false, isWebURL: false, relayHasRun: true,
                                              relayRefused: false) == .direct)
        // Antenna streams are unchanged: always direct.
        #expect(MPVPlayerController.loadRoute(antenna: true, relayServes: false, isWebURL: true, relayHasRun: true,
                                              relayRefused: false) == .direct)
    }

    /// Pre-release lows (a): a running relay reports `hasRun` and gives every load of a stream (first and each
    /// retry) a relay address; stopped, it gives none but still reports that it ran.
    @Test @MainActor func runningRelayServesEveryLoad() async throws {
        let relay = HLSRelay(fetch: { _, _ in throw URLError(.cannotConnectToHost) })
        #expect(!relay.hasRun)
        relay.start()
        defer { relay.stop() }
        for _ in 0..<300 where relay.port == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(relay.hasRun)
        let url = URL(string: "https://cdn.example/live/master.m3u8")!
        for _ in 0...MPVPlayerController.maxRetries {
            #expect(relay.localURL(for: url)?.host() == "127.0.0.1")
        }
        relay.stop()
        #expect(relay.hasRun)
        #expect(relay.localURL(for: url) == nil)
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
        // MR step 2: no Lua scripts (the hardened runtime has no JIT exception).
        let core = try MPVHandle(options: MPVOptions.scriptsOff + [("vo", "null"), ("ao", "null"), ("audio", "no"),
                                                                    ("idle", "yes"), ("input-default-bindings", "no"),
                                                                    ("network-timeout", "3")],
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

/// M7n step 4a: the display rate given to mpv's `display-fps-override`.
struct DisplayRefreshTests {
    @Test func theModesRateWhenUsable() {
        #expect(DisplayRefresh.usableRate(modeRate: 60, maximumFPS: 60) == 60)
        // Exact, not rounded: a 59.94 Hz TV mode.
        #expect(DisplayRefresh.usableRate(modeRate: 60_000.0 / 1001, maximumFPS: 60) == 60_000.0 / 1001)
        #expect(DisplayRefresh.usableRate(modeRate: 50, maximumFPS: 60) == 50)
        #expect(DisplayRefresh.usableRate(modeRate: 1, maximumFPS: 0) == 1)
        #expect(DisplayRefresh.usableRate(modeRate: 240, maximumFPS: 0) == 240)
    }

    /// Displays whose mode reports 0 (or nonsense) fall back to the screen's maximum frames per second.
    @Test func fallsBackToMaximumFPS() {
        #expect(DisplayRefresh.usableRate(modeRate: 0, maximumFPS: 120) == 120)
        #expect(DisplayRefresh.usableRate(modeRate: 240.5, maximumFPS: 60) == 60)
        #expect(DisplayRefresh.usableRate(modeRate: .nan, maximumFPS: 60) == 60)
        #expect(DisplayRefresh.usableRate(modeRate: .infinity, maximumFPS: 60) == 60)
        #expect(DisplayRefresh.usableRate(modeRate: -60, maximumFPS: 60) == 60)
    }

    /// Nothing usable: no override (mpv keeps audio timing).
    @Test func nothingUsable() {
        #expect(DisplayRefresh.usableRate(modeRate: 0, maximumFPS: 0) == nil)
        #expect(DisplayRefresh.usableRate(modeRate: 0, maximumFPS: 241) == nil)
        #expect(DisplayRefresh.usableRate(modeRate: 0.5, maximumFPS: -1) == nil)
        #expect(DisplayRefresh.usableRate(modeRate: 1000, maximumFPS: 1000) == nil)
    }

    @Test func overrideValues() {
        #expect(DisplayRefresh.overrideValue(for: 60) == "60.0")
        #expect(Double(DisplayRefresh.overrideValue(for: 60_000.0 / 1001)) == 60_000.0 / 1001)
        #expect(DisplayRefresh.overrideValue(for: nil) == "0")
    }

    @Test func liveTVCoresResampleToTheDisplay() {
        #expect(MPVOptions.all.first { $0.name == "video-sync" }?.value == "display-resample")
    }
}

/// M7n step 3a: the stats line.
struct PlaybackStatsTests {
    @Test func deltas() {
        #expect(PlaybackStats.delta(12, since: 10) == 2)
        #expect(PlaybackStats.delta(10, since: 10) == 0)
        // Reset for a new file: counts from zero.
        #expect(PlaybackStats.delta(3, since: 10) == 3)
        #expect(PlaybackStats.delta(5, since: nil) == 5)
        #expect(PlaybackStats.delta(nil, since: 5) == nil)
    }

    @Test func renderTimings() {
        var timings = PlaybackStats.RenderTimings()
        timings.record(nanos: 9_800_000)
        timings.record(nanos: 12_000_000)
        timings.record(nanos: 14_250_000)
        timings.record(nanos: 3_000_000)
        #expect(timings.draws == 4)
        #expect(timings.longestNanos == 14_250_000)
        // Over 12 ms, not at it.
        #expect(timings.slowDraws == 1)
    }

    @Test func fullLine() {
        let sample = PlaybackStats.Sample(
            decoder: "no", containerFPS: 29.97003, filteredFPS: 59.94006,
            counters: .init(frameDrops: 7, decoderFrameDrops: 1, delayedFrames: 13, mistimedFrames: 2),
            avsync: -0.0123, displayFPS: 60)
        var render = PlaybackStats.RenderTimings()
        render.record(nanos: 9_840_000)
        render.record(nanos: 13_000_000)
        render.updates = 3
        render.longestUpdateToDrawNanos = 4_150_000
        render.longestDrawGapNanos = 50_049_000
        let line = PlaybackStats.line(
            player: 1, sample: sample,
            previous: .init(frameDrops: 5, decoderFrameDrops: 1, delayedFrames: 10, mistimedFrames: 0), render: render,
            stuck: 4)
        #expect(line == "Stats (player 1): decoder no, 29.97 fps, filtered 59.94 fps, dropped 2, decoder dropped 0, "
            + "delayed 3, mistimed 2, avsync -0.012 s, display 60.00 fps, 3 updates, 2 draws, 4 stuck, "
            + "longest render 13.0 ms, 1 over 12 ms, longest update to draw 4.2 ms, longest gap 50.0 ms")
    }

    @Test func unknownValuesAndNoDisplayRate() {
        let line = PlaybackStats.line(player: 2, sample: PlaybackStats.Sample(),
                                      previous: .init(), render: .init(), stuck: 0)
        #expect(line == "Stats (player 2): decoder ?, ? fps, filtered ? fps, dropped ?, decoder dropped ?, delayed ?, "
            + "mistimed ?, avsync ?, 0 updates, 0 draws, 0 stuck, longest render 0.0 ms, 0 over 12 ms, "
            + "longest update to draw 0.0 ms, longest gap 0.0 ms")
    }

    /// QA (step 3a): mpv's update callbacks against draws, the wait from a callback to its draw, the gap between draws.
    @Test func recorderCountsUpdatesWaitsAndGaps() {
        var recorder = PlaybackStats.RenderRecorder()
        // Two callbacks before one draw (coalesced): the wait runs from the first.
        recorder.update(at: 1_000_000)
        recorder.update(at: 3_000_000)
        recorder.draw(at: 6_000_000, renderNanos: 2_000_000)
        // A callback then a draw 1 ms later, 40 ms after the last draw.
        recorder.update(at: 45_000_000)
        recorder.draw(at: 46_000_000, renderNanos: 13_000_000)
        // A draw with no callback (a resize): a gap, no wait.
        recorder.draw(at: 62_000_000, renderNanos: 1_000_000)
        let first = recorder.take(restart: false)
        #expect(first.updates == 3)
        #expect(first.draws == 3)
        #expect(first.longestUpdateToDrawNanos == 5_000_000)
        #expect(first.longestDrawGapNanos == 40_000_000)
        #expect(first.longestNanos == 13_000_000)
        #expect(first.slowDraws == 1)

        // The next period starts empty but still measures the gap from the last draw of the one before.
        recorder.draw(at: 162_000_000, renderNanos: 1_000_000)
        let second = recorder.take(restart: false)
        #expect(second.updates == 0)
        #expect(second.draws == 1)
        #expect(second.longestDrawGapNanos == 100_000_000)
        #expect(second.longestUpdateToDrawNanos == 0)

        // A restart forgets the last draw: the first draw after it has no gap.
        _ = recorder.take(restart: true)
        recorder.update(at: 900_000_000)
        recorder.draw(at: 902_000_000, renderNanos: 1_000_000)
        let third = recorder.take(restart: false)
        #expect(third.longestDrawGapNanos == 0)
        #expect(third.longestUpdateToDrawNanos == 2_000_000)
        #expect(third.updates == 1)
    }

    /// The render-stuck lines: all counted per stats period, the first of each load logged.
    @Test func renderStuckLinesAreCountedAndLoggedOncePerLoad() {
        var counter = PlaybackStats.RenderStuckCounter()
        let first = counter.note(), second = counter.note(), third = counter.note()
        #expect(first && !second && !third)
        #expect(counter.take() == 3)
        #expect(counter.take() == 0)
        let sameLoad = counter.note()
        #expect(!sameLoad)
        counter.newLoad()
        let nextLoad = counter.note(), after = counter.note()
        #expect(nextLoad && !after)
        #expect(counter.take() == 3)
    }

    /// A callback still waiting at the end of a period is measured by the draw in the next one.
    @Test func pendingUpdateCarriesIntoTheNextPeriod() {
        var recorder = PlaybackStats.RenderRecorder()
        recorder.update(at: 10_000_000)
        #expect(recorder.take(restart: false).updates == 1)
        recorder.draw(at: 70_000_000, renderNanos: 1_000_000)
        #expect(recorder.take(restart: false).longestUpdateToDrawNanos == 60_000_000)
    }

    /// Only the full-screen player while it plays: not a Multiview window, not the muted home preview, not paused.
    @Test func onlyTheFullScreenPlayerLogs() {
        #expect(MPVPlayerController.logsStats(phase: .playing, profile: .full, holdsSleepAssertion: true))
        #expect(!MPVPlayerController.logsStats(phase: .playing, profile: .tile, holdsSleepAssertion: true))
        #expect(!MPVPlayerController.logsStats(phase: .playing, profile: .full, holdsSleepAssertion: false))
        #expect(!MPVPlayerController.logsStats(phase: .paused, profile: .full, holdsSleepAssertion: true))
        #expect(!MPVPlayerController.logsStats(phase: .loading, profile: .full, holdsSleepAssertion: true))
    }
}

/// M7n step 4a: a real mpv core (MPVKit's mpv) takes display-resample and a display rate set at runtime.
/// No file is loaded: nothing is drawn or heard.
struct MPVDisplayRateCoreTests {
    /// MPVHandle lives for the app's lifetime (its wakeup callback holds it unretained), so the test core is kept.
    nonisolated(unsafe) static var cores: [MPVHandle] = []

    @Test func aCoreTakesTheDisplayRate() throws {
        let core = try MPVHandle(options: MPVOptions.all + [("ao", "null")], onEvent: { _ in })
        Self.cores.append(core)
        #expect(core.string("video-sync") == "display-resample")
        #expect(core.double("display-fps-override") == 0)
        core.setString("display-fps-override", DisplayRefresh.overrideValue(for: 60_000.0 / 1001))
        #expect(core.double("display-fps-override").map { abs($0 - 59.94) < 0.001 } == true)
        core.setString("display-fps-override", DisplayRefresh.overrideValue(for: nil))
        #expect(core.double("display-fps-override") == 0)
        // MMTVL's own options are still there.
        #expect(core.string("hwdec") == "videotoolbox")
        #expect(core.string("video-timing-offset").flatMap(Double.init) == 0)
    }
}

/// M7n step 3a (a step 3b aid): which of mpv's log messages `MPVHandle` passes on.
struct MPVLogForwardingTests {
    @Test func warningsErrorsAndTheRenderStuckLine() {
        #expect(MPVLogText.forwards(level: "warn", text: "Audio device underrun detected."))
        #expect(MPVLogText.forwards(level: "error", text: "x"))
        #expect(MPVLogText.forwards(level: "fatal", text: "x"))
        // vo_libmpv's MP_VERBOSE line, as mpv 0.41 prints it.
        #expect(MPVLogText.forwards(level: "v", text: "mpv_render_context_render() not being called or stuck."))
        // Its other verbose and info lines (msg-level lets vo/libmpv through at v) are dropped.
        #expect(!MPVLogText.forwards(level: "v", text: "reconfig to 1280x720 yuv420p"))
        #expect(!MPVLogText.forwards(level: "info", text: "VO: [libmpv] 1280x720 yuv420p"))
        #expect(!MPVLogText.forwards(level: "debug", text: "x"))
    }

    @Test func liveTVCoresAskForTheModuleLevels() {
        #expect(MPVOptions.logLevel == "terminal-default")
        #expect(MPVOptions.all.first { $0.name == "msg-level" }?.value == "all=warn,vo/libmpv=v")
    }

    /// A real core takes the msg-level option and the "terminal-default" request.
    @Test func aCoreTakesTheLogLevels() throws {
        let core = try MPVHandle(options: MPVOptions.all + [("ao", "null")], logLevel: MPVOptions.logLevel,
                                 onEvent: { _ in })
        MPVDisplayRateCoreTests.cores.append(core)
        #expect(core.string("msg-level") == "all=warn,vo/libmpv=v")
    }
}

/// MR step 2 (security review): mpv's built-in Lua scripts, user scripts and config files are off, so LuaJIT never runs
/// and the hardened runtime needs neither JIT exception. A real core (MPVKit's mpv 0.41) reads every option back as
/// "no": `MPVHandle` only logs an option mpv rejects, so a renamed one would leave its script on.
struct MPVScriptsOffTests {
    static let names = ["osc", "load-stats-overlay", "load-console", "load-auto-profiles", "load-select",
                        "load-positioning", "load-commands", "load-context-menu", "load-scripts", "ytdl", "config"]

    @Test func liveTVCoresTurnEveryScriptOff() {
        for name in Self.names {
            #expect(MPVOptions.all.first { $0.name == name }?.value == "no", "\(name)")
        }
        #expect(Set(MPVOptions.scriptsOff.map(\.name)) == Set(Self.names))
    }

    @Test func aCoreReadsEveryScriptOptionBackAsNo() throws {
        let core = try MPVHandle(options: MPVOptions.all + [("ao", "null")], onEvent: { _ in })
        MPVDisplayRateCoreTests.cores.append(core)
        for name in Self.names {
            #expect(core.string(name) == "no", "\(name)")
        }
    }
}
