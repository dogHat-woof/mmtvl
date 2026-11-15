import Foundation
import Testing
@testable import MMTVL

/// The top shelf's content (M7 L13).
struct TopShelfModelTests {
    static let now = Date(timeIntervalSince1970: 1_791_200_000)

    private func channel(_ n: Int, group: String = "Live") -> Channel {
        Channel(id: "id:c\(n)", number: n, name: "Channel \(n)", group: group, tvgID: "c\(n)", tvgName: nil,
                logoURL: URL(string: "https://logo/\(n).png"), streamURL: URL(string: "https://cdn/\(n).m3u8")!)
    }

    private let liveTile = LaunchItem.defaults.first { $0.id == "iptv" }!

    /// 12 channels; c1 has a programme on now (started 5 min ago, 25 min left).
    private func makeModel(favorites: [Channel.ID] = [], hidden: [Channel.ID] = [], recent: [Channel.ID] = [],
                           teams: [Channel.ID] = [],
                           channels: [Channel]? = nil, defaultChannel: @escaping () -> Channel.ID? = { nil }) -> TopShelfModel {
        let all = channels ?? (1...12).map { channel($0) }
        let lineup = ChannelLineup(channels: all, preferences: ChannelPreferences(favorites: favorites, hiddenChannels: hidden),
                                   teamChannelIDs: teams)
        let source = LiveShelfSource(
            channels: { (lineup, recent) },
            nowNext: { channel in
                guard channel.id == "id:c1" else { return (nil, nil) }
                let programme = Programme(channelID: "c1", start: Self.now - 300, stop: Self.now + 1500, title: "The Game")
                return (programme, nil)
            },
            defaultChannel: defaultChannel
        )
        return TopShelfModel(live: source, now: { Self.now })
    }

    /// M7j L7: the first pages' streams are resolved ahead, but never an antenna channel's (a GET takes a tuner).
    @Test func liveCardsDontPrefetchAntennaStreams() async {
        let antenna = AntennaFixtures.liveChannels(firstNumber: 13)   // 2.1, 5.1, 11.1
        let playlist = (1...3).map { channel($0) }
        let favorites = [antenna[1].id, "id:c1", antenna[0].id, "id:c2"]
        var prefetched: [[URL]] = []
        let source = LiveShelfSource(
            channels: { (ChannelLineup(channels: playlist + antenna,
                                       preferences: ChannelPreferences(favorites: favorites)), []) },
            nowNext: { _ in (nil, nil) },
            prefetchStreams: { prefetched.append($0) }
        )
        let model = TopShelfModel(live: source, now: { Self.now })
        await model.reloadLive()
        #expect(model.liveCards.map(\.id) == favorites.map { "live.\($0)" })
        #expect(prefetched == [[URL(string: "https://cdn/1.m3u8")!]])

        // Only antenna channels on the first pages: nothing is prefetched.
        prefetched = []
        let onlyAntenna = TopShelfModel(live: LiveShelfSource(
            channels: { (ChannelLineup(channels: antenna,
                                       preferences: ChannelPreferences(favorites: antenna.map(\.id))), []) },
            nowNext: { _ in (nil, nil) },
            prefetchStreams: { prefetched.append($0) }
        ), now: { Self.now })
        await onlyAntenna.reloadLive()
        #expect(onlyAntenna.liveCards.count == 3)
        #expect(prefetched.isEmpty)
    }

    @Test func favoritesComeFirst() async {
        let model = makeModel(favorites: ["id:c3", "id:c1"], recent: ["id:c5"])
        await model.reloadLive()
        #expect(model.liveCards.map(\.id) == ["live.id:c3", "live.id:c1"])
        // M7c L21: channel pages that don't auto-advance.
        #expect(model.content(for: liveTile) == .carousel(title: "On Now", model.liveCards, autoAdvances: false))
    }

    /// M7c L21: the default channel is the first page, not repeated.
    @Test func theDefaultChannelComesFirst() async {
        let model = makeModel(favorites: ["id:c3", "id:c1"], defaultChannel: { "id:c1" })
        await model.reloadLive()
        #expect(model.liveCards.map(\.id) == ["live.id:c1", "live.id:c3"])

        let other = makeModel(recent: ["id:c5", "id:c2"], defaultChannel: { "id:c9" })
        await other.reloadLive()
        #expect(other.liveCards.map(\.id) == ["live.id:c9", "live.id:c5", "live.id:c2"])

        let hidden = makeModel(hidden: ["id:c9"], recent: ["id:c5"], defaultChannel: { "id:c9" })
        await hidden.reloadLive()
        #expect(hidden.liveCards.map(\.id) == ["live.id:c5"])
    }

    @Test func aNewDefaultChannelReloads() async {
        var defaultID: Channel.ID? = "id:c1"
        let model = makeModel(favorites: ["id:c3"], defaultChannel: { defaultID })
        model.refresh(focusing: nil)
        await model.pendingTask?.value
        let first = model.pendingTask
        model.refresh(focusing: liveTile)
        #expect(model.pendingTask == first)
        defaultID = "id:c3"
        model.refresh(focusing: liveTile)
        await model.pendingTask?.value
        #expect(model.liveCards.map(\.id) == ["live.id:c3"])
    }

    /// M7l 8b: live team games top the guide's Favorites group only; the On Now pages keep the saved favorites,
    /// and recents when there are none.
    @Test func teamGamesDontChangeTheLivePages() async {
        let model = makeModel(favorites: ["id:c3", "id:c1"], recent: ["id:c5"], teams: ["id:c7", "id:c1"])
        await model.reloadLive()
        #expect(model.liveCards.map(\.id) == ["live.id:c3", "live.id:c1"])
        let recents = makeModel(recent: ["id:c5"], teams: ["id:c7"])
        await recents.reloadLive()
        #expect(recents.liveCards.map(\.id) == ["live.id:c5"])
    }

    @Test func recentsWhenThereAreNoFavorites() async {
        let model = makeModel(hidden: ["id:c4"], recent: ["id:c4", "id:c2", "id:gone", "id:c1"])
        await model.reloadLive()
        #expect(model.liveCards.map(\.id) == ["live.id:c2", "live.id:c1"])
    }

    @Test func atMostTenCards() async {
        let model = makeModel(favorites: (1...12).map { "id:c\($0)" })
        await model.reloadLive()
        #expect(model.liveCards.count == 10)
    }

    @Test func cardText() async throws {
        let model = makeModel(favorites: ["id:c1", "id:c2"])
        await model.reloadLive()
        let onNow = try #require(model.liveCards.first)
        #expect(onNow.title == "The Game")
        #expect(onNow.subtitle == "Channel 1 · 25 min left")
        #expect(onNow.image == .channelLogo(URL(string: "https://logo/1.png")))
        #expect(onNow.action == .playChannel("id:c1"))
        #expect(abs((onNow.progress ?? 0) - 300.0 / 1800) < 0.0001)

        let noGuide = model.liveCards[1]
        #expect(noGuide.title == "Channel 2")
        #expect(noGuide.subtitle == "No guide data")
        #expect(noGuide.progress == nil)
    }

    @Test func timeLeft() {
        #expect(TopShelfModel.timeLeft(until: Self.now + 1500, from: Self.now) == "25 min left")
        #expect(TopShelfModel.timeLeft(until: Self.now + 1490, from: Self.now) == "25 min left")
        #expect(TopShelfModel.timeLeft(until: Self.now + 3900, from: Self.now) == "1 h 5 min left")
        #expect(TopShelfModel.timeLeft(until: Self.now + 7200, from: Self.now) == "2 h left")
    }

    @Test func bannerWithoutChannels() async {
        let model = makeModel(recent: ["id:c1"], channels: [])
        await model.reloadLive()
        #expect(model.content(for: liveTile) == .banner)
        let plex = LaunchItem.defaults[0]
        #expect(model.content(for: plex) == .banner)
    }

    @Test func refreshReloadsOnlyWhenStale() async {
        let model = makeModel(favorites: ["id:c1"])
        var changes = 0
        model.onChange = { changes += 1 }
        model.refresh(focusing: nil)
        await model.pendingTask?.value
        #expect(changes == 1)
        let first = model.pendingTask
        model.refresh(focusing: liveTile)
        #expect(model.pendingTask == first)
    }

    // MARK: Plex (L14)

    @Test func plexCardsOpenTheTileThatOwnsTheShelf() async throws {
        let server = FakePlexServer()
        server.on("GET plex.tv/api/v2/user", json: "{}")
        server.on("GET plex.tv/api/v2/resources", json: "[\(PlexAccountTests.resource("srv1", name: "Living Room", owned: true))]")
        server.on("GET 192-168-1-20.abc.plex.direct/identity", json: PlexAccountTests.identity)
        server.on("GET 192-168-1-20.abc.plex.direct/hubs/continueWatching", json: PlexAccountTests.continueWatching)
        let directory = FileManager.default.temporaryDirectory.appending(path: "TopShelfPlex-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let plex = PlexAccount(network: server.network,
                               configFile: JSONConfigFile(url: directory.appending(path: PlexConfig.fileName), defaultValue: PlexConfig()),
                               tokens: .inMemory(user: "user-token"), client: PlexAccountTests.client, sleep: { _ in })
        let model = TopShelfModel(live: LiveShelfSource(channels: { (ChannelLineup(channels: []), []) }, nowNext: { _ in (nil, nil) }),
                                  plex: plex, now: { Self.now })
        let tile = LaunchItem(id: "my-plex", title: "Plex", kind: .application(bundleID: "tv.plex.htpc"))
        #expect(model.content(for: tile) == .banner)

        model.refresh(focusing: tile)
        await plex.refreshTask?.value
        // M7c L14: Plex is a full-screen carousel with 1920 × 1080 backdrops.
        guard case .carousel(let title, let cards, let autoAdvances) = model.content(for: tile) else {
            Issue.record("No Plex carousel")
            return
        }
        #expect(model.content(for: tile).isCarousel)
        #expect(autoAdvances)
        #expect(title == "Continue Watching")
        guard case .remote(let backdrop, _) = cards[0].backdrop else {
            Issue.record("No backdrop")
            return
        }
        #expect(backdrop.absoluteString.contains("width=1920"))
        #expect(backdrop.absoluteString.contains("height=1080"))
        #expect(cards[0].minutesLeft == 1)
        #expect(cards[0].logo == nil)
        #expect(cards[1].backdrop == nil)
        #expect(cards.map(\.id) == ["plex.501", "plex.601"])
        #expect(cards.allSatisfy { $0.action == .openTile(id: "my-plex") })
        #expect(cards[0].title == "Friends")
        #expect(cards[0].subtitle == "S2 E7 · The One")

        // Another app's tile gets a banner.
        let other = LaunchItem(id: "prime", title: "Prime", kind: .application(bundleID: "com.amazon.aiv.AIVApp"))
        #expect(model.content(for: other) == .banner)

        plex.signOut()
        #expect(model.content(for: tile) == .banner)
    }
}
