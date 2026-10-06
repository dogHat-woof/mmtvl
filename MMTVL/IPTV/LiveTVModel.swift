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

/// The Live TV screen: modes, channel zapping, overlays and command handling (M4 L9, L11, L13),
/// and Multiview with its player pool (M6).
@Observable
final class LiveTVModel: LiveTVHosting {
    enum Mode: Equatable { case setupNeeded, loading, player, guide, multiview, unavailable(String) }
    /// The guide watches channels, or picks one for a Multiview window (M6 L11).
    enum GuidePurpose: Equatable { case watch, pick(slot: Int) }
    struct Banner: Equatable {
        var channel: Channel
        var now: Programme?
        var next: Programme?
    }
    /// Where a player's video goes (M6 L15). The view only draws these.
    struct VideoPlacement: Identifiable {
        let player: any LivePlayer
        var id: ObjectIdentifier { ObjectIdentifier(player) }
        /// nil = the whole window.
        var canvasRect: CGRect?
        var isVisible: Bool
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
    /// A menu over Live TV (M6 L10); it takes every command but Home while open.
    private(set) var menu: LiveMenu?
    /// The full-screen player. Multiview hands it between pool players (M6 L12).
    private(set) var player: any LivePlayer
    private(set) var guidePurpose: GuidePurpose = .watch
    /// Non-nil in `.multiview` and in the picker guide.
    private(set) var multiview: MultiviewModel?
    /// Each Multiview window's player.
    private(set) var tilePlayers: [Channel.ID: any LivePlayer] = [:]
    /// Windows that failed after their playlist refresh (M6 L14).
    private(set) var failedWindows: Set<Channel.ID> = []
    let library: IPTVLibrary
    /// The last async work started by open()/commands; tests await it.
    @ObservationIgnored private(set) var pendingTask: Task<Void, Never>?
    @ObservationIgnored private let now: () -> Date
    /// 5 s; tests assert state right after a command, never wait for hiding.
    @ObservationIgnored private let overlayDuration: Duration
    @ObservationIgnored private var refreshedAfterFailure = false
    /// The pool (M6 L2); players[0] is the init player. Never shrinks.
    @ObservationIgnored private var players: [any LivePlayer]
    @ObservationIgnored private let makePlayer: () -> any LivePlayer
    @ObservationIgnored private var refreshedWindows: Set<Channel.ID> = []
    @ObservationIgnored private var appVolume: (level: Int, muted: Bool)?
    @ObservationIgnored private var bannerGeneration = 0
    @ObservationIgnored private var barGeneration = 0
    @ObservationIgnored private let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "IPTV")

    init(player: any LivePlayer, makePlayer: @escaping () -> any LivePlayer, library: IPTVLibrary,
         now: @escaping () -> Date = Date.init, overlayDuration: Duration = .seconds(5)) {
        self.player = player
        self.makePlayer = makePlayer
        self.library = library
        self.now = now
        self.overlayDuration = overlayDuration
        players = [player]
        configure(player)
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
            if let snapshot = library.state.multiview, snapshot.isActive {
                let multiview = MultiviewModel(snapshot: snapshot, validIDs: Set(library.channels.map(\.id)))
                if !multiview.isEmpty {
                    startMultiview(multiview, reusing: nil)
                    return
                }
                var inactive = snapshot
                inactive.isActive = false
                library.rememberMultiview(inactive)
            }
            if let id = library.state.lastChannelID, let channel = library.channels.first(where: { $0.id == id }) {
                play(channel)
            } else {
                openGuide()
            }
        }
    }

    /// Keeps `currentChannel` so the guide can focus it later, and the Multiview snapshot (M6 L13).
    func leave() {
        pendingTask?.cancel()
        pendingTask = nil
        if multiview != nil { saveSnapshot(true) }
        for player in players { release(player) }
        player.setBufferProfile(.full)
        tilePlayers = [:]
        failedWindows = []
        refreshedWindows = []
        multiview = nil
        guidePurpose = .watch
        guide = nil
        menu = nil
        banner = nil
        showsTimeshiftBar = false
        playbackError = nil
        bannerGeneration += 1
        barGeneration += 1
    }

    func handle(_ command: RemoteCommand) -> LiveTVOutcome {
        if command == .home { return .leave }
        if var menu {
            let outcome = menu.handle(command)
            self.menu = menu
            switch outcome {
            case .none:
                break
            case .close:
                self.menu = nil
            case .choose(let action):
                self.menu = nil
                perform(action)
            }
            return .handled
        }
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
        case .multiview:
            return handleMultiview(command)
        }
    }

    /// Phone in-app volume (D25): every pool player, and players created later.
    func setAppVolume(_ level: Int, muted: Bool) {
        appVolume = (level, muted)
        for player in players { player.setVolume(level, muted: muted) }
    }

    /// M6 L15.
    var videoPlacements: [VideoPlacement] {
        switch mode {
        case .player:
            return [VideoPlacement(player: player, canvasRect: nil, isVisible: true)]
        case .guide:
            guard case .pick = guidePurpose, let multiview else {
                return [VideoPlacement(player: player, canvasRect: Theme.guidePreviewRect, isVisible: true)]
            }
            // The window with sound is the preview; the others keep playing, invisible, so their GL contexts survive.
            return multiview.slots.enumerated().compactMap { slot, id in
                guard let id, let player = tilePlayers[id] else { return nil }
                let isPreview = id == multiview.audioChannelID
                return VideoPlacement(player: player,
                                      canvasRect: isPreview ? Theme.guidePreviewRect : multiview.layout.slots[slot],
                                      isVisible: isPreview)
            }
        case .multiview:
            guard let multiview else { return [] }
            return multiview.slots.enumerated().compactMap { slot, id in
                guard let id, let player = tilePlayers[id] else { return nil }
                return VideoPlacement(player: player, canvasRect: multiview.layout.slots[slot], isVisible: true)
            }
        case .setupNeeded, .loading, .unavailable:
            return [VideoPlacement(player: player, canvasRect: nil, isVisible: false)]
        }
    }

    /// The window with sound in the picker guide, else `player`.
    var previewPlayer: any LivePlayer {
        if case .pick = guidePurpose, let id = multiview?.audioChannelID, let player = tilePlayers[id] { return player }
        return player
    }

    /// The guide's "playing" mark: the window with sound in the picker guide, else currentChannel.
    var previewChannel: Channel? {
        if case .pick = guidePurpose { return multiview?.audioChannelID.flatMap(self.channel) }
        return currentChannel
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

    private func channel(_ id: Channel.ID) -> Channel? {
        library.channels.first { $0.id == id }
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
            previewPlayer.togglePause()
            return .handled
        }
        guard var guide else { return .leave }
        let action = guide.handle(command, now: now())
        self.guide = guide
        switch action {
        case .none:
            break
        case .play(let id):
            if case .pick(let slot) = guidePurpose {
                assignWindow(id, to: slot)
                closePicker()
            } else {
                watch(id)
            }
        case .channelMenu(let id):
            if case .pick(let slot) = guidePurpose {
                assignWindow(id, to: slot)
                closePicker()
            } else {
                menu = channelMenu(for: id)
            }
        case .groupChanged(let group):
            library.rememberGroup(group)
            loadProgrammes()
        case .close:
            if case .pick = guidePurpose {
                closePicker()
                break
            }
            guard isPlaying else { return .leave }
            mode = .player
            self.guide = nil
        }
        return .handled
    }

    /// The watch guide's Select: full screen on that channel, without reloading the one already playing.
    private func watch(_ id: Channel.ID) {
        guard let channel = library.channels.first(where: { $0.id == id }) else { return }
        if channel.id == currentChannel?.id && isPlaying {
            mode = .player
            guide = nil
            showBanner()
        } else {
            play(channel)
        }
    }

    // MARK: - Menus

    /// M6 L8: the guide's channel menu.
    private func channelMenu(for id: Channel.ID) -> LiveMenu? {
        guard let channel = library.channels.first(where: { $0.id == id }) else { return nil }
        let isShown = library.state.multiview?.slots.contains(id) == true
        return LiveMenu(title: channel.name, items: [
            .init(id: "watch", title: "Watch", action: .watch(id)),
            .init(id: "addToMultiview", title: isShown ? "Show in Multiview" : "Add to Multiview", action: .addToMultiview(id)),
        ])
    }

    private func perform(_ action: LiveMenuAction) {
        switch action {
        case .watch(let id):
            watch(id)
        case .addToMultiview(let id):
            enterMultiview(adding: id)
        case .fullScreen:
            exitMultiview()
        case .makeMain:
            guard let slot = multiview?.focusedSlot else { return }
            multiview?.makeMain(slot)
            applyAudio()
            saveSnapshot(true)
        case .changeChannel:
            guard let slot = multiview?.focusedSlot else { return }
            openPicker(slot: slot)
        case .retryWindow:
            guard let id = multiview?.focusedChannelID, let channel = channel(id) else { return }
            failedWindows.remove(id)
            refreshedWindows.remove(id)
            tilePlayers[id]?.play(channel.streamURL)
        case .chooseLayout:
            menu = layoutMenu()
        case .setLayout(let layout):
            for id in multiview?.setLayout(layout) ?? [] {
                if let player = tilePlayers.removeValue(forKey: id) { release(player) }
                failedWindows.remove(id)
                refreshedWindows.remove(id)
            }
            applyAudio()
            saveSnapshot(true)
        case .removeWindow:
            guard let slot = multiview?.focusedSlot else { return }
            removeWindow(slot)
        }
    }

    /// M6 L10, for the highlighted window.
    private func windowMenu() -> LiveMenu? {
        guard let multiview, let id = multiview.focusedChannelID else { return nil }
        let layout = multiview.layout
        var items: [LiveMenu.Item] = [.init(id: "fullScreen", title: "Full Screen", action: .fullScreen)]
        if let main = layout.mainSlot, multiview.focusedSlot != main {
            items.append(.init(id: "makeMain", title: "Make Main", action: .makeMain))
        }
        items.append(.init(id: "changeChannel", title: "Change Channel", action: .changeChannel))
        if failedWindows.contains(id) {
            items.append(.init(id: "retry", title: "Retry", action: .retryWindow))
        }
        items.append(.init(id: "layout", title: "Layout", value: layout.title, action: .chooseLayout))
        items.append(.init(id: "remove", title: "Remove", action: .removeWindow))
        return LiveMenu(title: channel(id)?.name ?? "", items: items)
    }

    private func layoutMenu() -> LiveMenu? {
        guard let current = multiview?.layout else { return nil }
        let layouts = MultiviewLayout.allCases
        return LiveMenu(title: "Layout",
                        items: layouts.map { layout in
                            .init(id: "layout.\(layout.rawValue)", title: layout.title,
                                  value: layout == current ? "Current" : nil, layout: layout, action: .setLayout(layout))
                        },
                        focusedIndex: layouts.firstIndex(of: current) ?? 0)
    }

    // MARK: - Player pool (M6 L2)

    private func configure(_ player: any LivePlayer) {
        player.onFailure = { [weak self, weak player] in
            if let player { self?.playerFailed(player) }
        }
        if let appVolume { player.setVolume(appVolume.level, muted: appVolume.muted) }
    }

    /// An idle pool player, or a new one while the pool has fewer than five.
    private func acquirePlayer() -> (any LivePlayer)? {
        if let idle = players.first(where: { candidate in !tilePlayers.values.contains { $0 === candidate } }) {
            return idle
        }
        guard players.count < MultiviewModel.maxWindows else {
            logger.error("No free player for a Multiview window")
            return nil
        }
        let player = makePlayer()
        configure(player)
        players.append(player)
        return player
    }

    /// Stops it; it stays in the pool.
    private func release(_ player: any LivePlayer) {
        player.stop()
        player.setAudible(true)
    }

    // MARK: - Multiview (M6)

    private func enterMultiview(adding id: Channel.ID) {
        let current = isPlaying ? currentChannel?.id : nil
        let multiview = MultiviewModel.entering(snapshot: library.state.multiview, current: current, adding: id,
                                                validIDs: Set(library.channels.map(\.id)))
        startMultiview(multiview, reusing: current)
    }

    /// The channel playing now keeps its player and buffer (L12); the other windows start on pool players.
    private func startMultiview(_ multiview: MultiviewModel, reusing current: Channel.ID?) {
        guide = nil
        guidePurpose = .watch
        menu = nil
        hideOverlays()
        playbackError = nil
        tilePlayers = [:]
        failedWindows = []
        refreshedWindows = []
        if let current, multiview.slot(of: current) != nil {
            tilePlayers[current] = player
            player.setBufferProfile(.tile)
        } else {
            player.stop()
        }
        for id in multiview.channelIDs where tilePlayers[id] == nil {
            startWindow(id)
        }
        self.multiview = multiview
        mode = .multiview
        applyAudio()
        saveSnapshot(true)
        showWindowChip()
    }

    /// Plays `id` on a free pool player.
    private func startWindow(_ id: Channel.ID) {
        guard let channel = self.channel(id), let player = acquirePlayer() else { return }
        player.setBufferProfile(.tile)
        tilePlayers[id] = player
        player.play(channel.streamURL)
    }

    /// L5: only the window with sound is unmuted.
    private func applyAudio() {
        for (id, player) in tilePlayers {
            player.setAudible(id == multiview?.audioChannelID)
        }
    }

    private var focusedWindowPlayer: (any LivePlayer)? {
        multiview?.focusedChannelID.flatMap { tilePlayers[$0] }
    }

    /// L9.
    private func handleMultiview(_ command: RemoteCommand) -> LiveTVOutcome {
        switch command {
        case .up, .down, .left, .right:
            if let direction = MultiviewLayout.Direction(command), multiview?.moveFocus(direction) == true {
                applyAudio()
                showWindowChip()
            }
        case .select:
            guard let multiview else { break }
            if multiview.focusedChannelID != nil {
                menu = windowMenu()
            } else {
                openPicker(slot: multiview.focusedSlot)
            }
        case .playPause:
            focusedWindowPlayer?.togglePause()
            showTimeshiftBar()
        case .rewind:
            focusedWindowPlayer?.seek(by: -Self.longSkip)
            showTimeshiftBar()
        case .fastForward:
            focusedWindowPlayer?.seek(by: Self.longSkip)
            showTimeshiftBar()
        case .back:
            exitMultiview()
        case .home:
            return .leave
        }
        return .handled
    }

    /// L12: the highlighted window (else the one with sound, else the first) goes full screen without reconnecting.
    private func exitMultiview() {
        guard let multiview,
              let slot = [multiview.focusedSlot, multiview.audioSlot].compactMap({ $0 }).first(where: { multiview.slots[$0] != nil })
                ?? multiview.slots.firstIndex(where: { $0 != nil }),
              let id = multiview.slots[slot]
        else {
            removeAllWindows()
            return
        }
        let target = tilePlayers[id]
        for (otherID, other) in tilePlayers where otherID != id {
            release(other)
        }
        if let target {
            player = target
        }
        player.setBufferProfile(.full)
        player.setAudible(true)
        let channel = self.channel(id)
        currentChannel = channel ?? currentChannel
        library.rememberChannel(id)
        playbackError = failedWindows.contains(id) ? Self.playbackErrorMessage : nil
        refreshedAfterFailure = refreshedWindows.contains(id)
        saveSnapshot(false)
        self.multiview = nil
        tilePlayers = [:]
        failedWindows = []
        refreshedWindows = []
        guide = nil
        guidePurpose = .watch
        menu = nil
        mode = .player
        if target == nil, let channel {
            play(channel)
        } else {
            showBanner()
        }
    }

    /// L11: the guide picks the channel for `slot`; the window with sound is its preview.
    private func openPicker(slot: Int) {
        guard let multiview else { return }
        guide = GuideModel(allChannels: library.channels, group: library.state.lastGroup,
                           focusedChannelID: multiview.slots[slot] ?? multiview.audioChannelID, now: now())
        guidePurpose = .pick(slot: slot)
        mode = .guide
        hideOverlays()
        loadProgrammes()
    }

    private func closePicker() {
        guide = nil
        guidePurpose = .watch
        mode = .multiview
        showWindowChip()
    }

    /// L11. Releases the displaced channel's player before acquiring one, so a full 1 + 4 never needs a sixth.
    private func assignWindow(_ id: Channel.ID, to slot: Int) {
        guard multiview != nil else { return }
        if let displaced = multiview?.assign(id, to: slot) {
            if let player = tilePlayers.removeValue(forKey: displaced) { release(player) }
            failedWindows.remove(displaced)
            refreshedWindows.remove(displaced)
        }
        if tilePlayers[id] == nil { startWindow(id) }
        applyAudio()
        saveSnapshot(true)
    }

    private func removeWindow(_ slot: Int) {
        guard let id = multiview?.remove(slot) else { return }
        if let player = tilePlayers.removeValue(forKey: id) { release(player) }
        failedWindows.remove(id)
        refreshedWindows.remove(id)
        if multiview?.isEmpty != false {
            removeAllWindows()
        } else {
            applyAudio()
            saveSnapshot(true)
        }
    }

    /// Every window gone: nothing plays and the watch guide opens (L12).
    private func removeAllWindows() {
        for player in tilePlayers.values { release(player) }
        player.setBufferProfile(.full)
        tilePlayers = [:]
        failedWindows = []
        refreshedWindows = []
        multiview = nil
        library.rememberMultiview(nil)
        guidePurpose = .watch
        openGuide()
    }

    /// The banner as a chip on the highlighted window; none on an empty one.
    private func showWindowChip() {
        guard let channel = multiview?.focusedChannelID.flatMap(self.channel) else {
            bannerGeneration += 1
            banner = nil
            return
        }
        showBanner(for: channel)
    }

    private func saveSnapshot(_ active: Bool) {
        library.rememberMultiview(multiview?.snapshot(isActive: active))
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

    private func showBanner() {
        guard let channel = currentChannel else { return }
        showBanner(for: channel)
    }

    /// The banner shows the channel at once, then its now/next, and hides after `overlayDuration`.
    private func showBanner(for channel: Channel) {
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

    /// M4 L13: after the player's own retries, refresh the playlist once (tokens may have rotated), then give up.
    /// M6 L14: the same per Multiview window.
    private func playerFailed(_ failed: any LivePlayer) {
        if multiview != nil {
            guard let id = tilePlayers.first(where: { $0.value === failed })?.key else { return }   // a released player
            windowFailed(id, player: failed)
            return
        }
        guard failed === player, let channel = currentChannel else { return }
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

    private func windowFailed(_ id: Channel.ID, player failed: any LivePlayer) {
        guard !refreshedWindows.contains(id) else {
            failedWindows.insert(id)
            logger.error("Can't play \(self.channel(id)?.name ?? id, privacy: .public) in a window")
            return
        }
        refreshedWindows.insert(id)
        let library = library
        pendingTask = Task {
            await library.refreshPlaylist()
            guard !Task.isCancelled, tilePlayers[id] === failed, let fresh = channel(id) else { return }
            failed.play(fresh.streamURL)
        }
    }
}
