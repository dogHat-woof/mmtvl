import Foundation
import Observation
import os

nonisolated struct PlayerState: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case idle, loading, playing, paused, failed }
    var phase: Phase = .idle
    var timeshift: Timeshift?
    /// M7f L3: the stream's resolution and frame rate, once mpv knows them.
    var videoFormat: VideoFormat? = nil
    /// M7j L9: the last "HTTP error NNN" mpv logged for the current load (nil: none, or not yet).
    var httpStatus: Int? = nil

    /// A load that failed for good: no timeshift or format, but the load's HTTP status stays for L9's diagnosis,
    /// which `onFailure` runs right after (QA, step 5). `play` and each `loadFile` reset it.
    static func failed(from state: PlayerState) -> PlayerState {
        PlayerState(phase: .failed, timeshift: nil, httpStatus: state.httpStatus)
    }
}

/// What `LiveTVModel` needs from a player; tests use a fake.
protocol LivePlayer: AnyObject {
    var state: PlayerState { get }
    /// After retries are exhausted (L13). Set by LiveTVModel.
    var onFailure: (() -> Void)? { get set }
    /// `direct`: an antenna stream (M7j L6): no resolver or relay, MPEG-TS only, deinterlaced, at most one reconnect.
    func play(_ url: URL, direct: Bool)
    func stop()
    func togglePause()
    func seek(by seconds: Double)
    func seekToLive()
    /// The phone's in-app volume (M5 L9, D25). Applied to every pool player.
    func setVolume(_ level: Int, muted: Bool)
    /// Multiview sound (M6 L5). Effective mute = muted (from setVolume) || !audible. Default true.
    func setAudible(_ audible: Bool)
    /// M6 L6. Applied at once if the core exists, else when it's created.
    func setBufferProfile(_ profile: BufferProfile)
    /// M7c L15: false while the home screen's muted preview plays, so the display can still sleep. Default true.
    func setHoldsSleepAssertion(_ holds: Bool)
}

extension LivePlayer {
    /// A playlist stream (through the resolver and the relay).
    func play(_ url: URL) { play(url, direct: false) }
}

/// One mpv core and its video view. Live TV pools up to five (M6 L2).
@Observable
final class MPVPlayerController: LivePlayer {
    nonisolated static let maxRetries = 2
    /// M7j L6: an antenna stream that was playing is reconnected once; one that never played fails at once.
    nonisolated static let directReconnects = 1
    static let retryDelay: Duration = .seconds(2)
    private static var nextIndex = 1

    /// Names the player in logs ("player 2").
    let index: Int

    private(set) var state = PlayerState() {
        didSet {
            if state.phase != oldValue.phase { phaseDidChange() }
        }
    }
    /// Created with the mpv core on first use; LauncherRootView hosts it (M7h step 13h).
    private(set) var videoView: MPVVideoView?
    @ObservationIgnored var onFailure: (() -> Void)?
    /// M7c L29: follows the provider's redirect once (nil = mpv follows it).
    @ObservationIgnored var resolver: StreamResolver? = .shared
    @ObservationIgnored private var resolveTask: Task<Void, Never>?
    /// M7c L30: mpv loads through the loopback relay (nil, or never ran = straight from the CDN; pre-release lows (a):
    /// once it ran, never straight).
    @ObservationIgnored var relay: HLSRelay? = .shared

    @ObservationIgnored private var mpv: MPVHandle?
    @ObservationIgnored private var currentURL: URL?
    /// M7j L6: the current stream is an antenna stream.
    @ObservationIgnored private var isDirect = false
    @ObservationIgnored private var pendingURL: URL?
    @ObservationIgnored private var retries = 0
    /// Re-review L2: the URL the current load gave the relay (nil: loaded directly).
    @ObservationIgnored private var relayedURL: URL?
    /// Re-review L2: the relay refused a URI or a redirect for one of this `play`'s loads; no direct load follows, and
    /// one relayed retry fewer.
    @ObservationIgnored private var relayRefused = false
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var liveEdge = LiveEdgeSmoother()
    @ObservationIgnored private let sleep = SleepAssertion()
    /// MMTVL's own volume (M5 L9), kept across cores and files.
    @ObservationIgnored private var volumeLevel = 100
    @ObservationIgnored private var volumeMuted = false
    /// M6 L5: false mutes a Multiview window without sound.
    @ObservationIgnored private var audible = true
    @ObservationIgnored private var holdsSleep = true
    @ObservationIgnored private var bufferProfile = BufferProfile.full
    @ObservationIgnored private var loggedDecoder = false
    /// M7f L3: the first format of each channel is logged once.
    @ObservationIgnored private var loggedFormat = false
    /// M7c L27: when the current load (or retry) started; nil once its first frame is logged.
    @ObservationIgnored private var loadStartedAt: ContinuousClock.Instant?
    /// M7j Q2: the current load's decoder warnings before its first frame, logged at debug and counted.
    @ObservationIgnored private var preFrameNoise = MPVLogText.PreFrameNoise()
    /// M7n step 3a: the stats line's timer, the counters at the last line, and a generation that drops reads
    /// begun before a restart or stop.
    @ObservationIgnored private var statsTimer: Timer?
    @ObservationIgnored private var statsBaseline: PlaybackStats.Counters?
    @ObservationIgnored private var statsGeneration = 0
    /// M7n step 3a: vo_libmpv's render-stuck lines since the last stats line; the first of each load is logged.
    @ObservationIgnored private var renderStuck = PlaybackStats.RenderStuckCounter()
    /// M7n step 4a: the `display-fps-override` last set (nil: none).
    @ObservationIgnored private var appliedDisplayRate: Double?
    @ObservationIgnored private let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "MPV")

    init() {
        index = Self.nextIndex
        Self.nextIndex += 1
    }

    /// Creates the core and view without playing, so the view can get its GL context early.
    func prepare() {
        guard mpv == nil else { return }
        do {
            let mpv = try MPVHandle(options: MPVOptions.all, logLevel: MPVOptions.logLevel) { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
            self.mpv = mpv
            if volumeLevel != 100 || volumeMuted || !audible { applyVolume() }
            if bufferProfile != .full { applyBufferProfile() }
            let view = MPVVideoView(mpv: mpv)
            view.videoLayer.onReady = { [weak self] replacedContext in
                Task { @MainActor in self?.videoContextReady(replacedContext: replacedContext) }
            }
            view.onDisplayRate = { [weak self] rate in self?.applyDisplayRate(rate) }
            videoView = view
            logger.info("mpv core created (player \(self.index))")
        } catch {
            logger.error("Creating the mpv core failed: \(String(describing: error), privacy: .public)")
            state.phase = .failed
        }
    }

    func play(_ url: URL, direct: Bool) {
        prepare()
        guard mpv != nil else {
            onFailure?()
            return
        }
        retryTask?.cancel()
        retries = 0
        relayRefused = false
        currentURL = url
        isDirect = direct
        loggedFormat = false
        state = PlayerState(phase: .loading, timeshift: nil)
        load(url)
    }

    func stop() {
        reportPreFrameNoise()
        loadStartedAt = nil
        resolveTask?.cancel()
        resolveTask = nil
        retryTask?.cancel()
        retryTask = nil
        pendingURL = nil
        currentURL = nil
        mpv?.command(["stop"])
        state = PlayerState(phase: .idle, timeshift: nil)
    }

    func togglePause() {
        switch state.phase {
        case .playing:
            mpv?.setString("pause", "yes")
            state.phase = .paused
        case .paused:
            mpv?.setString("pause", "no")
            state.phase = .playing
        default:
            break
        }
    }

    func seek(by seconds: Double) {
        guard let timeshift = state.timeshift else { return }
        seek(to: timeshift.target(seekingBy: seconds))
    }

    func seekToLive() {
        guard let timeshift = state.timeshift else { return }
        seek(to: timeshift.livePosition)
    }

    /// M5 L9: the phone's in-app volume.
    func setVolume(_ level: Int, muted: Bool) {
        volumeLevel = level
        volumeMuted = muted
        applyVolume()
    }

    func setAudible(_ audible: Bool) {
        self.audible = audible
        applyVolume()
    }

    func setBufferProfile(_ profile: BufferProfile) {
        bufferProfile = profile
        applyBufferProfile()
        updateStats()
    }

    func setHoldsSleepAssertion(_ holds: Bool) {
        holdsSleep = holds
        applySleepAssertion()
        updateStats()
    }

    private func applySleepAssertion() {
        sleep.hold(holdsSleep && (state.phase == .loading || state.phase == .playing))
    }

    // MARK: - Private

    private func applyVolume() {
        guard let mpv else { return }
        mpv.setString("volume", "\(volumeLevel)")
        mpv.setString("mute", volumeMuted || !audible ? "yes" : "no")
    }

    /// M7n step 4a: mpv's `video-sync=display-resample` needs the display's rate, which the render API never gives
    /// it. Set only when it changes; an unusable rate after a usable one clears the override (mpv then keeps audio
    /// timing, as before).
    private func applyDisplayRate(_ rate: Double?) {
        guard let mpv, rate != appliedDisplayRate else { return }
        appliedDisplayRate = rate
        mpv.setString("display-fps-override", DisplayRefresh.overrideValue(for: rate))
        if let rate {
            logger.notice("Display rate \(String(format: "%.2f", rate), privacy: .public) Hz (player \(self.index))")
        } else {
            logger.notice("Display rate unknown; no override (player \(self.index))")
        }
    }

    /// Takes effect on a playing stream; shrinking prunes the buffer (M6 Research).
    private func applyBufferProfile() {
        guard let mpv else { return }
        mpv.setString("demuxer-max-back-bytes", bufferProfile.backBytes)
        mpv.setString("demuxer-max-bytes", bufferProfile.forwardBytes)
    }

    private func seek(to position: Double) {
        mpv?.command(["seek", String(format: "%.3f", position), "absolute+keyframes"])
        pollTimeshift()
    }

    /// Never loadfile before the render context exists: with vo=libmpv there'd be no video output for that file.
    private func load(_ url: URL) {
        guard let videoView, videoView.videoLayer.isReady else {
            pendingURL = url
            return
        }
        pendingURL = nil
        resolveTask?.cancel()
        resolveTask = nil
        // M7c L27: the time to the first frame includes resolving.
        loadStartedAt = .now
        // M7j L6: an antenna stream is never resolved (a resolve is a GET, which takes a tuner).
        guard let resolver, !isDirect else {
            loadFile(url, original: url)
            return
        }
        // M7c L29: the CDN address at once if it was resolved ahead of time, else after resolving.
        if let resolved = resolver.cached(url) {
            loadFile(resolved, original: url)
            return
        }
        resolveTask = Task { [weak self] in
            let resolved = await resolver.resolve(url)
            guard !Task.isCancelled, let self, self.currentURL == url else { return }
            self.loadFile(resolved, original: url)
        }
    }

    private func loadFile(_ url: URL, original: URL) {
        loggedDecoder = false
        renderStuck.newLoad()
        liveEdge.reset()
        state.httpStatus = nil
        // M7j Q2: a load replaced before its first frame still reports its count.
        reportPreFrameNoise()
        preFrameNoise.reset()
        // M7j L6: an antenna stream never goes through the relay (it buffers whole bodies; a TS stream never ends).
        // Pre-release lows (a): every load of a playlist stream, retries included, goes through the relay while it
        // runs; straight from the provider only when the relay never started (or for a URL it doesn't carry).
        let relayed = isDirect ? nil : relay?.localURL(for: url)
        relayedURL = relayed == nil ? nil : url
        let route = Self.loadRoute(antenna: isDirect, relayServes: relayed != nil, isWebURL: RelayURLPolicy.isWebURL(url),
                                   relayHasRun: relay?.hasRun == true, relayRefused: relayRefused)
        if route == .refuse {
            logger.notice("Not loading straight from \(original.host() ?? "?", privacy: .public): the relay isn't running (player \(self.index))")
            state = .failed(from: state)
            onFailure?()
            return
        }
        mpv?.setString("pause", "no")
        mpv?.command(MPVLoadCommand.make(url: relayed ?? url, direct: isDirect))
        // M7c L27: notice, so `log show` keeps it. M7j L15: never the tuner's address.
        if isDirect {
            logger.notice("Loading a stream from the antenna tuner (player \(self.index))")
        } else {
            logger.notice("Loading a stream from \(original.host() ?? "?", privacy: .public) via \(url.host() ?? "?", privacy: .public)\(relayed == nil ? "" : " through the relay", privacy: .public) (player \(self.index))")
        }
    }

    /// M7h 13g: a pending URL loads as before. A replaced render context (the video view moved between hosts, e.g.
    /// Select on the home preview) left mpv's video track off, so a playing or loading stream is loaded again.
    private func videoContextReady(replacedContext: Bool) {
        if let url = pendingURL {
            load(url)
            return
        }
        guard Self.reloadsAfterContextChange(replaced: replacedContext, hasPending: false,
                                             hasCurrentURL: currentURL != nil, phase: state.phase),
              let url = currentURL
        else { return }
        logger.notice("Video GL context replaced while playing; reloading the stream (player \(self.index))")
        // The reload supersedes a waiting retry, which would load the same URL again.
        retryTask?.cancel()
        retryTask = nil
        load(url)
    }

    /// M7h 13g: whether a new render context should reload the current stream. Not while paused: reloading would drop
    /// the timeshift buffer and unpause.
    nonisolated static func reloadsAfterContextChange(replaced: Bool, hasPending: Bool, hasCurrentURL: Bool,
                                                      phase: PlayerState.Phase) -> Bool {
        guard replaced, !hasPending, hasCurrentURL else { return false }
        return phase == .loading || phase == .playing
    }

    private func handle(_ event: MPVEvent) {
        switch event {
        case .playbackRestart:
            if state.phase == .loading || state.phase == .playing {
                state.phase = .playing
            }
            reportPreFrameNoise()
            if let loadStartedAt {
                self.loadStartedAt = nil
                let elapsed = ContinuousClock.now - loadStartedAt
                let ms = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
                logger.notice("Playing after \(ms) ms (player \(self.index))")
            }
            // M7n step 3a: every playback restart (a load, a retry, a seek or a timeshift jump) starts a new stats
            // period, since mpv may start its counters over.
            updateStats(restart: true)
            if !loggedDecoder, let mpv {
                loggedDecoder = true
                // M7c L27: notice, so a fallback to software decoding ("no") shows in `log show`.
                logger.notice("Decoder \(mpv.string("hwdec-current") ?? "?", privacy: .public) (player \(self.index))")
            }
        case .endFile(let reason, let error):
            guard reason == .eof || reason == .error,
                  state.phase == .loading || state.phase == .playing,
                  let url = currentURL
            else { return }
            reportPreFrameNoise()
            logger.error("Stream ended (\(String(describing: reason), privacy: .public), error \(error)); retries used \(self.retries) (player \(self.index))")
            // M7c L29: the resolved address may have expired; the retry resolves again.
            if !isDirect { resolver?.invalidate(url) }
            // Re-review L2: after a refusal one relayed retry fewer (another would most likely be refused too).
            if let relayedURL, relay?.refusedSomething(forStreamOf: relayedURL) == true { relayRefused = true }
            if Self.shouldRetry(direct: isDirect, wasPlaying: state.phase == .playing, used: retries,
                                relayRefused: relayRefused) {
                retries += 1
                state.phase = .loading
                retryTask?.cancel()
                retryTask = Task { [weak self] in
                    try? await Task.sleep(for: Self.retryDelay)
                    guard !Task.isCancelled, let self, self.currentURL == url else { return }
                    self.load(url)
                }
            } else {
                state = .failed(from: state)
                onFailure?()
            }
        case .log(let level, let text):
            // M7n step 3a: vo_libmpv says this up to ~5 times a second while draws stall: the first of a load at
            // notice, the rest only counted in the stats line.
            if text.contains(MPVLogText.renderStuckText) {
                if renderStuck.note() {
                    logger.notice("mpv \(level, privacy: .public): \(MPVLogText.redacted(text), privacy: .public) (player \(self.index); more are counted in the stats line)")
                }
                return
            }
            // M7j L9: ffmpeg's "HTTP error 503 …" for the current load.
            if let status = MPVLogText.httpStatus(in: text) { state.httpStatus = status }
            // Warnings and errors only (`MPVLogText.forwards`; M7n step 3a: and vo_libmpv's verbose render-stuck
            // line); notice keeps them for `log show` (L27).
            // M7j L15: never a URL (tokens, the tuner's address). M7j Q2: a decoder's complaints before the first
            // frame (a stream joined mid-GOP) go to debug and are counted; after it they stay at notice.
            if preFrameNoise.absorbs(text) {
                logger.debug("mpv \(level, privacy: .public): \(MPVLogText.redacted(text), privacy: .public)")
            } else {
                logger.notice("mpv \(level, privacy: .public): \(MPVLogText.redacted(text), privacy: .public)")
            }
        case .fileLoaded, .shutdown:
            break
        }
    }

    /// M7j Q2: one notice line for the decoder warnings logged at debug before the first frame, if there were any.
    private func reportPreFrameNoise() {
        guard let count = preFrameNoise.finish() else { return }
        logger.notice("\(count) decoder warnings before the first frame (player \(self.index))")
    }

    /// Whether an ended stream is loaded again. A playlist stream: `maxRetries` times per `play`, each one through
    /// the relay while it runs (`loadRoute`; pre-release lows (a): no last retry straight from the CDN, which a
    /// provider answering mpv differently from the relay could steer to LAN hosts), one fewer (re-review L2) after
    /// the relay refused a URI or a redirect for the stream (`relayRefused`). M7j L6: an antenna stream only when it
    /// was playing, once per `play`; one that never played fails at once, so the diagnosis follows a single tuner
    /// answer (L9).
    nonisolated static func shouldRetry(direct: Bool, wasPlaying: Bool, used: Int, relayRefused: Bool = false) -> Bool {
        if direct { return wasPlaying && used < directReconnects }
        return used < (relayRefused ? maxRetries - 1 : maxRetries)
    }

    nonisolated enum LoadRoute: Equatable, Sendable {
        /// Through the loopback relay.
        case relay
        /// mpv fetches the URL itself.
        case direct
        /// Not loaded: the stream fails.
        case refuse
    }

    /// How a load (first or retry; the retry count plays no part) reaches mpv. Pre-release lows (a): an antenna stream
    /// directly (M7j L6); a playlist stream through the relay whenever it serves the URL; straight from the provider
    /// only for a URL the relay doesn't carry (not http(s)) or when the relay never ran since launch and refused
    /// nothing for the stream. A relay that ran and stopped fails the load rather than let mpv fetch on its own.
    nonisolated static func loadRoute(antenna: Bool, relayServes: Bool, isWebURL: Bool, relayHasRun: Bool,
                                      relayRefused: Bool) -> LoadRoute {
        if antenna { return .direct }
        if relayServes { return .relay }
        if !isWebURL { return .direct }
        return relayHasRun || relayRefused ? .refuse : .direct
    }

    private func phaseDidChange() {
        applySleepAssertion()
        updateStats()
        let polls = state.phase == .playing || state.phase == .paused
        if polls, pollTimer == nil {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pollTimeshift() }
            }
        } else if !polls {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    private func pollTimeshift() {
        guard let mpv else { return }
        pollFormat(mpv)
        guard let position = mpv.double("time-pos"), let json = mpv.string("demuxer-cache-state"),
              var timeshift = Timeshift.parse(cacheStateJSON: json, timePos: position)
        else { return }
        timeshift.liveEdge = liveEdge.liveEdge(cacheEnd: timeshift.cacheEnd, position: position,
                                               now: ProcessInfo.processInfo.systemUptime,
                                               steady: state.phase == .playing)
        if timeshift != state.timeshift { state.timeshift = timeshift }
    }

    // MARK: - M7n step 3a: playback stats

    /// Stats are logged only for the full-screen player while it plays: not a Multiview window (`.tile`) and not the
    /// home screen's muted preview (which doesn't hold the sleep assertion).
    nonisolated static func logsStats(phase: PlayerState.Phase, profile: BufferProfile, holdsSleepAssertion: Bool) -> Bool {
        phase == .playing && profile == .full && holdsSleepAssertion
    }

    /// Starts or stops the stats period as the player's role changes; `restart` begins a new period while it runs.
    private func updateStats(restart: Bool = false) {
        guard Self.logsStats(phase: state.phase, profile: bufferProfile, holdsSleepAssertion: holdsSleep) else {
            stopStats()
            return
        }
        guard restart || statsTimer == nil else { return }
        statsTimer?.invalidate()
        statsGeneration += 1
        statsBaseline = nil
        // Also starts the render timings' period.
        sampleStats(logging: false)
        statsTimer = Timer.scheduledTimer(withTimeInterval: PlaybackStats.period, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleStats(logging: true) }
        }
    }

    private func stopStats() {
        guard statsTimer != nil else { return }
        statsTimer?.invalidate()
        statsTimer = nil
        statsGeneration += 1
        statsBaseline = nil
    }

    /// The render timings are taken here; mpv's properties are read off the main thread (a read waits for the core).
    private func sampleStats(logging: Bool) {
        guard let mpv else { return }
        // The baseline read (not logged) starts a new period, without the gap across the restart.
        let render = videoView?.videoLayer.takeRenderTimings(restart: !logging) ?? PlaybackStats.RenderTimings()
        let stuck = renderStuck.take()
        let generation = statsGeneration
        Task.detached(priority: .utility) { [weak self] in
            let sample = PlaybackStats.read(mpv)
            await self?.statsSampled(sample, render: render, stuck: stuck, generation: generation, logging: logging)
        }
    }

    private func statsSampled(_ sample: PlaybackStats.Sample, render: PlaybackStats.RenderTimings, stuck: Int,
                              generation: Int, logging: Bool) {
        guard generation == statsGeneration else { return }
        let previous = statsBaseline
        statsBaseline = sample.counters
        guard logging, let previous else { return }
        // Notice, so `log show` keeps it. Numbers and mpv's decoder name only.
        let line = PlaybackStats.line(player: index, sample: sample, previous: previous, render: render, stuck: stuck)
        logger.notice("\(line, privacy: .public)")
    }

    /// M7f L3: mpv's values as they are (no field/frame conversion); a variant change shows within one poll.
    private func pollFormat(_ mpv: MPVHandle) {
        let format = VideoFormat.parse(width: mpv.string("video-params/w"), height: mpv.string("video-params/h"),
                                       fps: mpv.string("container-fps") ?? mpv.string("estimated-vf-fps"),
                                       interlaced: mpv.string("video-frame-info/interlaced"))
        if format != state.videoFormat { state.videoFormat = format }
        if !loggedFormat, let format {
            loggedFormat = true
            // Notice, so M7f step 4 can read it with `log show`.
            logger.notice("Format \(format.label, privacy: .public) (player \(self.index))")
        }
    }
}
