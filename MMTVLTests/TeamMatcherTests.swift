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

    private func programme(_ title: String, subtitle: String? = nil, category: String? = nil,
                           summary: String? = nil) -> Programme {
        let start = Date(timeIntervalSince1970: 1_791_200_000)
        return Programme(channelID: "espn.us", start: start, stop: start + 3600, title: title, subtitle: subtitle,
                         summary: summary, category: category)
    }

    // MARK: Catalog

    @Test func catalogHasEveryTeamOnce() {
        #expect(TeamCatalog.proTeams.count == 124)
        #expect(Set(TeamCatalog.proTeams.map(\.id)).count == 124)
        #expect(TeamLeague.allCases.filter { !$0.isCollege }.map { TeamCatalog.teams(in: $0).count } == [32, 30, 32, 30])
        // Every full name and alias finds its own team.
        for team in TeamCatalog.proTeams {
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

    /// M7l step 8a (build 29 on the TV): a game in a league's own group, next to its network channels.
    static let leagueGroups = """
    #EXTM3U
    #EXTINF:0 tvg-id="NFLNetwork.us" group-title="NFL",NFL Network
    \(url(31))
    #EXTINF:0 tvg-id="Tampa Bay Buccaneers @ Chicago Bears-H" group-title="NFL",Tampa Bay Buccaneers @ Chicago Bears-H
    \(url(32))
    #EXTINF:0 tvg-id="Tampa Bay Buccaneers @ Chicago Bears-A" group-title="NFL",Tampa Bay Buccaneers @ Chicago Bears-A
    \(url(33))
    #EXTINF:0 tvg-id="Tampa Bay Buccaneers @ Chicago Bears" group-title="NFL",Tampa Bay Buccaneers @ Chicago Bears
    \(url(34))
    #EXTINF:0 tvg-id="NFLRedZone.us" group-title="NFL",NFL RedZone
    \(url(35))
    #EXTINF:0 tvg-id="Some Team @ Other Team" group-title="NFL",Some Team @ Other Team
    \(url(36))
    #EXTINF:0 tvg-id="Tampa Bay Buccaneers @ Chicago Bears (R)" group-title="NFL Replays",Tampa Bay Buccaneers @ Chicago Bears
    \(url(37))
    """

    @Test func gameEntriesCountInAnyGroupButReplays() throws {
        let channels = ChannelList.make(from: try M3UParser.parse(Self.leagueGroups))
        let network = "id:nflnetwork.us"
        let home = "id:tampa bay buccaneers @ chicago bears-h"
        let away = "id:tampa bay buccaneers @ chicago bears-a"
        let plain = "id:tampa bay buccaneers @ chicago bears"
        let redZone = "id:nflredzone.us"
        func channel(_ id: Channel.ID) throws -> Channel { try #require(channels.first { $0.id == id }) }

        #expect(channels.filter { TeamMatcher.isGameEntry($0) }.map(\.id) == [home, away, plain])
        // Neither side a known team, or a Replays group: not a game.
        #expect(!TeamMatcher.isGameEntry(try channel("id:some team @ other team")))
        #expect(!TeamMatcher.isGameEntry(try channel("id:tampa bay buccaneers @ chicago bears (r)")))

        // The picked team's feed first, then the rest in playlist order; the replay never.
        #expect(TeamMatcher.gameChannelIDs(channels: channels, picked: ["nfl.tb"]) == [away, home, plain])
        #expect(TeamMatcher.gameChannelIDs(channels: channels, picked: ["nfl.chi"]) == [home, away, plain])
        #expect(TeamMatcher.gameChannelIDs(channels: channels, picked: ["nfl.tb", "nfl.chi"]) == [home, away, plain])
        #expect(TeamMatcher.gameChannelIDs(channels: channels, picked: ["nfl.kc"]).isEmpty)

        // The channel menu's teams.
        #expect(TeamMatcher.teams(inGame: try channel(home)).map(\.id) == ["nfl.tb", "nfl.chi"])
        #expect(TeamMatcher.teams(inGame: try channel(network)).isEmpty)
        #expect(TeamMatcher.teams(inGame: try channel("id:tampa bay buccaneers @ chicago bears (r)")).isEmpty)

        // Channels in "NFL" that aren't games still match by their programme; a game entry never as a network.
        let game = programme("NFL Football", subtitle: "Tampa Bay Buccaneers at Chicago Bears")
        let now: [Channel.ID: Programme] = [network: game, redZone: programme("NFL RedZone", subtitle: "Buccaneers"),
                                            home: game]
        #expect(TeamMatcher.networkChannelIDs(channels: channels, nowPlaying: now, picked: ["nfl.tb"])
                == [network, redZone])
        #expect(TeamMatcher.channelIDs(channels: channels, nowPlaying: now, picked: ["nfl.tb"])
                == [away, home, plain, network, redZone])
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
        #expect(Array(both.groups.prefix(3)) == ["Favorites", "My Teams", "All Channels"])
        #expect(both.channels(in: "My Teams").map(\.id) == ids)
        let noFavorites = ChannelLineup(channels: channels, teamChannelIDs: ids)
        // M7l 8b: live team games alone make a Favorites group.
        #expect(Array(noFavorites.groups.prefix(3)) == ["Favorites", "My Teams", "All Channels"])
        // No live game visible.
        let hidden = ChannelLineup(channels: channels, preferences: ChannelPreferences(hiddenGroups: ["Live-Games"]),
                                   teamChannelIDs: ids)
        // M7l 8c: My Teams still shows, with no live channels.
        #expect(hidden.groups.contains("My Teams"))
        #expect(hidden.channels(in: "My Teams").isEmpty)
        #expect(ChannelLineup(channels: channels).groups.contains("My Teams"))
        #expect(ChannelLineup(channels: channels).channels(in: "My Teams").isEmpty)
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
        #expect(library.lineup.groups.contains("My Teams"))
        #expect(library.lineup.channels(in: "My Teams").isEmpty)
        library.setTeamPicked("nba.lal", true)
        await library.teamUpdateTask?.value
        #expect(library.preferences.teams == ["nba.lal"])
        #expect(fixture.preferencesFile.load().teams == ["nba.lal"])
        #expect(Array(library.lineup.groups.prefix(2)) == ["Favorites", "My Teams"])
        #expect(library.lineup.channels(in: "My Teams").map(\.id) == [Self.heatHome, Self.heatAway])
        // Unknown ids aren't picked; unpicking empties the group.
        library.setTeamPicked("nba.nope", true)
        #expect(library.preferences.teams == ["nba.lal"])
        library.setTeamPicked("nba.lal", false)
        await library.teamUpdateTask?.value
        #expect(library.lineup.groups.contains("My Teams"))
        #expect(library.lineup.channels(in: "My Teams").isEmpty)
    }

    /// M7l 8b: a picked team's live game tops the guide's Favorites group (every feed, Teams' order), then the saved
    /// favorites; the saved list, the favorite actions and the home preview's default channel use the saved list only.
    @Test func aLiveTeamGameTopsFavorites() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, texts: [IPTVFixtures.playlistURL: Self.playlist],
                                      preferences: ChannelPreferences(favorites: [Self.espn]))
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshPlaylist()
        #expect(library.lineup.channels(in: "Favorites").map(\.id) == [Self.espn])
        library.setTeamPicked("nba.lal", true)
        await library.teamUpdateTask?.value
        #expect(library.lineup.channels(in: "Favorites").map(\.id) == [Self.heatHome, Self.heatAway, Self.espn])
        #expect(library.lineup.channels(in: "My Teams").map(\.id) == [Self.heatHome, Self.heatAway])
        #expect(library.lineup.favorites.map(\.id) == [Self.espn])
        #expect(library.preferences.favorites == [Self.espn])
        #expect(fixture.preferencesFile.load().favorites == [Self.espn])
        #expect(!library.isFavorite(Self.heatHome))
        let model = LiveTVModel(player: FakePlayer(), makePlayer: { FakePlayer() }, library: library,
                                now: { fixture.clock.now })
        #expect(model.defaultPreviewChannelID == Self.espn)

        // Saved as a favorite too: once, at the top; the actions change the saved list only.
        library.setFavorite(Self.heatHome, true)
        #expect(fixture.preferencesFile.load().favorites == [Self.espn, Self.heatHome])
        #expect(library.lineup.channels(in: "Favorites").map(\.id) == [Self.heatHome, Self.heatAway, Self.espn])
        // A Teams channel doesn't move (orchestrator, 8b), saved or not.
        library.moveFavorite(Self.heatHome, by: -1)
        library.moveFavorite(Self.heatAway, by: 1)
        #expect(fixture.preferencesFile.load().favorites == [Self.espn, Self.heatHome])
        library.setFavorite(Self.heatHome, false)
        #expect(fixture.preferencesFile.load().favorites == [Self.espn])

        // The game ends (team unpicked): Favorites is the saved list again.
        library.setTeamPicked("nba.lal", false)
        await library.teamUpdateTask?.value
        #expect(library.lineup.channels(in: "Favorites").map(\.id) == [Self.espn])
    }

    static let heatReplay = "id:miami heat @ los angeles lakers"

    /// M7l 8b (orchestrator): in Favorites, Move Up/Down only for the saved favorites below the team channels, among
    /// themselves. Saved [ESPN, Heat home, Heat replay], the Lakers picked: the guide shows the game's feeds, then
    /// [ESPN, replay]; ESPN's Move Down swaps it with the replay in the saved list.
    @Test func favoritesMoveOnlyBelowTheTeamChannels() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, texts: [IPTVFixtures.playlistURL: Self.playlist],
                                      state: IPTVState(lastChannelID: Self.espn),
                                      preferences: ChannelPreferences(favorites: [Self.espn, Self.heatHome, Self.heatReplay]))
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshPlaylist()
        library.setTeamPicked("nba.lal", true)
        await library.teamUpdateTask?.value
        #expect(library.lineup.movableFavorites.map(\.id) == [Self.espn, Self.heatReplay])
        let model = LiveTVModel(player: FakePlayer(), makePlayer: { FakePlayer() }, library: library,
                                now: { fixture.clock.now })
        model.open()
        await model.pendingTask?.value
        if model.banner != nil || model.showsTimeshiftBar { _ = model.handle(.back) }
        _ = model.handle(.back)
        #expect(model.mode == .guide)
        #expect(model.guide?.selectedGroup == "Favorites")
        #expect(model.guide?.channels.map(\.id) == [Self.heatHome, Self.heatAway, Self.espn, Self.heatReplay])

        func menuIDs(on id: Channel.ID) -> [String] {
            for _ in 0..<5 where model.guide?.focusedChannel?.id != id { _ = model.handle(.up) }
            for _ in 0..<5 where model.guide?.focusedChannel?.id != id { _ = model.handle(.down) }
            #expect(model.guide?.focusedChannel?.id == id)
            _ = model.handle(.left)
            _ = model.handle(.select)
            let ids = model.menu?.items.map(\.id) ?? []
            _ = model.handle(.back)
            _ = model.handle(.right)
            return ids
        }
        // Team rows, saved or not: no Move items; Add/Remove Favorite still there.
        #expect(!menuIDs(on: Self.heatHome).contains { $0.hasPrefix("move") })
        #expect(menuIDs(on: Self.heatHome).contains("favorite"))
        #expect(!menuIDs(on: Self.heatAway).contains { $0.hasPrefix("move") })
        // The tail [ESPN, replay]: ESPN first, the replay last.
        #expect(menuIDs(on: Self.espn).filter { $0.hasPrefix("move") } == ["moveDown"])
        #expect(menuIDs(on: Self.heatReplay).filter { $0.hasPrefix("move") } == ["moveUp"])

        // ESPN's Move Down, from the menu.
        for _ in 0..<5 where model.guide?.focusedChannel?.id != Self.espn { _ = model.handle(.up) }
        _ = model.handle(.left)
        _ = model.handle(.select)
        let moveDown = try #require(model.menu?.items.firstIndex { $0.id == "moveDown" })
        for _ in 0..<moveDown { _ = model.handle(.down) }
        _ = model.handle(.select)
        #expect(fixture.preferencesFile.load().favorites == [Self.heatReplay, Self.heatHome, Self.espn])
        #expect(model.guide?.focusedChannel?.id == Self.espn)
        #expect(library.lineup.channels(in: "Favorites").map(\.id) == [Self.heatHome, Self.heatAway, Self.heatReplay, Self.espn])
        #expect(model.guide?.channels.map(\.id) == [Self.heatHome, Self.heatAway, Self.heatReplay, Self.espn])
        // Past the tail's end does nothing.
        library.moveFavorite(Self.espn, by: 1)
        #expect(fixture.preferencesFile.load().favorites == [Self.heatReplay, Self.heatHome, Self.espn])
    }

    /// M7l (QA): quick picks; the first update, held at a slow programme fetch, finishes last and is ignored.
    @Test func aLateTeamUpdateDoesntUndoANewerPick() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let library = fixture.library
        let gate = SlowFetchGate()
        library.afterTeamProgrammesFetch = { await gate.wait() }
        library.setTeamPicked("nba.lal", true)
        let first = library.teamUpdateTask
        for _ in 0..<1000 where !gate.isWaiting { await Task.yield() }
        #expect(gate.isWaiting)
        library.setTeamPicked("nba.tor", true)
        await library.teamUpdateTask?.value
        gate.release()
        await first?.value
        #expect(Set(library.lineup.channels(in: "My Teams").map(\.id))
                == [Self.heatAway, Self.heatHome, "id:toronto raptors @ los angeles clippers-h"])
    }

    /// M7l (QA): a cancelled update with the picks unchanged (AppDelegate restarting the 5-minute refresh) still
    /// sets the group.
    @Test func aCancelledUpdateWithTheSamePicksStillSetsTheGroup() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let library = fixture.library
        let gate = SlowFetchGate()
        library.afterTeamProgrammesFetch = { await gate.wait() }
        library.setTeamPicked("nba.lal", true)
        let update = library.teamUpdateTask
        for _ in 0..<1000 where !gate.isWaiting { await Task.yield() }
        #expect(gate.isWaiting)
        update?.cancel()
        gate.release()
        await update?.value
        #expect(library.lineup.channels(in: "My Teams").map(\.id) == [Self.heatHome, Self.heatAway])
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
        #expect(titles.contains("Add Miami Heat to My Teams"))
        #expect(titles.contains("Add Los Angeles Lakers to My Teams"))
        // Select the first one.
        let index = try #require(titles.firstIndex(of: "Add Miami Heat to My Teams"))
        for _ in 0..<index { _ = model.handle(.down) }
        _ = model.handle(.select)
        await fixture.library.teamUpdateTask?.value
        #expect(fixture.library.isTeamPicked("nba.mia"))
        _ = model.handle(.menu)
        #expect(model.menu?.items.map(\.title).contains("Remove Miami Heat from My Teams") == true)
    }

    // MARK: College (M7l L10), with fixture teams

    private static func college(_ league: TeamLeague, _ slug: String, _ name: String, school: String, nickname: String,
                                conference: String = "Test", aliases: [String] = [], abbreviations: [String] = []) -> Team {
        Team(id: "\(league.rawValue).\(slug)", league: league, name: name, school: school, nickname: nickname,
             conference: conference, aliases: aliases, abbreviations: abbreviations)
    }

    static let collegeFixture: [Team] = [
        college(.ncaaf, "texas-am-aggies", "Texas A&M Aggies", school: "Texas A&M", nickname: "Aggies", aliases: ["Texas A&M"]),
        college(.ncaaf, "south-carolina-gamecocks", "South Carolina Gamecocks", school: "South Carolina",
                nickname: "Gamecocks", aliases: ["South Carolina"]),
        college(.ncaaf, "texas-longhorns", "Texas Longhorns", school: "Texas", nickname: "Longhorns", aliases: ["Texas"]),
        college(.ncaaf, "georgia-bulldogs", "Georgia Bulldogs", school: "Georgia", nickname: "Bulldogs", aliases: ["Georgia"]),
        college(.ncaaf, "oklahoma-sooners", "Oklahoma Sooners", school: "Oklahoma", nickname: "Sooners", aliases: ["Oklahoma"]),
        college(.ncaaf, "ohio-state-buckeyes", "Ohio State Buckeyes", school: "Ohio State", nickname: "Buckeyes",
                aliases: ["Ohio St", "Ohio State"]),
        college(.ncaam, "grambling-tigers", "Grambling Tigers", school: "Grambling", nickname: "Tigers",
                aliases: ["Grambling", "Grambling State"]),
        college(.ncaam, "texas-longhorns", "Texas Longhorns", school: "Texas", nickname: "Longhorns", aliases: ["Texas"]),
        college(.ncaam, "duke-blue-devils", "Duke Blue Devils", school: "Duke", nickname: "Blue Devils", aliases: ["Duke"]),
        college(.ncaam, "kansas-jayhawks", "Kansas Jayhawks", school: "Kansas", nickname: "Jayhawks", aliases: ["Kansas"]),
        college(.ncaam, "villanova-wildcats", "Villanova Wildcats", school: "Villanova", nickname: "Wildcats",
                aliases: ["Villanova"]),
        college(.ncaam, "princeton-tigers", "Princeton Tigers", school: "Princeton", nickname: "Tigers", aliases: ["Princeton"]),
        college(.ncaaw, "villanova-wildcats", "Villanova Wildcats", school: "Villanova", nickname: "Wildcats",
                aliases: ["Villanova"]),
        college(.ncaaw, "princeton-tigers", "Princeton Tigers", school: "Princeton", nickname: "Tigers", aliases: ["Princeton"]),
        college(.ncaaw, "grambling-lady-tigers", "Grambling Lady Tigers", school: "Grambling", nickname: "Lady Tigers",
                aliases: ["Grambling", "Grambling State"]),
        college(.ncaaw, "michigan-wolverines", "Michigan Wolverines", school: "Michigan", nickname: "Wolverines",
                aliases: ["Michigan"]),
    ]

    static let index = TeamMatcher.Index(teams: TeamCatalog.proTeams + collegeFixture)

    private func ids(_ programme: Programme, _ index: TeamMatcher.Index = Self.index) -> Set<Team.ID> {
        Set(TeamMatcher.teams(in: programme, index: index).map(\.id))
    }

    @Test func collegeSportComesFromTheTitleAndCategory() {
        #expect(TeamMatcher.collegeLeague(of: programme("College Football")) == .ncaaf)
        #expect(TeamMatcher.collegeLeague(of: programme("Live: College Basketball")) == .ncaam)
        #expect(TeamMatcher.collegeLeague(of: programme("Live: Women's College Basketball")) == .ncaaw)
        #expect(TeamMatcher.collegeLeague(of: programme("College Baseball")) == .ncaabase)
        #expect(TeamMatcher.collegeLeague(of: programme("Basketball", category: "NCAAW")) == .ncaaw)
        #expect(TeamMatcher.collegeLeague(of: programme("Live: Women's College Soccer")) == nil)
        #expect(TeamMatcher.collegeLeague(of: programme("NBA Basketball")) == nil)
    }

    @Test func collegeSidesAreParsedExactly() {
        #expect(TeamMatcher.collegeSides(of: programme("College Football", subtitle: "Texas A&M at South Carolina"))
                == [" texas a m ", " south carolina "])
        #expect(TeamMatcher.collegeSides(of: programme("College Basketball", subtitle: "SEC Tournament: Georgia vs. Oklahoma"))
                == [" georgia ", " oklahoma "])
        #expect(TeamMatcher.collegeSides(of: programme("College Basketball", subtitle: "#5 Duke vs Kansas"))
                == [" duke ", " kansas "])
        #expect(TeamMatcher.collegeSides(of: programme("College Basketball", subtitle: "(12) Duke @ Kansas"))
                == [" duke ", " kansas "])
        // No subtitle: the title after its first ":", never after "Live:".
        #expect(TeamMatcher.collegeSides(of: programme("College Football: Georgia at Texas")) == [" georgia ", " texas "])
        #expect(TeamMatcher.collegeSides(of: programme("Live: College Basketball")).isEmpty)
        #expect(TeamMatcher.collegeSides(of: programme("College Football", subtitle: "TBA")).isEmpty)
    }

    /// M7m L25: the guide's own summaries (2026-11-10), for games with no subtitle.
    @Test func collegeSidesFromTheSummary() {
        func sides(_ summary: String, subtitle: String? = nil) -> [String] {
            TeamMatcher.collegeSides(of: programme("Live: College Basketball", subtitle: subtitle, summary: summary))
        }
        #expect(sides("The No. 1 Florida Gators visit the Florida State Seminoles for an NCAA Division I game in Florida. "
                      + "The Gators lead the series.") == [" florida gators ", " florida state seminoles "])
        #expect(sides("The No. 6 Michigan State Spartans face the No. 2 Duke Blue Devils for an NCAA Division I game.")
                == [" michigan state spartans ", " duke blue devils "])
        #expect(sides("The Ohio Bobcats visit the Miami (OH) RedHawks for a MAC game.")
                == [" ohio bobcats ", " miami oh redhawks "])
        #expect(sides("The Nebraska Cornhuskers (5-3) visit the Illinois Fighting Illini (5-3) at Memorial Stadium.")
                == [" nebraska cornhuskers ", " illinois fighting illini "])
        #expect(sides("The Louisiana-Monroe Warhawks host the Louisiana Ragin' Cajuns in Sun Belt play.")
                == [" louisiana monroe warhawks ", " louisiana ragin cajuns "])
        #expect(sides("The Pittsburgh Panthers meet the Florida State Seminoles.")
                == [" pittsburgh panthers ", " florida state seminoles "])
        #expect(sides("The Colorado Buffaloes clash with the No. 17 Houston Cougars in Big 12 play.")
                == [" colorado buffaloes ", " houston cougars "])
        // "St." doesn't end a side.
        #expect(sides("The Villanova Wildcats host the St. John's Red Storm.") == [" villanova wildcats ", " st john s red storm "])
        // An initial doesn't end a side either.
        #expect(sides("The Duke Blue Devils host the Stephen F. Austin Lumberjacks for a non-conference game.")
                == [" duke blue devils ", " stephen f austin lumberjacks "])
        #expect(TeamMatcher.teams(in: programme("College Basketball", summary: "The Duke Blue Devils host the "
                                                + "Stephen F. Austin Lumberjacks for a non-conference game."),
                                  among: TeamMatcher.Index.bundled(.off).byID["ncaam.stephen-f-austin-lumberjacks"].map { [$0] } ?? [])
                .map(\.id) == ["ncaam.stephen-f-austin-lumberjacks"])
        // No teams, or no verb the lead knows.
        #expect(sides("From Breslin Center in East Lansing, Mich.").isEmpty)
        #expect(sides("The Huskies (5-3, 2-3 Big Ten) try to solve the Nittany Lions (4-4, 1-4).").isEmpty)
        #expect(sides("Men's college basketball action.").isEmpty)
        // A subtitle still wins over the summary.
        #expect(sides("The No. 1 Florida Gators visit the Florida State Seminoles for an NCAA Division I game.",
                      subtitle: "Duke at Kansas") == [" duke ", " kansas "])
    }

    /// QA and the security review: only the summary's lead is read (UTF-16 units, whitespace collapsed), so a long or
    /// hostile description can't backtrack for seconds.
    @Test func aLongHostileSummaryIsCheap() {
        let spaces = "the" + String(repeating: "     visits     the", count: 5) + String(repeating: " ", count: 300) + "x"
        let hostile = [
            "The A" + String(repeating: " visits the (1", count: 1_500),   // ~21,000 characters
            spaces,
            spaces.replacingOccurrences(of: " ", with: "\n"),
            "the " + String(repeating: "a visits the ", count: 30) + "b" + String(repeating: "\u{301}", count: 200_000),
        ]
        for (n, summary) in hostile.enumerated() {
            let start = Date()
            #expect(TeamMatcher.summarySides(of: summary).isEmpty, "\(n)")
            #expect(Date().timeIntervalSince(start) < 0.5, "\(n)")
        }
        // Collapsed whitespace still reads a lead split over lines.
        #expect(TeamMatcher.summarySides(of: "The Duke Blue Devils host\n  the Kansas Jayhawks for a game.")
                == [" duke blue devils ", " kansas jayhawks "])
    }

    /// The security review for build 34 (M1): the old regex backtracked on repeated verb phrases within its 400-unit
    /// cap (~17 ms each, ~27 ms hill-climbed); the scan is linear.
    @Test func repeatedVerbPhrasesAreCheap() {
        let attacks = ["#1 x plays the ", "#1 x hosts the ", "no. 1 x plays the ", "(1) x plays the ", "#1 x (1) meets the "]
        for attack in attacks {
            let summary = "the " + String(repeating: attack, count: 40)
            let start = Date()
            for _ in 0..<10 { _ = TeamMatcher.summarySides(of: summary) }
            let each = Date().timeIntervalSince(start) / 10
            #expect(each < 0.005, "\(attack): \(each * 1000) ms")
        }
        // As a whole programme, the way `networkChannelIDs` reaches it.
        let game = programme("Live: College Basketball", category: "Sports",
                             summary: "the " + String(repeating: "#1 x plays the ", count: 40))
        // Built on first use (tens of ms in Debug): build it before timing the match.
        let index = TeamMatcher.Index.bundled(.init(initials: true, nicknames: true))
        let start = Date()
        _ = TeamMatcher.teams(in: game, index: index)
        #expect(Date().timeIntervalSince(start) < 0.005)
    }

    /// M1: random leads from the pieces the lead reads, each bounded.
    @Test func fuzzedLeadsAreCheap() {
        let pieces = ["the", "#1", "no. 1", "(1", ")", "x", "st.", ",", ".", "visits", "faces", "meets", "hosts",
                      "clashes with", "takes on", "plays", "battles", "squares off against", "for", "at", "in", "on",
                      "to", "The", "(1-2)", "No.1"]
        var generator = SplitMix(seed: 34)
        var worst: TimeInterval = 0
        for _ in 0..<10_000 {
            var text = "the "
            while text.utf16.count < TeamMatcher.summaryLeadLength {
                text += pieces[Int(generator.next() % UInt64(pieces.count))] + (generator.next() % 4 == 0 ? "" : " ")
            }
            let start = Date()
            _ = TeamMatcher.summarySides(of: text)
            worst = max(worst, Date().timeIntervalSince(start))
        }
        #expect(worst < 0.005, "worst \(worst * 1000) ms")
    }

    /// The scan reads what the regex read: records, ranks, the end words and the "." exceptions.
    @Test func theLeadScanKeepsTheRegexsReadings() {
        func sides(_ summary: String) -> [String] { TeamMatcher.summarySides(of: summary) }
        #expect(sides("the #3 Duke Blue Devils (5-0) host the (12) Kansas Jayhawks (4-1), in a rematch.")
                == [" duke blue devils ", " kansas jayhawks "])
        #expect(sides("THE DUKE BLUE DEVILS VISIT THE KANSAS JAYHAWKS TONIGHT FOR A GAME.")
                == [" duke blue devils ", " kansas jayhawks tonight "])
        #expect(sides("The Texas Longhorns take on the Mt. Olive Trojans; it's early.") == [" texas longhorns ", " mt olive trojans "])
        #expect(sides("The Texas Longhorns squares off against the No. 9 Ohio State Buckeyes at noon.")
                == [" texas longhorns ", " ohio state buckeyes "])
        #expect(sides("The Duke Blue Devils clash with the UNC Tar Heels on-campus.") == [" duke blue devils ", " unc tar heels "])
        // A verb inside a word isn't one; the side runs to a real one.
        #expect(sides("The Visitors meet the Hosts.") == [" visitors ", " hosts "])
        // Not a lead.
        #expect(sides("Duke hosts the Kansas Jayhawks.").isEmpty)
        #expect(sides("The Duke Blue Devils host Kansas.").isEmpty)
        #expect(sides("The Duke Blue Devils host the Kansas Jayhawks").isEmpty)
        #expect(sides("The plays the x.").isEmpty)
    }

    @Test func aGatorsGameNamedOnlyInTheSummaryMatches() throws {
        let index = TeamMatcher.Index.bundled(.off)
        let gators = try #require(index.byID["ncaam.florida-gators"])
        let seminoles = try #require(index.byID["ncaam.florida-state-seminoles"])
        let bulls = try #require(index.byID["ncaam.south-florida-bulls"])
        let duke = try #require(index.byID["ncaam.duke-blue-devils"])
        let game = programme("Live: College Basketball", category: "Sports",
                             summary: "The No. 1 Florida Gators visit the Florida State Seminoles for an NCAA Division I "
                                + "game in Florida. The Gators look to stay unbeaten.")
        #expect(Set(TeamMatcher.teams(in: game, among: [gators, seminoles]).map(\.id))
                == ["ncaam.florida-gators", "ncaam.florida-state-seminoles"])
        #expect(TeamMatcher.teams(in: game, among: [gators]).map(\.id) == ["ncaam.florida-gators"])
        // Exact sides only: South Florida isn't "Florida State Seminoles" or "Florida Gators".
        #expect(TeamMatcher.teams(in: game, among: [bulls]).isEmpty)
        // Not a college programme: the summary isn't read for sides.
        let movie = programme("The Secret Life of Pets", category: "Movie",
                              summary: "Max's life is turned upside down when his owner adopts Duke, a big, unruly dog.")
        #expect(TeamMatcher.teams(in: movie, among: [duke]).isEmpty)
        let show = programme("SportsCenter", category: "Sports",
                             summary: "The Duke Blue Devils face the Kansas Jayhawks for a preview.")
        #expect(TeamMatcher.teams(in: show, among: [duke]).isEmpty)
    }

    @Test func collegeProgrammesMatchTheirSportsSchoolsExactly() {
        // Not Texas, though "texas a m at south carolina" contains "texas".
        #expect(ids(programme("College Football", subtitle: "Texas A&M at South Carolina", category: "Sports"))
                == ["ncaaf.texas-am-aggies", "ncaaf.south-carolina-gamecocks"])
        // An alias ("Grambling State"), and men's basketball only.
        #expect(ids(programme("Live: College Basketball", subtitle: "Grambling State at Texas"))
                == ["ncaam.grambling-tigers", "ncaam.texas-longhorns"])
        #expect(ids(programme("Live: Women's College Basketball", subtitle: "Villanova at Princeton"))
                == ["ncaaw.villanova-wildcats", "ncaaw.princeton-tigers"])
        // Not a college sport in the catalog.
        #expect(ids(programme("Live: Women's College Soccer", subtitle: "SEC Tournament: Georgia vs. Oklahoma")).isEmpty)
        // Rankings are dropped.
        #expect(ids(programme("College Basketball", subtitle: "No. 5 Duke vs. Kansas"))
                == ["ncaam.duke-blue-devils", "ncaam.kansas-jayhawks"])
        // Studio shows aren't the game.
        #expect(!TeamMatcher.isLiveGame(programme("College Basketball Pregame", subtitle: "Duke vs. Kansas")))
        // "basketball" in a college title isn't the NBA's: no nickname match for the Charlotte Hornets…
        #expect(ids(programme("College Basketball", subtitle: "Alabama State Hornets at Duke")) == ["ncaam.duke-blue-devils"])
        // …which still match by nickname in an NBA programme.
        #expect(ids(programme("NBA Basketball", subtitle: "Hornets at Heat")) == ["nba.cha", "nba.mia"])
        // Pro unchanged.
        #expect(ids(programme("NHL Hockey", subtitle: "New Jersey Devils at Toronto Maple Leafs")) == ["nhl.nj", "nhl.tor"])
    }

    @Test func collegeTeamsShowWithTheirSport() {
        #expect(Self.collegeFixture.last?.pickTitle == "Michigan Wolverines (Women's Basketball)")
        #expect(TeamCatalog.byID["nba.lal"]?.pickTitle == "Los Angeles Lakers")
    }

    static let collegeGames = """
    #EXTM3U
    #EXTINF:0 tvg-id="Michigan @ Ohio State-A" group-title="Live-Games",Michigan @ Ohio State-A
    \(url(11))
    #EXTINF:0 tvg-id="Michigan @ Ohio State-H" group-title="Live-Games",Michigan @ Ohio State-H
    \(url(12))
    #EXTINF:0 tvg-id="Grambling State @ Texas" group-title="Live-Games",Grambling State @ Texas
    \(url(13))
    #EXTINF:0 tvg-id="Michigan @ Ohio State" group-title="NCAA-Replays",Michigan @ Ohio State
    \(url(14))
    """

    @Test func collegeGameEntriesMatchTheSchoolInAnySport() throws {
        let channels = ChannelList.make(from: try M3UParser.parse(Self.collegeGames))
        let michiganAway = "id:michigan @ ohio state-a"
        let michiganHome = "id:michigan @ ohio state-h"
        func games(_ picked: Set<Team.ID>) -> [Channel.ID] {
            TeamMatcher.gameChannelIDs(channels: channels, picked: picked, index: Self.index)
        }
        // Michigan is only in women's basketball in the fixture: the entry doesn't say its sport.
        #expect(games(["ncaaw.michigan-wolverines"]) == [michiganAway, michiganHome])
        #expect(games(["ncaaf.ohio-state-buckeyes"]) == [michiganHome, michiganAway])
        // By school, not slug: the women's Grambling id differs from the men's.
        #expect(games(["ncaaw.grambling-lady-tigers"]) == ["id:grambling state @ texas"])
        #expect(games(["ncaaf.texas-longhorns"]) == ["id:grambling state @ texas"])
        #expect(games(["ncaam.duke-blue-devils"]).isEmpty)
        #expect(games(["nba.lal"]).isEmpty)
    }

    static let networks = """
    #EXTM3U
    #EXTINF:0 tvg-id="ESPN.us" group-title="Live-Channels",ESPN
    \(url(21))
    #EXTINF:0 tvg-id="SECN.us" group-title="Live-Channels",SEC Network
    \(url(22))
    #EXTINF:0 tvg-id="ESPN2.us" group-title="Live-Channels",ESPN2
    \(url(23))
    """

    @Test func networkMatchingTestsOnlyThePickedTeams() throws {
        let channels = ChannelList.make(from: try M3UParser.parse(Self.networks))
        let now: [Channel.ID: Programme] = [
            "id:espn.us": programme("Live: College Basketball", subtitle: "Grambling State at Texas"),
            "id:secn.us": programme("College Football", subtitle: "Texas A&M at South Carolina"),
            "id:espn2.us": programme("NBA Basketball", subtitle: "Miami Heat at Los Angeles Lakers"),
        ]
        // More college teams, none picked: the same results.
        let unpicked = [
            Self.college(.ncaabase, "texas-longhorns", "Texas Longhorns", school: "Texas", nickname: "Longhorns",
                         aliases: ["Texas"]),
            Self.college(.ncaaf, "grambling-tigers", "Grambling Tigers", school: "Grambling", nickname: "Tigers",
                         aliases: ["Grambling State"]),
        ]
        let bigger = TeamMatcher.Index(teams: TeamCatalog.proTeams + Self.collegeFixture + unpicked)
        let picks: [Set<Team.ID>] = [["ncaam.texas-longhorns"], ["ncaaf.texas-longhorns"], ["ncaaf.south-carolina-gamecocks"],
                                     ["nba.lal", "ncaam.grambling-tigers"], []]
        let expected: [[Channel.ID]] = [["id:espn.us"], [], ["id:secn.us"], ["id:espn.us", "id:espn2.us"], []]
        for (picked, result) in zip(picks, expected) {
            let small = TeamMatcher.networkChannelIDs(channels: channels, nowPlaying: now, picked: picked, index: Self.index)
            #expect(small == result, "\(picked)")
            #expect(TeamMatcher.networkChannelIDs(channels: channels, nowPlaying: now, picked: picked, index: bigger) == small)
        }
        // Only the candidates are looked at.
        let texas = try #require(Self.index.byID["ncaam.texas-longhorns"])
        #expect(TeamMatcher.teams(in: now["id:espn.us"]!, among: [texas], index: Self.index) == [texas])
    }

    // MARK: Name variants (M7m L27) and the nickname fallback (L28)

    /// Football teams for L27–L28: four Cougars (two in the Big 12), the Bearcats, Miners, Rainbow Warriors, two
    /// Mountaineers and two Huskies.
    static let variantFixture: [Team] = [
        college(.ncaaf, "houston-cougars", "Houston Cougars", school: "Houston", nickname: "Cougars", conference: "Big 12",
                aliases: ["Houston", "HOU"]),
        college(.ncaaf, "byu-cougars", "BYU Cougars", school: "BYU", nickname: "Cougars", conference: "Big 12",
                aliases: ["BYU", "Brigham Young"]),
        college(.ncaaf, "washington-state-cougars", "Washington State Cougars", school: "Washington State",
                nickname: "Cougars", conference: "Pac-12", aliases: ["Washington St", "Washington State", "WSU"]),
        college(.ncaaf, "cincinnati-bearcats", "Cincinnati Bearcats", school: "Cincinnati", nickname: "Bearcats",
                conference: "Big 12", aliases: ["Cincinnati", "CIN"]),
        college(.ncaaf, "utep-miners", "UTEP Miners", school: "UTEP", nickname: "Miners", conference: "Mountain West",
                aliases: ["UTEP", "Texas-El Paso"]),
        college(.ncaaf, "hawaii-rainbow-warriors", "Hawai'i Rainbow Warriors", school: "Hawai'i",
                nickname: "Rainbow Warriors", conference: "Mountain West", aliases: ["Hawaii", "HAW"]),
        college(.ncaaf, "app-state-mountaineers", "App State Mountaineers", school: "App State", nickname: "Mountaineers",
                conference: "Sun Belt", aliases: ["App State", "Appalachian State", "APP"]),
        college(.ncaaf, "west-virginia-mountaineers", "West Virginia Mountaineers", school: "West Virginia",
                nickname: "Mountaineers", conference: "Big 12", aliases: ["West Virginia", "WVU"]),
        college(.ncaaf, "houston-christian-huskies", "Houston Christian Huskies", school: "Houston Christian",
                nickname: "Huskies", conference: "Southland (FCS)", aliases: ["Houston Christian", "HCU"]),
        college(.ncaaf, "washington-huskies", "Washington Huskies", school: "Washington", nickname: "Huskies",
                conference: "Big Ten", aliases: ["Washington", "WASH"]),
        college(.ncaaf, "uconn-huskies", "UConn Huskies", school: "UConn", nickname: "Huskies",
                conference: "FBS Independents", aliases: ["UConn", "Connecticut"]),
        college(.ncaaf, "seattle-cougars", "Seattle Cougars", school: "Seattle", nickname: "Cougars",
                conference: "Test", aliases: ["Seattle"]),
        college(.ncaabase, "mercer-bears", "Mercer Bears", school: "Mercer", nickname: "Bears", aliases: ["Mercer", "MER"]),
        college(.ncaabase, "mercyhurst-lakers", "Mercyhurst Lakers", school: "Mercyhurst", nickname: "Lakers",
                aliases: ["Mercyhurst", "MER"]),
    ]

    /// Both of L29's options off (the default), and each on.
    static let variantIndex = TeamMatcher.Index(teams: TeamCatalog.proTeams + variantFixture)
    static let nicknameIndex = TeamMatcher.Index(teams: TeamCatalog.proTeams + variantFixture,
                                                 options: .init(nicknames: true))
    static let initials = TeamMatchOptions(initials: true)
    static let nicknames = TeamMatchOptions(nicknames: true)

    /// The ids of `candidates` (default: every fixture team) a football programme is about.
    private func variantIDs(_ subtitle: String? = nil, summary: String? = nil, title: String = "College Football",
                            among candidates: [String]? = nil, index: TeamMatcher.Index = Self.variantIndex) -> Set<Team.ID> {
        let teams = candidates.map { $0.compactMap { index.byID[$0] } } ?? index.teams
        return Set(TeamMatcher.teams(in: programme(title, subtitle: subtitle, summary: summary), among: teams, index: index)
            .map(\.id))
    }

    @Test func schoolFormsWithTheNicknameMatchFromTheBundledCatalog() {
        let bundled = TeamMatcher.Index.bundled(.off)
        // The guide's "Louisiana-Monroe Warhawks"; the catalog's school is "UL Monroe".
        #expect(variantIDs("Louisiana-Monroe Warhawks at Troy Trojans", index: bundled)
                == ["ncaaf.ul-monroe-warhawks", "ncaaf.troy-trojans"])
        // A hand alias with the nickname, and an apostrophe left out.
        #expect(variantIDs("Brigham Young Cougars at Hawaii Rainbow Warriors", index: bundled)
                == ["ncaaf.byu-cougars", "ncaaf.hawaii-rainbow-warriors"])
        #expect(variantIDs("Hawai'i Rainbow Warriors at UTEP", index: bundled)
                == ["ncaaf.hawaii-rainbow-warriors", "ncaaf.utep-miners"])
        #expect(variantIDs("St Johns Red Storm at Villanova", title: "College Basketball",
                           among: ["ncaam.st-johns-red-storm"], index: bundled) == ["ncaam.st-johns-red-storm"])
        // A school alias with the nickname.
        #expect(variantIDs("Appalachian State Mountaineers at Nowhere") == ["ncaaf.app-state-mountaineers"])
    }

    @Test func aKeyTeamsShareMatchesEachOfThem() {
        #expect(variantIDs("MER at Nowhere", title: "College Baseball") == ["ncaabase.mercer-bears", "ncaabase.mercyhurst-lakers"])
        #expect(variantIDs("MER at Nowhere", title: "College Baseball", among: ["ncaabase.mercyhurst-lakers"])
                == ["ncaabase.mercyhurst-lakers"])
        // The bundled catalog's only shared key, an abbreviation (L29: with Match Initials).
        #expect(variantIDs("MER at Nowhere", title: "College Baseball", index: .bundled(Self.initials))
                == ["ncaabase.mercer-bears", "ncaabase.mercyhurst-lakers"])
        #expect(variantIDs("MER at Nowhere", title: "College Baseball", index: .bundled(.off)).isEmpty)
    }

    // MARK: The options (M7m L29)

    @Test func withBothOptionsOffInitialsAndNicknamesAloneMatchNothing() throws {
        let bundled = TeamMatcher.Index.bundled(.off)
        #expect(bundled.options == .off)
        #expect(TeamMatchOptions() == .off)
        let ulm = try #require(bundled.byID["ncaaf.ul-monroe-warhawks"])
        #expect(ulm.abbreviations == ["ULM"])
        #expect(!ulm.aliases.contains("ULM"))
        #expect(variantIDs("ULM Warhawks at Troy", among: ["ncaaf.ul-monroe-warhawks"], index: bundled).isEmpty)
        #expect(variantIDs("ULM at Troy", among: ["ncaaf.ul-monroe-warhawks"], index: bundled).isEmpty)
        // Spelled-out forms, and ESPN's short names that are initials, always match.
        #expect(variantIDs("Louisiana-Monroe Warhawks at Troy", among: ["ncaaf.ul-monroe-warhawks"], index: bundled)
                == ["ncaaf.ul-monroe-warhawks"])
        #expect(variantIDs("LSU at Alabama", index: bundled) == ["ncaaf.lsu-tigers", "ncaaf.alabama-crimson-tide"])
        #expect(variantIDs("BYU Cougars at Utah", among: ["ncaaf.byu-cougars"], index: bundled) == ["ncaaf.byu-cougars"])
        // A nickname alone: nothing, from the fixture's index and the bundled one.
        let big12 = "The Cougars meet the Bearcats in Big 12 play."
        #expect(variantIDs(summary: big12).isEmpty)
        #expect(variantIDs(summary: big12, index: bundled).isEmpty)
        #expect(variantIDs("Springfield Cougars at Nowhere").isEmpty)
        #expect(bundled.collegeNicknames.isEmpty && bundled.collegeSchoolWords.isEmpty && bundled.collegeConferences.isEmpty)
        // "NE @ BUF" is no game entry.
        let channels = ChannelList.make(from: try M3UParser.parse(Self.variantGames))
        let shorthand = try #require(channels.first { $0.id == "id:shorthand" })
        #expect(!TeamMatcher.isGameEntry(shorthand))
        #expect(TeamMatcher.gameChannelIDs(channels: channels, picked: ["ncaaf.buffalo-bulls"]).isEmpty)
    }

    @Test func matchInitialsAddsTheAbbreviations() throws {
        let bundled = TeamMatcher.Index.bundled(Self.initials)
        #expect(bundled.options == Self.initials)
        #expect(variantIDs("ULM Warhawks at Troy", among: ["ncaaf.ul-monroe-warhawks"], index: bundled)
                == ["ncaaf.ul-monroe-warhawks"])
        #expect(variantIDs("ULM at Troy", among: ["ncaaf.ul-monroe-warhawks"], index: bundled)
                == ["ncaaf.ul-monroe-warhawks"])
        // A hand initial too.
        #expect(variantIDs("UTRGV Vaqueros at Nowhere", title: "College Basketball",
                           among: ["ncaam.ut-rio-grande-valley-vaqueros"], index: bundled)
                == ["ncaam.ut-rio-grande-valley-vaqueros"])
        // Not the nickname fallback.
        #expect(variantIDs(summary: "The Cougars meet the Bearcats in Big 12 play.", index: bundled).isEmpty)
        // "NE @ BUF" counts for Buffalo (BUF is also the Bills' and Sabres' shorthand: accepted, L29's description).
        let channels = ChannelList.make(from: try M3UParser.parse(Self.variantGames))
        let shorthand = try #require(channels.first { $0.id == "id:shorthand" })
        #expect(TeamMatcher.isGameEntry(shorthand, index: bundled))
        #expect(TeamMatcher.gameChannelIDs(channels: channels, picked: ["ncaaf.buffalo-bulls"], index: bundled)
                == ["id:shorthand"])
        // A built index: an abbreviation alone and with the nickname.
        let built = TeamMatcher.Index(teams: [
            Self.college(.ncaaf, "ul-monroe-warhawks", "UL Monroe Warhawks", school: "UL Monroe", nickname: "Warhawks",
                         aliases: ["UL Monroe", "Louisiana-Monroe"], abbreviations: ["ULM"]),
        ], options: Self.initials)
        #expect(built.collegeNames[.ncaaf]?[" ulm warhawks "]?.map(\.id) == ["ncaaf.ul-monroe-warhawks"])
        #expect(built.collegeSchools[" ulm "] == [" ul monroe "])
        let plain = TeamMatcher.Index(teams: built.teams)
        #expect(plain.collegeNames[.ncaaf]?[" ulm warhawks "] == nil)
        #expect(plain.collegeSchools[" ulm "] == nil)
    }

    @Test func eachCombinationOfTheOptionsHasItsIndex() {
        for initials in [false, true] {
            for nicknames in [false, true] {
                let options = TeamMatchOptions(initials: initials, nicknames: nicknames)
                #expect(TeamMatcher.Index.bundled(options).options == options)
                #expect(TeamMatcher.Index.bundled(options).teams.count == TeamCatalog.teams.count)
            }
        }
        // Both on: the abbreviations and the fallback.
        let both = TeamMatcher.Index.bundled(.init(initials: true, nicknames: true))
        #expect(variantIDs("ULM Warhawks at Troy", among: ["ncaaf.ul-monroe-warhawks"], index: both)
                == ["ncaaf.ul-monroe-warhawks"])
        #expect(variantIDs(summary: "The Rainbow Warriors (2-6, 1-4) visit the Miners (1-7, 0-4) for a Mountain West affair.",
                           index: both) == ["ncaaf.hawaii-rainbow-warriors", "ncaaf.utep-miners"])
    }

    // MARK: The nickname fallback (L28), with Match Nicknames Alone (L29)

    @Test func aNicknameAloneFallsBackToItsTeams() {
        func variantIDs(_ subtitle: String? = nil, summary: String? = nil, title: String = "College Football",
                        among candidates: [String]? = nil) -> Set<Team.ID> {
            self.variantIDs(subtitle, summary: summary, title: title, among: candidates, index: Self.nicknameIndex)
        }
        // The guide's own text (2026-11-10): one team each.
        #expect(variantIDs(summary: "The Rainbow Warriors (2-6, 1-4) visit the Miners (1-7, 0-4) for a Mountain West affair.")
                == ["ncaaf.hawaii-rainbow-warriors", "ncaaf.utep-miners"])
        // The conference narrows the Cougars: not Washington State (Pac-12) or Seattle.
        let big12 = "The Cougars meet the Bearcats in Big 12 play."
        #expect(variantIDs(summary: big12) == ["ncaaf.houston-cougars", "ncaaf.byu-cougars", "ncaaf.cincinnati-bearcats"])
        // Narrowed among every Cougars team, not just the picked ones.
        #expect(variantIDs(summary: big12, among: ["ncaaf.washington-state-cougars"]).isEmpty)
        // No conference named: every Cougars team.
        #expect(variantIDs(summary: "The Cougars meet the Bearcats.")
                == ["ncaaf.houston-cougars", "ncaaf.byu-cougars", "ncaaf.washington-state-cougars",
                    "ncaaf.seattle-cougars", "ncaaf.cincinnati-bearcats"])
        // A "(FCS)" label isn't in the guide's text: "Southland play" names the Southland (FCS).
        #expect(variantIDs(summary: "The Huskies host the Miners in Southland play.")
                == ["ncaaf.houston-christian-huskies", "ncaaf.utep-miners"])
        // A word before the nickname that no school has, and no conference: every Cougars team.
        #expect(variantIDs("Springfield Cougars at Nowhere")
                == ["ncaaf.houston-cougars", "ncaaf.byu-cougars", "ncaaf.washington-state-cougars", "ncaaf.seattle-cougars"])
        #expect(variantIDs("Springfield Cougars at Nowhere", among: ["ncaaf.houston-cougars"]) == ["ncaaf.houston-cougars"])
        // A school word narrows ("washington", not "state"); before a conference.
        #expect(variantIDs(summary: "The Washington Cougars meet the Bearcats in Big 12 play.")
                == ["ncaaf.washington-state-cougars", "ncaaf.cincinnati-bearcats"])
        #expect(variantIDs(summary: "The State Cougars meet the Bearcats.")
                == ["ncaaf.houston-cougars", "ncaaf.byu-cougars", "ncaaf.washington-state-cougars",
                    "ncaaf.seattle-cougars", "ncaaf.cincinnati-bearcats"])
        // No nickname at the end: nothing.
        #expect(variantIDs("Springfield at Nowhere").isEmpty)
        #expect(variantIDs("Cougars Fans at Nowhere").isEmpty)
        // A pro programme never falls back.
        #expect(variantIDs("Cougars at Bearcats", title: "NFL Football").isEmpty)
    }

    @Test func anExactKeyWinsOverTheNickname() {
        func variantIDs(_ subtitle: String? = nil, summary: String? = nil, among candidates: [String]? = nil) -> Set<Team.ID> {
            self.variantIDs(subtitle, summary: summary, among: candidates, index: Self.nicknameIndex)
        }
        // Houston Christian's own name: not Houston Cougars (another nickname), nor the other Huskies.
        #expect(variantIDs("Houston Christian Huskies at Nowhere") == ["ncaaf.houston-christian-huskies"])
        #expect(variantIDs("Houston Christian Huskies at Nowhere", among: ["ncaaf.houston-cougars"]).isEmpty)
        // A side that matches exactly never falls back, even when its team isn't a candidate.
        #expect(variantIDs("Houston Christian Huskies at Nowhere", among: ["ncaaf.washington-huskies", "ncaaf.uconn-huskies"])
                .isEmpty)
        #expect(variantIDs(summary: "The Houston Cougars meet the West Virginia Mountaineers in Big 12 play.")
                == ["ncaaf.houston-cougars", "ncaaf.west-virginia-mountaineers"])
    }

    /// QA's note for 11e: school words come from the school and multi-word aliases, never one-word ones.
    @Test func onlyMultiWordAliasesNarrow() {
        func hawks(_ aliases: [String]) -> TeamMatcher.Index {
            TeamMatcher.Index(teams: [
                Self.college(.ncaaf, "monmouth-hawks", "Monmouth Hawks", school: "Monmouth", nickname: "Hawks",
                             aliases: ["Monmouth"]),
                Self.college(.ncaaf, "hartford-hawks", "Hartford Hawks", school: "Hartford", nickname: "Hawks",
                             aliases: ["Hartford"] + aliases),
            ], options: Self.nicknames)
        }
        // "Long Hawks" is itself a key with the alias "Long" (L27), so the side is "Long Beach Hawks".
        let oneWord = hawks(["Long"])
        #expect(variantIDs("Long Beach Hawks at Nowhere", index: oneWord) == ["ncaaf.monmouth-hawks", "ncaaf.hartford-hawks"])
        #expect(variantIDs("Long Hawks at Nowhere", index: oneWord) == ["ncaaf.hartford-hawks"])
        let multiWord = hawks(["Long Island"])
        #expect(variantIDs("Long Beach Hawks at Nowhere", index: multiWord) == ["ncaaf.hartford-hawks"])
        #expect(variantIDs("Long Hawks at Nowhere", index: multiWord) == ["ncaaf.hartford-hawks"])
        // The words themselves: 3 letters or more, no "state", with and without apostrophes.
        let bundled = TeamMatcher.Index.bundled(Self.nicknames)
        #expect(bundled.collegeSchoolWords["ncaaf.ul-monroe-warhawks"] == ["monroe", "louisiana"])
        #expect(bundled.collegeSchoolWords["ncaaf.washington-state-cougars"] == ["washington"])
        #expect(bundled.collegeSchoolWords["ncaaf.hawaii-rainbow-warriors"] == ["hawai", "hawaii"])
        #expect(bundled.collegeConferences["ncaaf.ul-monroe-warhawks"] == [" sun belt "])
    }

    /// M7m L30: Owls in conferences named by ordinary words, the long forms and the initials.
    @Test func conferencesAreNamedByTheirPhrases() {
        let conferences = ["Southern (FCS)", "American", "Mid-American", "Northeast (FCS)", "West Coast", "Big Ten",
                           "Conference USA", "FBS Independents", "Missouri Valley Football (FCS)",
                           "Pioneer Football League (FCS)", "UAC (FCS)", "CAA"]
        let index = TeamMatcher.Index(teams: conferences.enumerated().map { n, conference in
            Self.college(.ncaaf, "owls-\(n)", "Owls \(n) Owls", school: "Owls \(n)", nickname: "Owls", conference: conference)
        }, options: Self.nicknames)
        /// The conferences of the Owls teams a summary narrows to (every one when it names none).
        func named(_ summary: String) -> [String] {
            let found = TeamMatcher.teams(in: programme("College Football", summary: "The Owls host the Nowhere Pumas \(summary)"),
                                          index: index)
            return found.count == conferences.count ? [] : found.compactMap(\.conference)
        }
        #expect(named("in Southern Conference play.") == ["Southern (FCS)"])
        #expect(named("in a SoCon game.") == ["Southern (FCS)"])
        #expect(named("in American Athletic play.") == ["American"])
        #expect(named("for an AAC game.") == ["American"])
        #expect(named("for a MAC game.") == ["Mid-American"])
        #expect(named("in Mid-American play.") == ["Mid-American"])
        #expect(named("in an NEC game.") == ["Northeast (FCS)"])
        #expect(named("in West Coast Conference play.") == ["West Coast"])
        #expect(named("in B1G play.") == ["Big Ten"])
        #expect(named("in C-USA play.") == ["Conference USA"])
        #expect(named("in MVFC play.") == ["Missouri Valley Football (FCS)"])
        #expect(named("in Missouri Valley Football Conference play.") == ["Missouri Valley Football (FCS)"])
        #expect(named("in Pioneer League play.") == ["Pioneer Football League (FCS)"])
        #expect(named("in United Athletic Conference play.") == ["UAC (FCS)"])
        #expect(named("in a UAC game.") == ["UAC (FCS)"])
        #expect(named("in Coastal Athletic Association play.") == ["CAA"])
        #expect(named("in CAA play.") == ["CAA"])
        // Ordinary words name nothing.
        #expect(named("with an All-American guard.").isEmpty)
        #expect(named("after beating Southern Miss.").isEmpty)
        #expect(named("in the Northeast.").isEmpty)
        #expect(named("on the West Coast.").isEmpty)
        #expect(named("as FBS Independents.").isEmpty)
        // Two conferences named: both.
        #expect(named("in a MAC and AAC doubleheader.") == ["American", "Mid-American"])
        #expect(TeamMatcher.Index.phrases(naming: "Big Sky (FCS)") == [" big sky "])
        #expect(TeamMatcher.Index.phrases(naming: "FCS Independents").isEmpty)
        #expect(TeamMatcher.Index.phrases(naming: "Southern (FCS)") == [" southern conference ", " socon "])
    }

    /// L30: only the summary's first `summaryLeadLength` UTF-16 units are read for a conference.
    @Test func theConferenceIsReadFromTheSummarysLead() {
        let lead = "The Cougars meet the Bearcats."
        let late = lead + String(repeating: " x", count: TeamMatcher.summaryLeadLength) + " in Big 12 play."
        #expect(TeamMatcher.conferenceSearchText(of: programme("College Football", summary: late)).contains(" big 12 ") == false)
        #expect(variantIDs(summary: late, index: Self.nicknameIndex)
                == ["ncaaf.houston-cougars", "ncaaf.byu-cougars", "ncaaf.washington-state-cougars",
                    "ncaaf.seattle-cougars", "ncaaf.cincinnati-bearcats"])
        // The title and subtitle are read whole.
        #expect(variantIDs(summary: late, title: "College Football: Big 12 Showdown", index: Self.nicknameIndex)
                == ["ncaaf.houston-cougars", "ncaaf.byu-cougars", "ncaaf.cincinnati-bearcats"])
    }

    // MARK: Teams by side (M7m L31)

    @Test func teamsBySideKeepsEachSidesTeams() throws {
        let index = Self.nicknameIndex
        func sides(_ programme: Programme, among candidates: [String]? = nil) -> [[Team.ID]] {
            let teams = candidates.map { $0.compactMap { index.byID[$0] } } ?? index.teams
            return TeamMatcher.teamsBySide(in: programme, among: teams, index: index).map { $0.map(\.id) }
        }
        // A side that expands to several teams doesn't push the other side's team out.
        let cougars = programme("College Football", summary: "The Cougars meet the Bearcats.")
        #expect(sides(cougars) == [["ncaaf.houston-cougars", "ncaaf.byu-cougars", "ncaaf.washington-state-cougars",
                                    "ncaaf.seattle-cougars"], ["ncaaf.cincinnati-bearcats"]])
        #expect(TeamMatcher.teams(in: cougars, index: index).map(\.id)
                == ["ncaaf.houston-cougars", "ncaaf.byu-cougars", "ncaaf.washington-state-cougars",
                    "ncaaf.seattle-cougars", "ncaaf.cincinnati-bearcats"])
        // Only the candidates; a side with none is left out.
        #expect(sides(cougars, among: ["ncaaf.cincinnati-bearcats"]) == [["ncaaf.cincinnati-bearcats"]])
        // A team is in one side only: of two exact sides, the first.
        #expect(sides(programme("College Football", subtitle: "Houston at Houston Cougars")) == [["ncaaf.houston-cougars"]])
        // QA (11f): an exact side claims its team before an earlier nickname-only side.
        #expect(sides(programme("College Football", subtitle: "Cougars at Houston Cougars"))
                == [["ncaaf.byu-cougars", "ncaaf.washington-state-cougars", "ncaaf.seattle-cougars"],
                    ["ncaaf.houston-cougars"]])
        #expect(TeamMatcher.teams(in: programme("College Football", subtitle: "Cougars at Houston Cougars"), index: index)
                .map(\.id) == ["ncaaf.byu-cougars", "ncaaf.washington-state-cougars", "ncaaf.seattle-cougars",
                              "ncaaf.houston-cougars"])
        // Exact sides, in the programme's order.
        #expect(sides(programme("College Football", subtitle: "Cincinnati at BYU"))
                == [["ncaaf.cincinnati-bearcats"], ["ncaaf.byu-cougars"]])
        // Pro: one team per side.
        #expect(sides(programme("NBA Basketball", subtitle: "Miami Heat at Los Angeles Lakers"))
                == [["nba.lal"], ["nba.mia"]])
        #expect(sides(programme("Movie")).isEmpty)
        // Without the option, a nickname-only side is no side.
        #expect(TeamMatcher.teamsBySide(in: cougars, index: Self.variantIndex).isEmpty)
    }

    /// QA (11f): with the bundled catalog, LSU stays its own side, so the channel menu can offer it.
    @Test func anExactSideKeepsItsTeamFromAnEarlierFallbackSide() throws {
        let index = TeamMatcher.Index.bundled(Self.nicknames)
        let game = programme("College Football", summary: "The Tigers host the LSU Tigers.")
        let sides = TeamMatcher.teamsBySide(in: game, index: index).map { $0.map(\.id) }
        #expect(sides.count == 2)
        #expect(sides.last == ["ncaaf.lsu-tigers"])
        let tigers = try #require(sides.first)
        #expect(!tigers.isEmpty)
        #expect(!tigers.contains("ncaaf.lsu-tigers"))
        // Flattened: each team once, in the programme's order.
        let flat = TeamMatcher.teams(in: game, index: index).map(\.id)
        #expect(flat == tigers + ["ncaaf.lsu-tigers"])
    }

    /// QA (11f): titles, subtitles and categories are read to `headingReadLength`, so a huge one is cheap.
    @Test func aHugeTitleOrSubtitleIsCheap() {
        let filler = String(repeating: " x", count: 500_000)   // 1 MB
        let cases: [(Programme, Set<Team.ID>)] = [
            (programme("NBA Basketball: Miami Heat at Los Angeles Lakers" + filler), ["nba.mia", "nba.lal"]),
            (programme("NBA Basketball", subtitle: "Miami Heat at Los Angeles Lakers" + filler), ["nba.mia", "nba.lal"]),
            (programme("NBA Basketball", subtitle: "Miami Heat at Los Angeles Lakers", category: "Sports" + filler),
             ["nba.mia", "nba.lal"]),
            (programme("College Football" + filler, summary: "The Cougars meet the Bearcats in Big 12 play."),
             ["ncaaf.houston-cougars", "ncaaf.byu-cougars", "ncaaf.cincinnati-bearcats"]),
            // Cut, the second side runs into the filler and names no one; the first still matches.
            (programme("College Football", subtitle: "Cincinnati Bearcats at BYU Cougars" + filler),
             ["ncaaf.cincinnati-bearcats"]),
        ]
        for (n, (game, expected)) in cases.enumerated() {
            let start = Date()
            #expect(Set(TeamMatcher.teams(in: game, index: Self.nicknameIndex).map(\.id)) == expected, "\(n)")
            _ = TeamMatcher.isLiveGame(game)
            _ = TeamMatcher.conferenceSearchText(of: game)
            #expect(Date().timeIntervalSince(start) < 0.05, "\(n)")
        }
        #expect(TeamMatcher.bounded(cases[0].0).title.utf16.count <= TeamMatcher.headingReadLength)
        // A combining-mark flood is cut without splitting a character.
        let marks = programme("NBA Basketball: Miami Heat at Los Angeles Lakers x" + String(repeating: "\u{301}", count: 1_000_000))
        let start = Date()
        #expect(Set(TeamMatcher.teams(in: marks, index: Self.nicknameIndex).map(\.id)) == ["nba.mia", "nba.lal"])
        #expect(Date().timeIntervalSince(start) < 0.05)
    }

    /// The security review for build 34 (L1): a game entry's name is read to `headingReadLength`.
    @Test func aHugeGameEntryNameIsCheap() throws {
        let name = "Los Angeles Lakers @ Miami Heat" + String(repeating: " x", count: 50_000)   // 100 KB
        let channel = Channel(id: "id:huge", number: 1, name: name, group: "NBA", tvgID: nil, tvgName: nil, logoURL: nil,
                              streamURL: URL(string: "https://cdn.example/huge.m3u8")!)
        let start = Date()
        let game = try #require(TeamMatcher.gameEntry(channel))
        #expect(game.away == "Los Angeles Lakers")
        #expect(game.home.utf16.count < TeamMatcher.headingReadLength)
        #expect(TeamMatcher.isGameEntry(channel))
        #expect(TeamMatcher.gameChannelIDs(channels: [channel], picked: ["nba.lal"]) == ["id:huge"])
        #expect(Date().timeIntervalSince(start) < 0.005)
    }

    static let variantGames = """
    #EXTM3U
    #EXTINF:0 tvg-id="ULM" group-title="Live-Games",Louisiana-Monroe Warhawks @ Troy Trojans
    \(url(31))
    #EXTINF:0 tvg-id="Nicknames" group-title="Live-Games",Warhawks @ Trojans
    \(url(32))
    #EXTINF:0 tvg-id="Shorthand" group-title="Live-Games",NE @ BUF
    \(url(33))
    #EXTINF:0 tvg-id="Shared" group-title="Live-Games",MER @ Nowhere
    \(url(34))
    """

    @Test func gameEntriesUseEveryKeyButNoNicknameFallback() throws {
        let channels = ChannelList.make(from: try M3UParser.parse(Self.variantGames))
        let both = TeamMatcher.Index.bundled(.init(initials: true, nicknames: true))
        func games(_ picked: Set<Team.ID>, index: TeamMatcher.Index = .bundled(.off)) -> [Channel.ID] {
            TeamMatcher.gameChannelIDs(channels: channels, picked: picked, index: index)
        }
        // The combined key; never the nicknames alone (entries are written with full names), whatever the options.
        #expect(games(["ncaaf.ul-monroe-warhawks"]) == ["id:ulm"])
        #expect(games(["ncaaf.troy-trojans"]) == ["id:ulm"])
        let nicknames = try #require(channels.first { $0.id == "id:nicknames" })
        #expect(!TeamMatcher.isGameEntry(nicknames))
        #expect(!TeamMatcher.isGameEntry(nicknames, index: both))
        // ESPN abbreviations are keys with Match Initials, pro shorthand or not (accepted, QA's note for 11e).
        #expect(games(["ncaaf.buffalo-bulls"]).isEmpty)
        #expect(games(["ncaaf.buffalo-bulls"], index: both) == ["id:shorthand"])
        // A key two schools share counts for each (MER is an abbreviation of both).
        #expect(games(["ncaabase.mercer-bears"], index: both) == ["id:shared"])
        #expect(games(["ncaabase.mercyhurst-lakers"], index: both) == ["id:shared"])
        #expect(games(["ncaabase.mercer-bears"]).isEmpty)
    }

    /// L25's bounds hold with the fallback: a huge summary is cut before the conference is looked for.
    @Test func theFallbackStaysCheapOnAHugeSummary() {
        func variantIDs(_ subtitle: String? = nil, summary: String) -> Set<Team.ID> {
            self.variantIDs(subtitle, summary: summary, index: Self.nicknameIndex)
        }
        let summary = "The Cougars meet the Bearcats " + String(repeating: "in Big 12 play ", count: 100_000)
        let start = Date()
        #expect(variantIDs(summary: summary) == ["ncaaf.houston-cougars", "ncaaf.byu-cougars", "ncaaf.cincinnati-bearcats"])
        #expect(variantIDs("Springfield Cougars at Nowhere Bearcats", summary: summary)
                == ["ncaaf.houston-cougars", "ncaaf.byu-cougars", "ncaaf.cincinnati-bearcats"])
        #expect(Date().timeIntervalSince(start) < 0.5)
    }
}

/// Holds the first call until `release()`; later calls pass at once. (Also `MyTeamsTests`.)
@MainActor
final class SlowFetchGate {
    private var calls = 0
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { continuation != nil }

    func wait() async {
        calls += 1
        guard calls == 1 else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

/// A seeded generator for the fuzz tests (the same strings every run).
struct SplitMix: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
