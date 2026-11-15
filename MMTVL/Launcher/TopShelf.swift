import Foundation

/// One card of the top shelf (M7 D28, L12).
nonisolated struct ShelfCard: Identifiable, Equatable, Sendable {
    enum Image: Equatable, Sendable {
        case channelLogo(URL?)
        /// Fetched by `ShelfImageLoader` with these headers (Plex token); the URL holds no secret.
        case remote(URL, headers: [String: String])
    }

    enum Action: Equatable, Sendable {
        case playChannel(Channel.ID)
        case openTile(id: String)
    }

    var id: String
    var title: String
    var subtitle: String
    var image: Image
    /// 0…1.
    var progress: Double?
    var action: Action
    /// M7c L14: the full-screen carousel art (Plex, 1920 × 1080); nil = scale `image` up.
    var backdrop: Image?
    /// M7c L14: a transparent title logo (Plex clear logo), drawn instead of the title.
    var logo: Image?
    /// M7c L14: "25 min left" in the carousel.
    var minutesLeft: Int?
}

/// What the shelf shows for the focused tile: its art as a banner, a row of cards, or (M7c L14, L21, D37, D38) a
/// full-screen carousel of pages. Plex's pages auto-advance; Live TV's (channels) don't.
nonisolated enum ShelfContent: Equatable, Sendable {
    case banner
    case cards(title: String, [ShelfCard])
    case carousel(title: String, [ShelfCard], autoAdvances: Bool)

    /// The items of `.cards` and `.carousel`; [] for `.banner`.
    var cards: [ShelfCard] {
        switch self {
        case .banner: []
        case .cards(_, let cards), .carousel(_, let cards, _): cards
        }
    }

    var isCarousel: Bool {
        if case .carousel = self { return true }
        return false
    }

    var autoAdvances: Bool {
        if case .carousel(_, _, let autoAdvances) = self { return autoAdvances }
        return false
    }
}

/// Where the shelf's content comes from (`TopShelfModel` in the app, a fake in tests).
protocol TopShelfProviding: AnyObject {
    func content(for item: LaunchItem) -> ShelfContent
    /// The home screen appeared or a tile got focus; implementations refresh what is stale.
    func refresh(focusing item: LaunchItem?)
}

/// Always a banner.
final class NoTopShelf: TopShelfProviding {
    func content(for item: LaunchItem) -> ShelfContent { .banner }
    func refresh(focusing item: LaunchItem?) {}
}

/// What the Live TV shelf reads (M7 L13). The app builds it from `IPTVLibrary`; tests pass fakes.
struct LiveShelfSource {
    /// The lineup (empty without a playlist or before channels load) and the recent channel ids.
    var channels: () -> (lineup: ChannelLineup, recent: [Channel.ID])
    var nowNext: (Channel) async -> (now: Programme?, next: Programme?)
    /// M7c L21: the channel the home preview plays by default (Multiview's highlighted window, else the last
    /// channel); Live TV's first page. Wired to `LiveTVModel.defaultPreviewChannelID` by the app.
    var defaultChannel: () -> Channel.ID? = { nil }
    /// M7c L24: loads the pages' channel logos ahead (`ChannelLogoCache.prefetch`).
    var prefetchLogos: ([URL]) -> Void = { _ in }
    /// M7c L29: resolves the first pages' stream redirects ahead (`StreamResolver.prefetch`).
    var prefetchStreams: ([URL]) -> Void = { _ in }
}

extension LiveShelfSource {
    static func library(_ library: IPTVLibrary) -> LiveShelfSource {
        LiveShelfSource(
            channels: { [weak library] in
                guard let library, library.hasLiveSource else { return (ChannelLineup(channels: []), []) }
                return (library.lineup, library.state.recentChannelIDs)
            },
            nowNext: { [weak library] channel in
                await library?.nowNext(for: channel, at: Date()) ?? (nil, nil)
            },
            prefetchLogos: { ChannelLogoCache.shared.prefetch($0) },
            prefetchStreams: { StreamResolver.shared.prefetch($0) }
        )
    }
}

/// The app's shelf content (M7 D28): Live TV "On Now" (L13), Plex "Continue Watching" (L14);
/// every other tile gets a banner. PIN-protected tiles are turned into banners by the router.
@Observable
final class TopShelfModel: TopShelfProviding {
    static let maxLiveCards = 10
    /// M7c L29: the first Live pages have their stream redirects resolved ahead.
    static let streamPrefetchPages = 3
    /// Live cards older than this reload on the next refresh.
    static let liveMaxAge: TimeInterval = 60

    private(set) var liveCards: [ShelfCard] = []
    /// The last reload; tests await it.
    @ObservationIgnored private(set) var pendingTask: Task<Void, Never>?
    /// Content changed (the router clamps its card focus).
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let live: LiveShelfSource
    @ObservationIgnored private let plex: PlexAccount?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var liveLoadedAt: Date?
    /// The default channel the live pages were built with; a change reloads them.
    @ObservationIgnored private var liveDefaultID: Channel.ID?

    /// L14: the Plex HTPC tile.
    static let plexBundleID = "tv.plex.htpc"
    /// L14: Continue Watching reloads when older than this.
    static let plexMaxAge: Duration = .seconds(120)

    init(live: LiveShelfSource, plex: PlexAccount? = nil, now: @escaping () -> Date = Date.init) {
        self.live = live
        self.plex = plex
        self.now = now
    }

    func content(for item: LaunchItem) -> ShelfContent {
        switch item.kind {
        case .internalDestination(.iptv):
            // M7c L21 (D38): channel pages; the muted preview follows the page, so no auto-advance.
            return liveCards.isEmpty ? .banner : .carousel(title: "On Now", liveCards, autoAdvances: false)
        case .application(Self.plexBundleID):
            // The account doesn't know tiles: its cards open the tile that owns the shelf.
            let cards = (plex?.continueWatching ?? []).map { card in
                var card = card
                card.action = .openTile(id: item.id)
                return card
            }
            // M7c L14 (D37): a full-screen carousel.
            return cards.isEmpty ? .banner : .carousel(title: "Continue Watching", cards, autoAdvances: true)
        default:
            return .banner
        }
    }

    func refresh(focusing item: LaunchItem?) {
        plex?.startRefresh(maxAge: Self.plexMaxAge)
        if let liveLoadedAt, now().timeIntervalSince(liveLoadedAt) < Self.liveMaxAge,
           live.defaultChannel() == liveDefaultID { return }
        pendingTask = Task { await reloadLive() }
    }

    /// L13: favorites, else recent channels (visible only), up to 10, with what's on now.
    /// M7c L21: the default channel first (if visible), then those without it.
    func reloadLive() async {
        let (lineup, recent) = live.channels()
        let defaultID = live.defaultChannel()
        let visible = Dictionary(lineup.visibleChannels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var channels = lineup.favorites
        if channels.isEmpty {
            channels = recent.compactMap { visible[$0] }
        }
        if let defaultID, let first = visible[defaultID] {
            channels = [first] + channels.filter { $0.id != defaultID }
        }
        channels = Array(channels.prefix(Self.maxLiveCards))
        liveDefaultID = defaultID
        live.prefetchLogos(channels.compactMap(\.logoURL))
        // M7j L7: never an antenna channel's stream (a resolve is a GET, which takes a tuner).
        let prefetched = channels.prefix(Self.streamPrefetchPages).filter { !$0.isDirectStream }
        if !prefetched.isEmpty { live.prefetchStreams(prefetched.map(\.streamURL)) }
        var cards: [ShelfCard] = []
        let date = now()
        for channel in channels {
            let (current, _) = await live.nowNext(channel)
            cards.append(Self.liveCard(channel, programme: current, at: date))
        }
        // Without channels (still loading) the next refresh tries again.
        liveLoadedAt = lineup.visibleChannels.isEmpty ? nil : date
        guard cards != liveCards else { return }
        liveCards = cards
        onChange?()
    }

    static func liveCard(_ channel: Channel, programme: Programme?, at date: Date) -> ShelfCard {
        var subtitle = "No guide data"
        var progress: Double?
        if let programme {
            subtitle = "\(channel.name) · \(timeLeft(until: programme.stop, from: date))"
            let length = programme.stop.timeIntervalSince(programme.start)
            if length > 0 { progress = min(max(date.timeIntervalSince(programme.start) / length, 0), 1) }
        }
        return ShelfCard(id: "live.\(channel.id)", title: programme?.title ?? channel.name, subtitle: subtitle,
                         image: .channelLogo(channel.logoURL), progress: progress, action: .playChannel(channel.id))
    }

    /// "25 min left", "1 h 5 min left".
    static func timeLeft(until stop: Date, from date: Date) -> String {
        let minutes = max(Int((stop.timeIntervalSince(date) / 60).rounded(.up)), 0)
        guard minutes >= 60 else { return "\(minutes) min left" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) h left" : "\(minutes / 60) h \(rest) min left"
    }
}
