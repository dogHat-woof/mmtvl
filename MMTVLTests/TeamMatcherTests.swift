import Foundation
import Testing
@testable import MMTVL

/// M7f L13: the team catalog, game and network matching, and the Teams group.
struct TeamMatcherTests {
    static func url(_ n: Int) -> String { "https://cdn.example/t/game/\(n)/chunks.m3u8" }

    /// Today's shape (2026-11-03): games in "Live-Games" with -A/-H feeds, replays without a suffix.
    static let playlist = """
    #EXTM3U
    #EXTINF:0 tvg-id="ESPN.us" group-title="Live-Channels",ESPN
    \(url(1))
    #EXTINF:0 tvg-id="Miami Heat @ Los Angeles Lakers-A" group-title="Live-Games",Miami Heat @ Los Angeles Lakers-A
    \(url(2))
    #EXTINF:0 tvg-id="Miami Heat @ Los Angeles Lakers-H" group-title="Live-Games",Miami Heat @ Los Angeles Lakers-H
    \(url(3))
    #EXTINF:0 tvg-id="Toronto Raptors @ Los Angeles Clippers-H" group-title="Live-Games",Toronto Raptors @ Los Angeles Clippers-H
    \(url(4))
    #EXTINF:0 tvg-id="Miami Heat @ Los Angeles Lakers" group-title="NBA-Replays",Miami Heat @ Los Angeles Lakers
    \(url(5))
    #EXTINF:0 tvg-id="Kansas City Chiefs @ Denver Broncos" group-title="NFL-Replays",Kansas City Chiefs @ Denver Broncos
    \(url(6))
    """

    static let heatAway = "id:miami heat @ los angeles lakers-a"
    static let heatHome = "id:miami heat @ los angeles lakers-h"
    static let espn = "id:espn.us"

    private var channels: [Channel] {
        get throws { ChannelList.make(from: try M3UParser.parse(Self.playlist)) }
    }

    private func programme(_ title: String, subtitle: String? = nil, category: String? = nil) -> Programme {
        let start = Date(timeIntervalSince1970: 1_791_200_000)
        return Programme(channelID: "espn.us", start: start, stop: start + 3600, title: title, subtitle: subtitle,
                         category: category)
    }

    // MARK: Catalog

    @Test func catalogHasEveryTeamOnce() {
        #expect(TeamCatalog.teams.count == 124)
        #expect(Set(TeamCatalog.teams.map(\.id)).count == 124)
        #expect(TeamLeague.allCases.map { TeamCatalog.teams(in: $0).count } == [32, 30, 32, 30])
        // Every full name and alias finds its own team.
        for team in TeamCatalog.teams {
            for name in team.fullNames {
                #expect(TeamMatcher.team(named: name) == team, "\(name)")
            }
        }
        #expect(TeamMatcher.team(named: "los angeles LAKERS") == TeamCatalog.byID["nba.lal"])
        #expect(TeamMatcher.team(named: "Montréal Canadiens") == TeamCatalog.byID["nhl.mtl"])
        #expect(TeamMatcher.team(named: "Los Angeles") == nil)
    }

    // MARK: Feed names (ChannelList.make)

    @Test func feedNamesAreSpelledOutAndIdsKept() throws {
        let channels = try channels
        #expect(channels[1].name == "Miami Heat @ Los Angeles Lakers (Away Feed)")
        #expect(channels[2].name == "Miami Heat @ Los Angeles Lakers (Home Feed)")
        #expect(channels[1].id == Self.heatAway)
        #expect(channels[2].id == Self.heatHome)
        // A replay without a suffix, and other names, are unchanged.
        #expect(channels[4].name == "Miami Heat @ Los Angeles Lakers")
        #expect(ChannelList.feedName("ESPN-H") == "ESPN-H")
        #expect(ChannelList.feedName("Philadelphia @ Tampa Bay-A") == "Philadelphia @ Tampa Bay (Away Feed)")
        #expect(TeamMatcher.game(from: channels[2].name)
                == TeamMatcher.Game(away: "Miami Heat", home: "Los Angeles Lakers", feed: .home))
    }

    @Test func feedNamesWithoutTvgIDKeepTheirOldID() {
        let entry = M3UEntry(name: "A Team @ B Team-H", attributes: [:], group: "Live-Games", url: Self.url(9))
        let channel = ChannelList.make(from: M3UPlaylist(guideURLs: [], entries: [entry]))[0]
        #expect(channel.id == "name:a team @ b team-h")
        #expect(channel.name == "A Team @ B Team (Home Feed)")
    }

    // MARK: Games

    @Test func gamesMatchEitherSideWithThePickedTeamsFeedFirst() throws {
        let channels = try channels
        #expect(TeamMatcher.gameChannelIDs(channels: channels, picked: ["nba.lal"]) == [Self.heatHome, Self.heatAway])
        #expect(TeamMatcher.gameChannelIDs(channels: channels, picked: ["nba.mia"]) == [Self.heatAway, Self.heatHome])
        // Both teams: playlist order.
        #expect(TeamMatcher.gameChannelIDs(channels: channels, picked: ["nba.mia", "nba.lal"]) == [Self.heatAway, Self.heatHome])
        // Another Los Angeles team doesn't match the Lakers game.
        #expect(TeamMatcher.gameChannelIDs(channels: channels, picked: ["nba.lac"])
                == ["id:toronto raptors @ los angeles clippers-h"])
        // Replays never match.
        #expect(TeamMatcher.gameChannelIDs(channels: channels, picked: ["nfl.den", "nfl.kc"]).isEmpty)
        #expect(TeamMatcher.channelIDs(channels: channels, nowPlaying: [:], picked: []).isEmpty)
        #expect(TeamMatcher.teams(inGame: channels[2]).map(\.id) == ["nba.mia", "nba.lal"])
        #expect(TeamMatcher.teams(inGame: channels[4]).isEmpty)
    }

    // MARK: Networks

    @Test func networkProgrammesMatchByNameOrNicknameAndLeague() throws {
        let heatGame = programme("NBA Basketball", subtitle: "Miami Heat at Los Angeles Lakers")
        #expect(Set(TeamMatcher.teams(in: heatGame).map(\.id)) == ["nba.mia", "nba.lal"])
        let kings = programme("Kings", category: "Hockey")
        #expect(TeamMatcher.teams(in: kings).map(\.id) == ["nhl.la"])
        // A nickname alone isn't enough, and a one-word full name needs a league word too.
        #expect(TeamMatcher.teams(in: programme("Kings of Comedy")).isEmpty)
        #expect(TeamMatcher.teams(in: programme("World Athletics Championships")).isEmpty)
        #expect(TeamMatcher.teams(in: programme("MLB Baseball", subtitle: "Athletics at Rays")).map(\.id).sorted()
                == ["mlb.ath", "mlb.tb"])
        // Shows about a game aren't the game.
        #expect(!TeamMatcher.isLiveGame(programme("Lakers Postgame", category: "Basketball")))
        #expect(TeamMatcher.isLiveGame(heatGame))

        let channels = try channels
        let now: [Channel.ID: Programme] = [Self.espn: heatGame]
        #expect(TeamMatcher.networkChannelIDs(channels: channels, nowPlaying: now, picked: ["nba.mia"]) == [Self.espn])
        #expect(TeamMatcher.networkChannelIDs(channels: channels, nowPlaying: now, picked: ["nhl.la"]).isEmpty)
        #expect(TeamMatcher.networkChannelIDs(channels: channels,
                                              nowPlaying: [Self.espn: programme("Lakers Postgame", subtitle: "NBA")],
                                              picked: ["nba.lal"]).isEmpty)
        // Games first, then networks.
        #expect(TeamMatcher.channelIDs(channels: channels, nowPlaying: now, picked: ["nba.mia"])
                == [Self.heatAway, Self.heatHome, Self.espn])
    }

    // MARK: Lineup and preferences

    @Test func teamsGroupComesRightAfterFavoritesWithAVisibleMatch() throws {
        let channels = try channels
        let ids = [Self.heatHome, Self.heatAway]
        let both = ChannelLineup(channels: channels, preferences: ChannelPreferences(favorites: [Self.espn]), teamChannelIDs: ids)
        #expect(Array(both.groups.prefix(3)) == ["Favorites", "Teams", "All Channels"])
        #expect(both.channels(in: "Teams").map(\.id) == ids)
        let noFavorites = ChannelLineup(channels: channels, teamChannelIDs: ids)
        #expect(Array(noFavorites.groups.prefix(2)) == ["Teams", "All Channels"])
        // Nothing visible: no Teams group.
        let hidden = ChannelLineup(channels: channels, preferences: ChannelPreferences(hiddenGroups: ["Live-Games"]),
                                   teamChannelIDs: ids)
        #expect(!hidden.groups.contains("Teams"))
        #expect(!ChannelLineup(channels: channels).groups.contains("Teams"))
    }

    @Test func preferencesKeepTeams() throws {
        let preferences = ChannelPreferences(favorites: ["id:a"], teams: ["nba.lal", "nhl.la"])
        let data = try JSONEncoder().encode(preferences)
        #expect(try JSONDecoder().decode(ChannelPreferences.self, from: data) == preferences)
        let old = try JSONDecoder().decode(ChannelPreferences.self, from: Data(#"{"favorites":["id:a"]}"#.utf8))
        #expect(old.teams == [])
        #expect(old.favorites == ["id:a"])
    }

    // MARK: Library and the channel menu

    private func makeFixture(state: IPTVState? = nil) async throws -> LibraryFixture {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, texts: [IPTVFixtures.playlistURL: Self.playlist],
                                      state: state)
        await fixture.library.refreshPlaylist()
        return fixture
    }

    @Test func pickingATeamBuildsTheTeamsGroup() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let library = fixture.library
        #expect(!library.lineup.groups.contains("Teams"))
        library.setTeamPicked("nba.lal", true)
        await library.teamUpdateTask?.value
        #expect(library.preferences.teams == ["nba.lal"])
        #expect(fixture.preferencesFile.load().teams == ["nba.lal"])
        #expect(library.lineup.groups.first == "Teams")
        #expect(library.lineup.channels(in: "Teams").map(\.id) == [Self.heatHome, Self.heatAway])
        // Unknown ids aren't picked; unpicking empties the group.
        library.setTeamPicked("nba.nope", true)
        #expect(library.preferences.teams == ["nba.lal"])
        library.setTeamPicked("nba.lal", false)
        await library.teamUpdateTask?.value
        #expect(!library.lineup.groups.contains("Teams"))
    }

    @Test func theChannelMenuOffersTheGamesTeams() async throws {
        let fixture = try await makeFixture(state: IPTVState(lastChannelID: Self.heatHome))
        defer { fixture.cleanUp() }
        let model = LiveTVModel(player: FakePlayer(), makePlayer: { FakePlayer() }, library: fixture.library,
                                now: { fixture.clock.now })
        model.open()
        await model.pendingTask?.value
        #expect(model.mode == .player)
        _ = model.handle(.menu)
        let titles = model.menu?.items.map(\.title) ?? []
        #expect(titles.contains("Add Miami Heat to Teams"))
        #expect(titles.contains("Add Los Angeles Lakers to Teams"))
        // Select the first one.
        let index = try #require(titles.firstIndex(of: "Add Miami Heat to Teams"))
        for _ in 0..<index { _ = model.handle(.down) }
        _ = model.handle(.select)
        await fixture.library.teamUpdateTask?.value
        #expect(fixture.library.isTeamPicked("nba.mia"))
        _ = model.handle(.menu)
        #expect(model.menu?.items.map(\.title).contains("Remove Miami Heat from Teams") == true)
    }
}
