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
                           channels: [Channel]? = nil) -> TopShelfModel {
        let all = channels ?? (1...12).map { channel($0) }
        let lineup = ChannelLineup(channels: all, preferences: ChannelPreferences(favorites: favorites, hiddenChannels: hidden))
        let source = LiveShelfSource(
            channels: { (lineup, recent) },
            nowNext: { channel in
                guard channel.id == "id:c1" else { return (nil, nil) }
                let programme = Programme(channelID: "c1", start: Self.now - 300, stop: Self.now + 1500, title: "The Game")
                return (programme, nil)
            }
        )
        return TopShelfModel(live: source, now: { Self.now })
    }

    @Test func favoritesComeFirst() async {
        let model = makeModel(favorites: ["id:c3", "id:c1"], recent: ["id:c5"])
        await model.reloadLive()
        #expect(model.liveCards.map(\.id) == ["live.id:c3", "live.id:c1"])
        #expect(model.content(for: liveTile) == .cards(title: "On Now", model.liveCards))
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
        guard case .cards(let title, let cards) = model.content(for: tile) else {
            Issue.record("No Plex cards")
            return
        }
        #expect(title == "Continue Watching")
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
