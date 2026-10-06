import Foundation
import Observation
import os

enum LiveTVOutcome: Equatable { case handled, leave, openSettings }

/// What the router needs; tests use a fake.
protocol LiveTVHosting: AnyObject {
    func open()
    func leave()
    func handle(_ command: RemoteCommand) -> LiveTVOutcome
}

/// The Live TV screen: modes, channel zapping, overlays and command handling (L9, L11, L13).
@Observable
final class LiveTVModel: LiveTVHosting {
    enum Mode: Equatable { case setupNeeded, loading, player, guide, unavailable(String) }
    struct Banner: Equatable {
        var channel: Channel
        var now: Programme?
        var next: Programme?
    }

    static let playbackErrorMessage = "Can't play this channel"
    static let shortSkip: Double = 10
    static let longSkip: Double = 30

    private(set) var mode: Mode = .loading
    private(set) var currentChannel: Channel?
    private(set) var banner: Banner?
    private(set) var showsTimeshiftBar = false
    /// "Can't play this channel"
    private(set) var playbackError: String?
    private(set) var guide: GuideModel?
    let player: any LivePlayer
    let library: IPTVLibrary
    /// The last async work started by open()/commands; tests await it.
    @ObservationIgnored private(set) var pendingTask: Task<Void, Never>?
    @ObservationIgnored private let now: () -> Date
    /// 5 s; tests assert state right after a command, never wait for hiding.
    @ObservationIgnored private let overlayDuration: Duration
    @ObservationIgnored private var refreshedAfterFailure = false
    @ObservationIgnored private var bannerGeneration = 0
    @ObservationIgnored private var barGeneration = 0
    @ObservationIgnored private let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "IPTV")

    init(player: any LivePlayer, library: IPTVLibrary, now: @escaping () -> Date = Date.init,
         overlayDuration: Duration = .seconds(5)) {
        self.player = player
        self.library = library
        self.now = now
        self.overlayDuration = overlayDuration
        player.onFailure = { [weak self] in self?.playerFailed() }
    }

    // MARK: - LiveTVHosting

    func open() {
        pendingTask?.cancel()
        playbackError = nil
        guard library.hasPlaylist else {
            mode = .setupNeeded
            return
        }
        // Shown while the playlist is checked (instant when it is fresh).
        mode = .loading
        let library = library
        Task { await library.refreshGuideIfStale() }
        pendingTask = Task {
            await library.refreshPlaylistIfStale()
            guard !Task.isCancelled else { return }
            guard !library.channels.isEmpty else {
                if case .failed(let message) = library.playlistStatus {
                    mode = .unavailable(message)
                } else {
                    mode = .unavailable("The playlist has no channels")
                }
                return
            }
            if let id = library.state.lastChannelID, let channel = library.channels.first(where: { $0.id == id }) {
                play(channel)
            } else {
                openGuide()
            }
        }
    }

    /// Keeps `currentChannel` so the guide can focus it later.
    func leave() {
        pendingTask?.cancel()
        pendingTask = nil
        player.stop()
        guide = nil
        banner = nil
        showsTimeshiftBar = false
        playbackError = nil
        bannerGeneration += 1
        barGeneration += 1
    }

    func handle(_ command: RemoteCommand) -> LiveTVOutcome {
        if command == .home { return .leave }
        switch mode {
        case .setupNeeded:
            switch command {
            case .select: return .openSettings
            case .back: return .leave
            default: return .handled
            }
        case .unavailable:
            switch command {
            case .select:
                open()
                return .handled
            case .back: return .leave
            default: return .handled
            }
        case .loading:
            return command == .back ? .leave : .handled
        case .player:
            return handlePlayer(command)
        case .guide:
            return handleGuide(command)
        }
    }

    /// The view calls this when `library.guideRevision` changes.
    func guideDataChanged() {
        guard mode == .guide else { return }
        loadProgrammes()
    }

    /// The view calls this when `library.channels` changes.
    func channelsChanged() {
        guide?.setChannels(allChannels: library.channels)
        if mode == .guide { loadProgrammes() }
    }

    /// The playing channel can return to full screen.
    private var isPlaying: Bool {
        currentChannel != nil && player.state.phase != .idle && player.state.phase != .failed
    }

    // MARK: - Player mode

    private func handlePlayer(_ command: RemoteCommand) -> LiveTVOutcome {
        switch command {
        case .up: zap(-1)
        case .down: zap(1)
        case .left: seek(-Self.shortSkip)
        case .right: seek(Self.shortSkip)
        case .rewind: seek(-Self.longSkip)
        case .fastForward: seek(Self.longSkip)
        case .playPause:
            player.togglePause()
            showTimeshiftBar()
        case .select:
            if playbackError != nil, let channel = currentChannel {
                play(channel)
            } else {
                openGuide()
            }
        case .back:
            guard banner != nil || showsTimeshiftBar else { return .leave }
            hideOverlays()
        case .home:
            return .leave
        }
        return .handled
    }

    private func play(_ channel: Channel) {
        currentChannel = channel
        playbackError = nil
        refreshedAfterFailure = false
        player.play(channel.streamURL)
        library.rememberChannel(channel.id)
        mode = .player
        guide = nil
        showBanner()
    }

    // MARK: - Guide mode

    private func handleGuide(_ command: RemoteCommand) -> LiveTVOutcome {
        if command == .playPause {
            player.togglePause()
            return .handled
        }
        guard var guide else { return .leave }
        let action = guide.handle(command, now: now())
        self.guide = guide
        switch action {
        case .none:
            break
        case .play(let id):
            guard let channel = library.channels.first(where: { $0.id == id }) else { break }
            if channel.id == currentChannel?.id && isPlaying {
                mode = .player
                self.guide = nil
                showBanner()
            } else {
                play(channel)
            }
        case .groupChanged(let group):
            library.rememberGroup(group)
            loadProgrammes()
        case .close:
            guard isPlaying else { return .leave }
            mode = .player
            self.guide = nil
        }
        return .handled
    }

    private func openGuide() {
        guide = GuideModel(allChannels: library.channels, group: library.state.lastGroup,
                           focusedChannelID: currentChannel?.id, now: now())
        mode = .guide
        hideOverlays()
        loadProgrammes()
    }

    /// [now − 1 h, now + 24 h] for the guide's channels, kept only if the guide still shows the same group.
    private func loadProgrammes() {
        guard let guide else { return }
        let group = guide.selectedGroup
        let channels = guide.channels
        let date = now()
        let library = library
        pendingTask = Task {
            let interval = DateInterval(start: date - 3600, end: date + GuideTimeline.horizon)
            let programmes = await library.programmes(for: channels, in: interval)
            guard !Task.isCancelled, self.guide?.selectedGroup == group else { return }
            self.guide?.programmes = programmes
        }
    }

    /// Up/Down: previous/next channel in the remembered group if it holds the current channel, else its own group. Wraps.
    private func zap(_ step: Int) {
        guard let current = currentChannel else { return }
        let all = library.channels
        var list = ChannelList.channels(in: current.group, of: all)
        if let group = library.state.lastGroup {
            let remembered = ChannelList.channels(in: group, of: all)
            if remembered.contains(where: { $0.id == current.id }) { list = remembered }
        }
        guard list.count > 1, let index = list.firstIndex(where: { $0.id == current.id }) else { return }
        play(list[(index + step + list.count) % list.count])
    }

    private func seek(_ seconds: Double) {
        player.seek(by: seconds)
        showTimeshiftBar()
    }

    private func hideOverlays() {
        banner = nil
        showsTimeshiftBar = false
        bannerGeneration += 1
        barGeneration += 1
    }

    /// The banner shows the channel at once, then its now/next, and hides after `overlayDuration`.
    private func showBanner() {
        guard let channel = currentChannel else { return }
        bannerGeneration += 1
        let generation = bannerGeneration
        banner = Banner(channel: channel)
        let library = library
        let date = now()
        let duration = overlayDuration
        Task {
            let (current, next) = await library.nowNext(for: channel, at: date)
            guard bannerGeneration == generation, banner?.channel.id == channel.id else { return }
            banner?.now = current
            banner?.next = next
            try? await Task.sleep(for: duration)
            if bannerGeneration == generation { banner = nil }
        }
    }

    /// Hides after `overlayDuration`; the view keeps it while paused.
    private func showTimeshiftBar() {
        barGeneration += 1
        let generation = barGeneration
        showsTimeshiftBar = true
        let duration = overlayDuration
        Task {
            try? await Task.sleep(for: duration)
            if barGeneration == generation { showsTimeshiftBar = false }
        }
    }

    /// L13: after the player's own retries, refresh the playlist once (tokens may have rotated), then give up.
    private func playerFailed() {
        guard let channel = currentChannel else { return }
        guard !refreshedAfterFailure else {
            playbackError = Self.playbackErrorMessage
            logger.error("Can't play \(channel.name, privacy: .public)")
            return
        }
        refreshedAfterFailure = true
        let library = library
        pendingTask = Task {
            await library.refreshPlaylist()
            guard !Task.isCancelled, currentChannel?.id == channel.id else { return }
            let fresh = library.channels.first { $0.id == channel.id } ?? channel
            currentChannel = fresh
            player.play(fresh.streamURL)
        }
    }
}
