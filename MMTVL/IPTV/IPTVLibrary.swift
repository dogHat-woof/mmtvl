import CryptoKit
import Foundation
import Observation
import os

/// Live TV data: channels (in memory, D23), guides (SQLite, D8), refresh policy (L4, L5), guide sources (M6b L1).
@Observable
final class IPTVLibrary {
    enum Status: Equatable { case idle, loading, loaded(Date), failed(String) }
    enum AddGuideProblem: Equatable { case duplicate, full }
    struct GuideSourceInfo: Equatable {
        var status: Status = .idle
        var programmeCount = 0
        var matchedChannels = 0
    }

    static let playlistStaleness: TimeInterval = 10 * 60
    static let guideStaleness: TimeInterval = 12 * 3600
    /// M7f L5 (D40): while MMTVL runs, `refreshIfStale()` runs this often (and after wake).
    static let autoRefreshInterval: TimeInterval = 15 * 60
    static let maxGuideSources = 6

    private(set) var channels: [Channel] = []
    private(set) var playlistStatus: Status = .idle
    private(set) var guideStatus: Status = .idle
    private(set) var guideProgrammeCount = 0
    /// Bumped after every guide import or rematch; views reload programmes when it changes.
    private(set) var guideRevision = 0
    /// Loaded from the state file at init; saved on every change.
    private(set) var state: IPTVState
    /// Favorites and hidden channels/groups (M6b L5). Loaded at init; saved on every change.
    private(set) var preferences: ChannelPreferences
    /// What Live TV lists show (M6b L11); recomputed when channels or preferences change.
    private(set) var lineup = ChannelLineup(channels: [])
    /// M7f L13: the Teams group's channels (`TeamMatcher`), recomputed by `updateTeams()`.
    @ObservationIgnored private(set) var teamChannelIDs: [Channel.ID] = []
    /// M7f L13: the update started by picking a team; tests await it.
    @ObservationIgnored private(set) var teamUpdateTask: Task<Void, Never>?
    static let teamsRefreshInterval: TimeInterval = 5 * 60
    /// The guides in use, in priority order (M6b L1): the pasted ones, else the playlist's.
    private(set) var guideSources: [GuideSource] = []
    /// By GuideSource.id.
    private(set) var guideSourceInfo: [String: GuideSourceInfo] = [:]
    @ObservationIgnored private(set) var epgMatches: [Channel.ID: EPGRef] = [:]
    @ObservationIgnored private var playlistGuideURLs: [URL] = []
    @ObservationIgnored private var lastPlaylistFetch: Date?
    /// Guide imports run one at a time; requests made meanwhile join the running loop (M6b L4).
    @ObservationIgnored private var queuedSourceIDs: Set<String> = []
    @ObservationIgnored private var isImportingGuide = false
    /// AppDelegate → settings.refreshStatus().
    @ObservationIgnored var onStatusChange: (() -> Void)?
    /// M7f L5: the lineup changed (a re-fetch, or favorites and hiding); AppDelegate → `AppRouter.playlistDidChange()`.
    @ObservationIgnored var onLineupChange: (() -> Void)?

    private var playlistURL: URL?
    private var customGuideURLs: [URL] = []
    /// M7f L4: `settings.json` `usePlaylistGuide`, set by AppDelegate at launch (live changes:
    /// `applyUsePlaylistGuide`).
    var usePlaylistGuide = false {
        didSet { updateGuideSources() }
    }

    @ObservationIgnored private let sources: IPTVSourceStore
    @ObservationIgnored private let store: EPGStore?
    @ObservationIgnored private let network: IPTVNetwork
    @ObservationIgnored private let stateFile: JSONConfigFile<IPTVState>
    @ObservationIgnored private let overridesFile: JSONConfigFile<[String: String]>
    @ObservationIgnored private let preferencesFile: JSONConfigFile<ChannelPreferences>
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "IPTV")

    init(sources: IPTVSourceStore, store: EPGStore?, network: IPTVNetwork,
         stateFile: JSONConfigFile<IPTVState>, overridesFile: JSONConfigFile<[String: String]>,
         preferencesFile: JSONConfigFile<ChannelPreferences>, now: @escaping () -> Date = Date.init) {
        self.sources = sources
        self.store = store
        self.network = network
        self.stateFile = stateFile
        self.overridesFile = overridesFile
        self.preferencesFile = preferencesFile
        self.now = now
        state = stateFile.load()
        preferences = preferencesFile.load()
        playlistURL = sources.playlistURL()
        customGuideURLs = sources.guideURLs()
        updateGuideSources()
        if let store {
            Task { [weak self] in
                let counts = (try? await store.programmeCounts()) ?? [:]
                guard let self else { return }
                for (id, count) in counts {
                    guideSourceInfo[id, default: GuideSourceInfo()].programmeCount = count
                }
                updateProgrammeCount()
            }
        } else {
            guideStatus = .failed("Guide storage unavailable")
        }
    }

    var hasPlaylist: Bool { playlistURL != nil }

    /// Host only (L2).
    var playlistHost: String? { playlistURL?.host() }

    /// Pasted guides (the playlist's don't count).
    var customGuideCount: Int { customGuideURLs.count }

    /// M7f L4: every pasted guide, in priority order, whether in use or not.
    var customGuideSources: [GuideSource] { customGuideURLs.map { GuideSource(url: $0, isFromPlaylist: false) } }

    /// M7f L4: the playlist's header names a guide (`url-tvg` / `x-tvg-url`).
    var playlistNamesGuide: Bool { !playlistGuideURLs.isEmpty }

    /// Playlist channels with guide data.
    var matchedChannelCount: Int { epgMatches.count }

    /// Also moves it to the front of `recentChannelIDs` (M7 L13).
    func rememberChannel(_ id: Channel.ID) {
        let recents = Array(([id] + state.recentChannelIDs.filter { $0 != id }).prefix(IPTVState.maxRecentChannels))
        guard state.lastChannelID != id || state.recentChannelIDs != recents else { return }
        updateState {
            $0.lastChannelID = id
            $0.recentChannelIDs = recents
        }
    }

    func rememberGroup(_ group: String) {
        guard state.lastGroup != group else { return }
        updateState { $0.lastGroup = group }
    }

    func rememberMultiview(_ snapshot: MultiviewSnapshot?) {
        guard state.multiview != snapshot else { return }
        updateState { $0.multiview = snapshot }
    }

    // MARK: - Refresh

    func refreshPlaylist() async {
        guard playlistStatus != .loading, let url = playlistURL else { return }
        setPlaylistStatus(.loading)
        do {
            let text = try await network.fetchText(url)
            let playlist = try M3UParser.parse(text)
            guard url == playlistURL else { return }    // replaced or removed meanwhile
            channels = ChannelList.make(from: playlist)
            playlistGuideURLs = playlist.guideURLs
            updateGuideSources()
            updateLineup()
            lastPlaylistFetch = now()
            logger.notice("Loaded \(self.channels.count) channels from \(url.host() ?? "?", privacy: .public)")
            await rematch()
            setPlaylistStatus(.loaded(now()))
        } catch {
            logger.error("Playlist from \(url.host() ?? "?", privacy: .public) failed: \(Self.redact(error.localizedDescription), privacy: .public)")
            setPlaylistStatus(url == playlistURL ? .failed(Self.message(for: error)) : .idle)
        }
    }

    /// When channels are empty or the last fetch is more than 10 minutes old (L4).
    func refreshPlaylistIfStale() async {
        if channels.isEmpty || lastPlaylistFetch.map({ now().timeIntervalSince($0) > Self.playlistStaleness }) ?? true {
            await refreshPlaylist()
        }
    }

    /// M7f L5 (D40): the timer's and wake's check. The playlist goes first, so a guide import never runs with no
    /// channels.
    func refreshIfStale() async {
        await refreshPlaylistIfStale()
        await refreshGuideIfStale()
    }

    /// Every guide (Refresh Now). Idle when there is no guide.
    func refreshGuide() async {
        guard store != nil, !guideSources.isEmpty else {
            await refreshGuide(sourceIDs: [])
            return
        }
        await refreshGuide(sourceIDs: Set(guideSources.map(\.id)))
    }

    /// Imports these guides one at a time (M6b L4). While a run is going, the ids join its queue and this returns.
    /// Skipped while there are no channels to match (the queue is kept), so an import never records an empty
    /// guide as fresh. A run ends by pruning guides no longer in use and one rematch.
    func refreshGuide(sourceIDs ids: Set<String>) async {
        guard let store else {
            setGuideStatus(.failed("Guide storage unavailable"))
            return
        }
        queuedSourceIDs.formUnion(ids)
        guard !isImportingGuide else { return }
        if guideSources.isEmpty {
            queuedSourceIDs = []
            await pruneUnusedGuides()
            await rematch()
            setGuideStatus(.idle)
            return
        }
        guard !channels.isEmpty, !queuedSourceIDs.isEmpty else { return }
        isImportingGuide = true
        setGuideStatus(.loading)
        var succeeded = 0
        var firstFailure: String?
        while let source = guideSources.first(where: { queuedSourceIDs.contains($0.id) }) {
            queuedSourceIDs.remove(source.id)
            guideSourceInfo[source.id, default: GuideSourceInfo()].status = .loading
            onStatusChange?()
            do {
                let outcome = try await GuideImporter.importGuide(
                    from: source.url, sourceID: source.id, channels: channels, overrides: overridesFile.load(),
                    store: store, network: network, now: now())
                guideSourceInfo[source.id, default: GuideSourceInfo()].programmeCount = outcome.programmeCount
                guideSourceInfo[source.id, default: GuideSourceInfo()].status = .loaded(now())
                updateState { $0.guideImports[source.id] = now() }
                succeeded += 1
            } catch {
                logger.error("Guide from \(source.url.host() ?? "?", privacy: .public) failed: \(Self.redact(error.localizedDescription), privacy: .public)")
                let message = Self.message(for: error)
                guideSourceInfo[source.id, default: GuideSourceInfo()].status = .failed(message)
                firstFailure = firstFailure ?? message
            }
        }
        queuedSourceIDs = []    // ids of guides removed meanwhile
        await pruneUnusedGuides()
        await rematch()
        isImportingGuide = false
        if let firstFailure, succeeded == 0 {
            setGuideStatus(.failed(firstFailure))
        } else {
            setGuideStatus(.loaded(now()))
        }
    }

    /// M6b L4: the guides whose last import is missing or more than 12 hours old.
    func refreshGuideIfStale() async {
        let stale = guideSources.filter { source in
            state.guideImports[source.id].map { now().timeIntervalSince($0) > Self.guideStaleness } ?? true
        }
        guard !stale.isEmpty else { return }
        await refreshGuide(sourceIDs: Set(stale.map(\.id)))
    }

    /// Playlist, then every guide (forced).
    func refreshAll() async {
        await refreshPlaylist()
        await refreshGuide()
    }

    func setPlaylistURL(_ url: URL) async {
        do {
            try sources.setPlaylistURL(url)
        } catch {
            logger.error("Failed to save the playlist URL: \(error.localizedDescription, privacy: .public)")
            setPlaylistStatus(.failed("Couldn't save the address"))
            return
        }
        logger.info("Playlist source set to \(url.host() ?? "?", privacy: .public)")
        playlistURL = url
        channels = []
        epgMatches = [:]
        playlistGuideURLs = []
        updateGuideSources()
        updateLineup()
        lastPlaylistFetch = nil
        playlistStatus = .idle
        await refreshAll()
    }

    // MARK: - Guides (M6b L1)

    /// Why a pasted guide can't be added, or nil.
    func guideAddProblem(_ url: URL) -> AddGuideProblem? {
        let id = Self.hash(url)
        if customGuideURLs.contains(where: { Self.hash($0) == id }) { return .duplicate }
        if customGuideURLs.count >= Self.maxGuideSources { return .full }
        return nil
    }

    /// Appends a pasted guide and imports it. The first one replaces the playlist's guides.
    func addGuideURL(_ url: URL) async {
        guard guideAddProblem(url) == nil else { return }
        guard saveCustomGuideURLs(customGuideURLs + [url]) else { return }
        logger.info("Guide added from \(url.host() ?? "?", privacy: .public)")
        await refreshGuide(sourceIDs: [Self.hash(url)])
    }

    /// Removes a pasted guide and its rows, and rematches (no download). Removing the last one brings back the
    /// playlist's guides, imported if stale.
    func removeGuideSource(_ id: String) async {
        guard let url = customGuideURLs.first(where: { Self.hash($0) == id }) else { return }
        guard saveCustomGuideURLs(customGuideURLs.filter { Self.hash($0) != id }) else { return }
        logger.info("Guide from \(url.host() ?? "?", privacy: .public) removed")
        updateState { $0.guideImports[id] = nil }
        await pruneUnusedGuides()
        await rematch()
        onStatusChange?()
        if customGuideURLs.isEmpty, !playlistGuideURLs.isEmpty {
            await refreshGuideIfStale()
        }
    }

    /// M7f L4: switches between the playlist's guide and the pasted ones. The guides no longer in use are pruned
    /// (their URLs stay in the Keychain); the newly used ones import if stale.
    func applyUsePlaylistGuide(_ use: Bool) async {
        guard use != usePlaylistGuide else { return }
        let before = guideSources
        usePlaylistGuide = use
        logger.info("Guide source: \(use ? "the playlist's guide" : "the pasted guides", privacy: .public)")
        guard guideSources != before else { return }
        await pruneUnusedGuides()
        await rematch()
        onStatusChange?()
        await refreshGuideIfStale()
    }

    /// Moves a pasted guide up (−1) or down (+1) in priority, and rematches (no download).
    func moveGuideSource(_ id: String, by step: Int) async {
        guard let index = customGuideURLs.firstIndex(where: { Self.hash($0) == id }) else { return }
        let target = min(max(index + step, 0), customGuideURLs.count - 1)
        guard target != index else { return }
        var urls = customGuideURLs
        urls.insert(urls.remove(at: index), at: target)
        guard saveCustomGuideURLs(urls) else { return }
        await rematch()
        onStatusChange?()
    }

    /// Keychain items, the stored guide, state and memory.
    func removeSource() async {
        do {
            try sources.removeAll()
        } catch {
            logger.error("Failed to remove the Live TV addresses: \(error.localizedDescription, privacy: .public)")
        }
        do {
            try await store?.removeAll()
        } catch {
            logger.error("Failed to clear the guide: \(error.localizedDescription, privacy: .public)")
        }
        playlistURL = nil
        customGuideURLs = []
        channels = []
        epgMatches = [:]
        playlistGuideURLs = []
        guideSources = []
        guideSourceInfo = [:]
        queuedSourceIDs = []
        teamChannelIDs = []
        updateLineup()    // preferences are kept (M6b L5)
        lastPlaylistFetch = nil
        guideProgrammeCount = 0
        updateState { $0 = IPTVState() }
        playlistStatus = .idle
        guideStatus = store == nil ? .failed("Guide storage unavailable") : .idle
        guideRevision += 1
        logger.info("Live TV source removed")
        onStatusChange?()
    }

    // MARK: - Channels (M6b L5, L11)

    func isFavorite(_ id: Channel.ID) -> Bool {
        preferences.favorites.contains(id)
    }

    /// Adding appends (favorites are in the order added); removing deletes.
    func setFavorite(_ id: Channel.ID, _ isFavorite: Bool) {
        guard isFavorite != self.isFavorite(id) else { return }
        updatePreferences { preferences in
            if isFavorite {
                preferences.favorites.append(id)
            } else {
                preferences.favorites.removeAll { $0 == id }
            }
        }
    }

    /// Swaps with the neighbor among the visible favorites; past either end does nothing.
    func moveFavorite(_ id: Channel.ID, by step: Int) {
        let visible = lineup.favorites.map(\.id)
        guard let index = visible.firstIndex(of: id), visible.indices.contains(index + step),
              let from = preferences.favorites.firstIndex(of: id),
              let to = preferences.favorites.firstIndex(of: visible[index + step])
        else { return }
        updatePreferences { $0.favorites.swapAt(from, to) }
    }

    func setChannelHidden(_ id: Channel.ID, _ hidden: Bool) {
        guard hidden != preferences.hiddenChannels.contains(id) else { return }
        updatePreferences { preferences in
            if hidden {
                preferences.hiddenChannels.append(id)
            } else {
                preferences.hiddenChannels.removeAll { $0 == id }
            }
        }
    }

    func setGroupHidden(_ group: String, _ hidden: Bool) {
        guard hidden != preferences.hiddenGroups.contains(group) else { return }
        updatePreferences { preferences in
            if hidden {
                preferences.hiddenGroups.append(group)
            } else {
                preferences.hiddenGroups.removeAll { $0 == group }
            }
        }
    }

    // MARK: - Matching (M6b L6, L9)

    /// The guide's short label ("guide-source_US2"), for a guide in use.
    func guideLabel(for ref: EPGRef) -> String? {
        guideSources.first { $0.id == ref.sourceID }?.shortLabel
    }

    /// What Match Guide offers for `channel`: its current choice and match, then ranked suggestions from every guide.
    func guideMatchOptions(for channel: Channel) async -> GuideMatchOptions {
        let bySource: [String: [EPGChannel]]
        do {
            bySource = try await store?.channelsBySource() ?? [:]
        } catch {
            logger.error("Reading guide channels failed: \(error.localizedDescription, privacy: .public)")
            bySource = [:]
        }
        let sources = guideSources.map { EPGSourceChannels(sourceID: $0.id, channels: bySource[$0.id] ?? []) }
        let suggestions = await EPGSuggester.suggest(for: channel, in: sources)

        let current = epgMatches[channel.id]
        let choice: GuideMatchChoice
        switch Self.override(for: channel, in: overridesFile.load()) {
        case "": choice = .none
        case let target? where current != nil && current?.epgID == target.lowercased(): choice = .epg(current!)
        default: choice = .automatic
        }

        let labels = Dictionary(guideSources.map { ($0.id, $0.shortLabel) }, uniquingKeysWith: { first, _ in first })
        var candidates: [GuideCandidate] = []
        if let current {
            let epg = bySource[current.sourceID]?.first { $0.id.lowercased() == current.epgID }
            candidates.append(GuideCandidate(ref: current, name: epg?.names.first ?? current.epgID,
                                             sourceLabel: labels[current.sourceID] ?? ""))
        }
        for suggestion in suggestions where suggestion.ref != current {
            candidates.append(GuideCandidate(ref: suggestion.ref, name: suggestion.name,
                                             sourceLabel: labels[suggestion.ref.sourceID] ?? ""))
        }
        return GuideMatchOptions(choice: choice, current: current, candidates: candidates)
    }

    /// Writes the choice to epg-overrides.json under the channel's name (L6), then re-imports the chosen guide if
    /// that channel's programmes weren't kept, else only rematches.
    func setGuideMatch(_ choice: GuideMatchChoice, for channel: Channel) async {
        var overrides = overridesFile.load()
        let keys = Set([channel.name, channel.tvgID ?? ""].filter { !$0.isEmpty }.map { $0.lowercased() })
        overrides = overrides.filter { !keys.contains($0.key.lowercased()) }
        switch choice {
        case .automatic: break
        case .none: overrides[channel.name] = ""
        case .epg(let ref): overrides[channel.name] = ref.epgID
        }
        do {
            try overridesFile.save(overrides)
        } catch {
            logger.error("Failed to save \(IPTVState.overridesFileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        if case .epg(let ref) = choice, await !hasProgrammes(ref) {
            await refreshGuide(sourceIDs: [ref.sourceID])
            return
        }
        await rematch()
        onStatusChange?()
        // Automatic after No Guide: the automatic match's programmes weren't kept at import.
        if choice == .automatic, let ref = epgMatches[channel.id], await !hasProgrammes(ref) {
            await refreshGuide(sourceIDs: [ref.sourceID])
        }
    }

    private func hasProgrammes(_ ref: EPGRef) async -> Bool {
        guard let store else { return true }
        return ((try? await store.programmeCount(for: ref)) ?? 0) > 0
    }

    /// The override value for `channel` (by name, then tvg-id, ignoring case), as the matcher reads it.
    private static func override(for channel: Channel, in overrides: [String: String]) -> String? {
        var lower: [String: String] = [:]
        for (key, value) in overrides { lower[key.lowercased()] = value }
        return lower[channel.name.lowercased()] ?? channel.tvgID.flatMap { lower[$0.lowercased()] }
    }

    // MARK: - Queries

    /// Keyed by Channel.ID; channels without an EPG match are absent.
    func programmes(for channels: [Channel], in interval: DateInterval) async -> [Channel.ID: [Programme]] {
        guard let store else { return [:] }
        let pairs = channels.compactMap { channel in epgMatches[channel.id].map { (channel.id, $0) } }
        guard !pairs.isEmpty else { return [:] }
        do {
            let byRef = try await store.programmes(refs: Set(pairs.map(\.1)), overlapping: interval)
            var result: [Channel.ID: [Programme]] = [:]
            for (channelID, ref) in pairs {
                if let programmes = byRef[ref] { result[channelID] = programmes }
            }
            return result
        } catch is CancellationError {
            return [:]
        } catch {
            logger.error("Guide query failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    /// M7f L12: programmes of these channels whose title has every word, overlapping `interval`, sorted by start;
    /// one result per channel when a guide channel serves several. At most `limit`.
    func searchProgrammes(words: [String], channels: [Channel], in interval: DateInterval,
                          limit: Int) async -> [(channel: Channel, programme: Programme)] {
        guard let store else { return [] }
        var channelsByRef: [EPGRef: [Channel]] = [:]
        for channel in channels {
            if let ref = epgMatches[channel.id] { channelsByRef[ref, default: []].append(channel) }
        }
        guard !channelsByRef.isEmpty else { return [] }
        do {
            let programmes = try await store.searchProgrammes(words: words, refs: Set(channelsByRef.keys),
                                                              interval: interval, limit: limit)
            let results = programmes.flatMap { programme in
                (channelsByRef[EPGRef(sourceID: programme.sourceID, epgID: programme.channelID)] ?? [])
                    .map { (channel: $0, programme: programme) }
            }
            return Array(results.prefix(limit))
        } catch is CancellationError {
            return []
        } catch {
            logger.error("Guide search failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func nowNext(for channel: Channel, at date: Date) async -> (now: Programme?, next: Programme?) {
        let programmes = await programmes(for: [channel], in: DateInterval(start: date, duration: 24 * 3600))[channel.id] ?? []
        let current = programmes.first { $0.start <= date && date < $0.stop }
        let next = programmes.first { $0.start >= (current?.stop ?? date) }
        return (current, next)
    }

    // MARK: - Teams (M7f L13)

    func isTeamPicked(_ id: Team.ID) -> Bool {
        preferences.teams.contains(id)
    }

    /// Picks or unpicks a team (Settings, the guide's channel menu); the Teams group follows.
    func setTeamPicked(_ id: Team.ID, _ picked: Bool) {
        guard picked != isTeamPicked(id), TeamCatalog.byID[id] != nil else { return }
        updatePreferences { preferences in
            if picked {
                preferences.teams.append(id)
            } else {
                preferences.teams.removeAll { $0 == id }
            }
        }
        teamUpdateTask = Task { await updateTeams() }
    }

    /// The Teams group: game entries by name, network channels by the programme on now. After each playlist
    /// refresh, guide import or rematch, a team picked, and every 5 minutes (AppDelegate). Sets the lineup on change.
    func updateTeams() async {
        let picked = Set(preferences.teams)
        var nowPlaying: [Channel.ID: Programme] = [:]
        if !picked.isEmpty {
            let date = now()
            let networks = channels.filter { !TeamMatcher.isGameGroup($0.group) && epgMatches[$0.id] != nil }
            let programmes = await programmes(for: networks, in: DateInterval(start: date, duration: 1))
            for (id, list) in programmes {
                nowPlaying[id] = list.first { $0.start <= date && date < $0.stop }
            }
        }
        let ids = TeamMatcher.channelIDs(channels: channels, nowPlaying: nowPlaying, picked: picked)
        guard ids != teamChannelIDs else { return }
        teamChannelIDs = ids
        updateLineup()
    }

    // MARK: - Private

    /// Matches every channel over every guide in use, in priority order (M6b L3).
    private func rematch() async {
        let bySource: [String: [EPGChannel]]
        do {
            bySource = try await store?.channelsBySource() ?? [:]
        } catch {
            logger.error("Reading guide channels failed: \(error.localizedDescription, privacy: .public)")
            bySource = [:]
        }
        let sources = guideSources.map { EPGSourceChannels(sourceID: $0.id, channels: bySource[$0.id] ?? []) }
        epgMatches = EPGMatcher.match(channels, sources: sources, overrides: overridesFile.load())
        var matched: [String: Int] = [:]
        for ref in epgMatches.values {
            matched[ref.sourceID, default: 0] += 1
        }
        for source in guideSources {
            guideSourceInfo[source.id, default: GuideSourceInfo()].matchedChannels = matched[source.id] ?? 0
        }
        guideRevision += 1
        await updateTeams()
    }

    /// Deletes the rows of guides no longer in use, and their bookkeeping.
    private func pruneUnusedGuides() async {
        let ids = Set(guideSources.map(\.id))
        do {
            try await store?.removeSources(keeping: ids)
        } catch {
            logger.error("Pruning old guides failed: \(error.localizedDescription, privacy: .public)")
        }
        guideSourceInfo = guideSourceInfo.filter { ids.contains($0.key) }
        if state.guideImports.keys.contains(where: { !ids.contains($0) }) {
            updateState { $0.guideImports = $0.guideImports.filter { ids.contains($0.key) } }
        }
        updateProgrammeCount()
    }

    /// Saves the pasted guides and recomputes the guides in use. Logs and returns false on a Keychain error.
    private func saveCustomGuideURLs(_ urls: [URL]) -> Bool {
        do {
            try sources.setGuideURLs(urls)
        } catch {
            logger.error("Failed to save the guide URLs: \(error.localizedDescription, privacy: .public)")
            setGuideStatus(.failed("Couldn't save the address"))
            return false
        }
        customGuideURLs = urls
        updateGuideSources()
        return true
    }

    /// M6b L1: the pasted guides when there are any, else the playlist's.
    /// M7f L4: with `usePlaylistGuide`, the playlist's when it names one.
    private func updateGuideSources() {
        let usesPlaylist = customGuideURLs.isEmpty || (usePlaylistGuide && !playlistGuideURLs.isEmpty)
        guideSources = usesPlaylist
            ? playlistGuideURLs.map { GuideSource(url: $0, isFromPlaylist: true) }
            : customGuideSources
    }

    private func updateProgrammeCount() {
        guideProgrammeCount = guideSourceInfo.values.reduce(0) { $0 + $1.programmeCount }
    }

    /// Saves iptv-channels.json, recomputes the lineup and tells Settings.
    private func updatePreferences(_ change: (inout ChannelPreferences) -> Void) {
        change(&preferences)
        do {
            try preferencesFile.save(preferences)
        } catch {
            logger.error("Failed to save \(ChannelPreferences.fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        updateLineup()
        onStatusChange?()
    }

    private func updateLineup() {
        let lineup = ChannelLineup(channels: channels, preferences: preferences, teamChannelIDs: teamChannelIDs)
        guard lineup != self.lineup else { return }
        self.lineup = lineup
        onLineupChange?()
    }

    private func setPlaylistStatus(_ status: Status) {
        playlistStatus = status
        onStatusChange?()
    }

    private func setGuideStatus(_ status: Status) {
        guideStatus = status
        onStatusChange?()
    }

    private func updateState(_ change: (inout IPTVState) -> Void) {
        change(&state)
        do {
            try stateFile.save(state)
        } catch {
            logger.error("Failed to save \(IPTVState.fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Error texts may quote the URL; never log it (L2).
    private static func redact(_ text: String) -> String {
        text.replacing(/https?:\/\/\S+/, with: "<url>")
    }

    nonisolated static func hash(_ url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func message(for error: Error) -> String {
        switch error {
        case IPTVNetworkError.http(let status): return "Server error (HTTP \(status))"
        case M3UParser.ParseError.notAPlaylist: return "The address didn't return a playlist"
        case let error as URLError: return error.localizedDescription
        case is Gunzip.GunzipError: return "The guide file couldn't be read"
        case let error as NSError where error.domain == XMLParser.errorDomain: return "The guide file couldn't be read"
        default: return error.localizedDescription
        }
    }
}
