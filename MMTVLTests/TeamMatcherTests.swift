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
                                conference: String = "Test", aliases: [String] = []) -> Team {
        Team(id: "\(league.rawValue).\(slug)", league: league, name: name, school: school, nickname: nickname,
             conference: conference, aliases: aliases)
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
