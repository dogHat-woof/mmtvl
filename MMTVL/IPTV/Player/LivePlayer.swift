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
    /// M7c L30: mpv loads through the loopback relay (nil, or not running = straight from the CDN).
    @ObservationIgnored var relay: HLSRelay? = .shared

    @ObservationIgnored private var mpv: MPVHandle?
    @ObservationIgnored private var currentURL: URL?
    /// M7j L6: the current stream is an antenna stream.
    @ObservationIgnored private var isDirect = false
    @ObservationIgnored private var pendingURL: URL?
    @ObservationIgnored private var retries = 0
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
    @ObservationIgnored private let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "MPV")

    init() {
        index = Self.nextIndex
        Self.nextIndex += 1
    }

    /// Creates the core and view without playing, so the view can get its GL context early.
    func prepare() {
        guard mpv == nil else { return }
        do {
            let mpv = try MPVHandle(options: MPVOptions.all) { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
            self.mpv = mpv
            if volumeLevel != 100 || volumeMuted || !audible { applyVolume() }
            if bufferProfile != .full { applyBufferProfile() }
            let view = MPVVideoView(mpv: mpv)
            view.videoLayer.onReady = { [weak self] replacedContext in
                Task { @MainActor in self?.videoContextReady(replacedContext: replacedContext) }
            }
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
    }

    func setHoldsSleepAssertion(_ holds: Bool) {
        holdsSleep = holds
        applySleepAssertion()
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
        liveEdge.reset()
        state.httpStatus = nil
        // M7j Q2: a load replaced before its first frame still reports its count.
        reportPreFrameNoise()
        preFrameNoise.reset()
        // M7c L30: the last retry goes straight to the CDN, in case the relay is the problem. M7j L6: an antenna
        // stream never goes through the relay (it buffers whole bodies; a TS stream never ends).
        let relayed = !isDirect && retries < Self.maxRetries ? relay?.localURL(for: url) : nil
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
            if Self.shouldRetry(direct: isDirect, wasPlaying: state.phase == .playing, used: retries) {
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
            // M7j L9: ffmpeg's "HTTP error 503 …" for the current load.
            if let status = MPVLogText.httpStatus(in: text) { state.httpStatus = status }
            // Warnings and errors only (`mpv_request_log_messages("warn")`); notice keeps them for `log show` (L27).
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

    /// Whether an ended stream is loaded again. A playlist stream: `maxRetries` times per `play`. M7j L6: an antenna
    /// stream only when it was playing, once per `play`; one that never played fails at once, so the diagnosis
    /// follows a single tuner answer (L9).
    nonisolated static func shouldRetry(direct: Bool, wasPlaying: Bool, used: Int) -> Bool {
        direct ? wasPlaying && used < directReconnects : used < maxRetries
    }

    private func phaseDidChange() {
        applySleepAssertion()
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
