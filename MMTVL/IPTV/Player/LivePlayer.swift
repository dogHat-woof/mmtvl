import Foundation
import Observation
import os

nonisolated struct PlayerState: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case idle, loading, playing, paused, failed }
    var phase: Phase = .idle
    var timeshift: Timeshift?
}

/// What `LiveTVModel` needs from a player; tests use a fake.
protocol LivePlayer: AnyObject {
    var state: PlayerState { get }
    /// After retries are exhausted (L13). Set by LiveTVModel.
    var onFailure: (() -> Void)? { get set }
    func play(_ url: URL)
    func stop()
    func togglePause()
    func seek(by seconds: Double)
    func seekToLive()
}

/// The single mpv core (L7) and its video view.
@Observable
final class MPVPlayerController: LivePlayer {
    static let maxRetries = 2
    static let retryDelay: Duration = .seconds(2)

    private(set) var state = PlayerState() {
        didSet {
            if state.phase != oldValue.phase { phaseDidChange() }
        }
    }
    /// Created with the mpv core on first use; LiveTVRootView hosts it.
    private(set) var videoView: MPVVideoView?
    @ObservationIgnored var onFailure: (() -> Void)?

    @ObservationIgnored private var mpv: MPVHandle?
    @ObservationIgnored private var currentURL: URL?
    @ObservationIgnored private var pendingURL: URL?
    @ObservationIgnored private var retries = 0
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var liveEdge = LiveEdgeSmoother()
    @ObservationIgnored private let sleep = SleepAssertion()
    /// MMTVL's own volume (M5 L9), kept across cores and files.
    @ObservationIgnored private var volumeLevel = 100
    @ObservationIgnored private var volumeMuted = false
    @ObservationIgnored private let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "MPV")

    /// Creates the core and view without playing, so the view can get its GL context early.
    func prepare() {
        guard mpv == nil else { return }
        do {
            let mpv = try MPVHandle(options: MPVOptions.all) { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
            self.mpv = mpv
            if volumeLevel != 100 || volumeMuted { applyVolume() }
            let view = MPVVideoView(mpv: mpv)
            view.videoLayer.onReady = { [weak self] in
                Task { @MainActor in self?.loadPending() }
            }
            videoView = view
            logger.info("mpv core created")
        } catch {
            logger.error("Creating the mpv core failed: \(String(describing: error), privacy: .public)")
            state.phase = .failed
        }
    }

    func play(_ url: URL) {
        prepare()
        guard mpv != nil else {
            onFailure?()
            return
        }
        retryTask?.cancel()
        retries = 0
        currentURL = url
        state = PlayerState(phase: .loading, timeshift: nil)
        load(url)
    }

    func stop() {
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

    /// M5 L9: the phone's in-app volume. Not on `LivePlayer`; AppDelegate calls the concrete class.
    func setVolume(_ level: Int, muted: Bool) {
        volumeLevel = level
        volumeMuted = muted
        applyVolume()
    }

    // MARK: - Private

    private func applyVolume() {
        guard let mpv else { return }
        mpv.setString("volume", "\(volumeLevel)")
        mpv.setString("mute", volumeMuted ? "yes" : "no")
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
        liveEdge.reset()
        mpv?.setString("pause", "no")
        mpv?.command(["loadfile", url.absoluteString, "replace"])
        logger.info("Loading a stream from \(url.host() ?? "?", privacy: .public)")
    }

    private func loadPending() {
        guard let url = pendingURL else { return }
        load(url)
    }

    private func handle(_ event: MPVEvent) {
        switch event {
        case .playbackRestart:
            if state.phase == .loading || state.phase == .playing {
                state.phase = .playing
            }
        case .endFile(let reason, let error):
            guard reason == .eof || reason == .error,
                  state.phase == .loading || state.phase == .playing,
                  let url = currentURL
            else { return }
            logger.error("Stream ended (\(String(describing: reason), privacy: .public), error \(error)); retries used \(self.retries)")
            if retries < Self.maxRetries {
                retries += 1
                state.phase = .loading
                retryTask?.cancel()
                retryTask = Task { [weak self] in
                    try? await Task.sleep(for: Self.retryDelay)
                    guard !Task.isCancelled, let self, self.currentURL == url else { return }
                    self.load(url)
                }
            } else {
                state = PlayerState(phase: .failed, timeshift: nil)
                onFailure?()
            }
        case .log(let level, let text):
            logger.info("mpv \(level, privacy: .public): \(text, privacy: .public)")
        case .fileLoaded, .shutdown:
            break
        }
    }

    private func phaseDidChange() {
        sleep.hold(state.phase == .loading || state.phase == .playing)
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
        guard let mpv, let position = mpv.double("time-pos"), let json = mpv.string("demuxer-cache-state"),
              var timeshift = Timeshift.parse(cacheStateJSON: json, timePos: position)
        else { return }
        timeshift.liveEdge = liveEdge.liveEdge(cacheEnd: timeshift.cacheEnd, position: position,
                                               now: ProcessInfo.processInfo.systemUptime,
                                               steady: state.phase == .playing)
        if timeshift != state.timeshift { state.timeshift = timeshift }
    }
}
