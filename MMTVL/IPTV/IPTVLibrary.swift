import CryptoKit
import Foundation
import Observation
import os

/// Live TV data: channels (in memory, D23), guide (SQLite, D8), refresh policy (L4, L5), guide source (L3).
@Observable
final class IPTVLibrary {
    enum Status: Equatable { case idle, loading, loaded(Date), failed(String) }
    enum GuideSource: Equatable { case none, playlist(URL), custom(URL) }

    static let playlistStaleness: TimeInterval = 10 * 60
    static let guideStaleness: TimeInterval = 12 * 3600

    private(set) var channels: [Channel] = []
    private(set) var playlistStatus: Status = .idle
    private(set) var guideStatus: Status = .idle
    private(set) var guideProgrammeCount = 0
    /// Bumped after every guide import or rematch; views reload programmes when it changes.
    private(set) var guideRevision = 0
    /// Loaded from the state file at init; saved on every change.
    private(set) var state: IPTVState
    @ObservationIgnored private(set) var epgIDs: [Channel.ID: String] = [:]
    @ObservationIgnored private var playlistGuideURLs: [URL] = []
    @ObservationIgnored private var lastPlaylistFetch: Date?
    /// AppDelegate → settings.refreshStatus().
    @ObservationIgnored var onStatusChange: (() -> Void)?

    private var playlistURL: URL?
    private var customGuideURL: URL?

    @ObservationIgnored private let sources: IPTVSourceStore
    @ObservationIgnored private let store: EPGStore?
    @ObservationIgnored private let network: IPTVNetwork
    @ObservationIgnored private let stateFile: JSONConfigFile<IPTVState>
    @ObservationIgnored private let overridesFile: JSONConfigFile<[String: String]>
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "IPTV")

    init(sources: IPTVSourceStore, store: EPGStore?, network: IPTVNetwork,
         stateFile: JSONConfigFile<IPTVState>, overridesFile: JSONConfigFile<[String: String]>,
         now: @escaping () -> Date = Date.init) {
        self.sources = sources
        self.store = store
        self.network = network
        self.stateFile = stateFile
        self.overridesFile = overridesFile
        self.now = now
        state = stateFile.load()
        playlistURL = sources.playlistURL()
        customGuideURL = sources.guideURL()
        if let store {
            Task { [weak self] in
                let count = (try? await store.programmeCount()) ?? 0
                self?.guideProgrammeCount = count
            }
        } else {
            guideStatus = .failed("Guide storage unavailable")
        }
    }

    var hasPlaylist: Bool { playlistURL != nil }

    /// Host only (L2).
    var playlistHost: String? { playlistURL?.host() }

    /// L3: a pasted guide URL wins, else the playlist's first url-tvg, else none.
    var guideSource: GuideSource {
        if let customGuideURL { return .custom(customGuideURL) }
        if let first = playlistGuideURLs.first { return .playlist(first) }
        return .none
    }

    private var guideURL: URL? {
        switch guideSource {
        case .none: nil
        case .playlist(let url), .custom(let url): url
        }
    }

    func rememberChannel(_ id: Channel.ID) {
        guard state.lastChannelID != id else { return }
        updateState { $0.lastChannelID = id }
    }

    func rememberGroup(_ group: String) {
        guard state.lastGroup != group else { return }
        updateState { $0.lastGroup = group }
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
            lastPlaylistFetch = now()
            logger.info("Loaded \(self.channels.count) channels from \(url.host() ?? "?", privacy: .public)")
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

    /// No-op while loading. Idle when there is no guide source. Skipped while there are no channels to match,
    /// so an import never records an empty guide as fresh.
    func refreshGuide() async {
        guard guideStatus != .loading else { return }
        guard let store else {
            setGuideStatus(.failed("Guide storage unavailable"))
            return
        }
        guard let url = guideURL else {
            setGuideStatus(.idle)
            return
        }
        guard !channels.isEmpty else { return }
        setGuideStatus(.loading)
        do {
            let outcome = try await GuideImporter.importGuide(
                from: url, channels: channels, overrides: overridesFile.load(),
                store: store, network: network, now: now())
            guideProgrammeCount = outcome.programmeCount
            updateState {
                $0.lastGuideImport = now()
                $0.lastGuideSourceHash = Self.hash(url)
            }
            await rematch()
            setGuideStatus(.loaded(now()))
        } catch {
            logger.error("Guide from \(url.host() ?? "?", privacy: .public) failed: \(Self.redact(error.localizedDescription), privacy: .public)")
            setGuideStatus(.failed(Self.message(for: error)))
        }
    }

    /// L5: when the last import is more than 12 hours old or the guide URL changed.
    func refreshGuideIfStale() async {
        guard let url = guideURL else { return }
        let stale = state.lastGuideImport.map { now().timeIntervalSince($0) > Self.guideStaleness } ?? true
        if stale || state.lastGuideSourceHash != Self.hash(url) {
            await refreshGuide()
        }
    }

    /// Playlist, then guide (forced).
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
        epgIDs = [:]
        playlistGuideURLs = []
        lastPlaylistFetch = nil
        playlistStatus = .idle
        await refreshAll()
    }

    /// nil = use the playlist's guide.
    func setGuideURL(_ url: URL?) async {
        do {
            try sources.setGuideURL(url)
        } catch {
            logger.error("Failed to save the guide URL: \(error.localizedDescription, privacy: .public)")
            setGuideStatus(.failed("Couldn't save the address"))
            return
        }
        logger.info("Guide source set to \(url?.host() ?? "the playlist's", privacy: .public)")
        customGuideURL = url
        await refreshGuide()
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
        customGuideURL = nil
        channels = []
        epgIDs = [:]
        playlistGuideURLs = []
        lastPlaylistFetch = nil
        guideProgrammeCount = 0
        updateState { $0 = IPTVState() }
        playlistStatus = .idle
        guideStatus = store == nil ? .failed("Guide storage unavailable") : .idle
        guideRevision += 1
        logger.info("Live TV source removed")
        onStatusChange?()
    }

    // MARK: - Queries

    /// Keyed by Channel.ID; channels without an EPG match are absent.
    func programmes(for channels: [Channel], in interval: DateInterval) async -> [Channel.ID: [Programme]] {
        guard let store else { return [:] }
        let pairs = channels.compactMap { channel in epgIDs[channel.id].map { (channel.id, $0) } }
        guard !pairs.isEmpty else { return [:] }
        do {
            let byEPG = try await store.programmes(channelIDs: Set(pairs.map(\.1)), overlapping: interval)
            var result: [Channel.ID: [Programme]] = [:]
            for (channelID, epgID) in pairs {
                if let programmes = byEPG[epgID] { result[channelID] = programmes }
            }
            return result
        } catch is CancellationError {
            return [:]
        } catch {
            logger.error("Guide query failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    func nowNext(for channel: Channel, at date: Date) async -> (now: Programme?, next: Programme?) {
        let programmes = await programmes(for: [channel], in: DateInterval(start: date, duration: 24 * 3600))[channel.id] ?? []
        let current = programmes.first { $0.start <= date && date < $0.stop }
        let next = programmes.first { $0.start >= (current?.stop ?? date) }
        return (current, next)
    }

    // MARK: - Private

    private func rematch() async {
        let epgChannels: [EPGChannel]
        do {
            epgChannels = try await store?.channels() ?? []
        } catch {
            logger.error("Reading guide channels failed: \(error.localizedDescription, privacy: .public)")
            epgChannels = []
        }
        epgIDs = EPGMatcher.match(channels, to: epgChannels, overrides: overridesFile.load())
        guideRevision += 1
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

    static func hash(_ url: URL) -> String {
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
