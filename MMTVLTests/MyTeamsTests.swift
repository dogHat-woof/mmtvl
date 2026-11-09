import Foundation
import Testing
@testable import MMTVL

/// M7l 8c: My Teams: always in the guide, Choose Teams as its first row, then the live games, then the upcoming ones.
struct MyTeamsTests {
    private static let now = Date(timeIntervalSince1970: 1_791_200_000)
    private static let nfl = "id:nflnetwork.us"
    private static let nba = "id:nbatv.us"
    private static let redZone = "name:red zone"

    private static func channel(_ name: String, group: String = "Live") -> Channel {
        Channel(id: "name:\(name.lowercased())", number: 1, name: name, group: group, tvgID: nil, tvgName: nil,
                logoURL: nil, streamURL: URL(string: "https://cdn.example/\(name.count).m3u8")!)
    }

    private static func programme(hours: Double, _ title: String, _ subtitle: String? = nil) -> Programme {
        let start = now + hours * 3600
        return Programme(channelID: "x", start: start, stop: start + 3 * 3600, title: title, subtitle: subtitle)
    }

    // MARK: TeamMatcher.upcomingGames

    @Test func upcomingGamesAreTheNext72HoursSoonestFirst() {
        let espn = Self.channel("ESPN")
        let fox = Self.channel("FOX")
        let game = Self.channel("Miami Heat @ Los Angeles Lakers", group: "NBA")
        let lakersCeltics = Self.programme(hours: 5, "NBA Basketball", "Los Angeles Lakers at Boston Celtics")
        let programmes: [Channel.ID: [Programme]] = [
            espn.id: [
                Self.programme(hours: -1, "NBA Basketball", "Miami Heat at Los Angeles Lakers"),   // on now: live, not upcoming
                lakersCeltics,
                Self.programme(hours: 8, "Lakers Postgame", "Los Angeles Lakers"),                // postgame
                Self.programme(hours: 30, "NBA Basketball", "Boston Celtics at New York Knicks"),  // not picked
                Self.programme(hours: 73, "NBA Basketball", "Los Angeles Lakers at Denver Nuggets"),  // past 72 h
            ],
            fox.id: [
                Self.programme(hours: 2, "NBA Replay", "Los Angeles Lakers at Utah Jazz"),        // replay
                lakersCeltics,                                                                     // the same game: its own row
                Self.programme(hours: 48, "NBA Basketball", "Golden State Warriors at Los Angeles Lakers"),
            ],
            game.id: [Self.programme(hours: 1, "NBA Basketball", "Miami Heat at Los Angeles Lakers")],  // a game entry
        ]
        let games = TeamMatcher.upcomingGames(channels: [espn, fox, game], programmes: programmes, picked: ["nba.lal"],
                                              now: Self.now)
        #expect(games.map(\.channel.name) == ["ESPN", "FOX", "FOX"])
        #expect(games.map(\.label) == ["Los Angeles Lakers at Boston Celtics", "Los Angeles Lakers at Boston Celtics",
                                       "Golden State Warriors at Los Angeles Lakers"])
        #expect(games.allSatisfy { $0.programme.start > Self.now && $0.programme.start < Self.now + 72 * 3600 })
        #expect(TeamMatcher.upcomingGames(channels: [espn, fox], programmes: programmes, picked: [], now: Self.now).isEmpty)
    }

    @Test func aGameWithoutSubtitleIsLabelledByItsTitle() {
        let game = UpcomingTeamGame(channel: Self.channel("ESPN"), programme: Self.programme(hours: 1, "Lakers vs. Celtics"))
        #expect(game.label == "Lakers vs. Celtics")
        #expect(!game.dayTime.isEmpty)
    }

    // MARK: Names

    @Test func theListIsCalledMyTeams() {
        #expect(ChannelLineup.teamsGroup == "My Teams")
        #expect(TeamPicker.pickedValue == "In My Teams")   // the picker's and search's team values
        #expect(LiveSearchView.teamHint(isPicked: false) == "Select: add to My Teams · Left: keyboard")
        #expect(LiveSearchView.teamHint(isPicked: true) == "Select: remove from My Teams · Left: keyboard")
        #expect(TeamPicker.title == "Choose Teams")
    }

    // MARK: Lineup

    @Test func myTeamsIsAlwaysAfterFavoritesAndUpcomingRowsStayOutOfFavorites() throws {
        let channels = ChannelList.make(from: try M3UParser.parse(IPTVFixtures.playlist))
        let none = ChannelLineup(channels: channels)
        #expect(none.groups == ["My Teams", "All Channels", "Live Channels", "NBA Games"])
        #expect(none.channels(in: "My Teams").isEmpty)
        let nfl = try #require(channels.first { $0.id == Self.nfl })
        let upcoming = [UpcomingTeamGame(channel: nfl, programme: Self.programme(hours: 3, "NFL Football", "A at B"))]
        let lineup = ChannelLineup(channels: channels, preferences: ChannelPreferences(favorites: [Self.redZone]),
                                   teamChannelIDs: [Self.nba], upcomingTeamGames: upcoming)
        #expect(Array(lineup.groups.prefix(3)) == ["Favorites", "My Teams", "All Channels"])
        // Favorites and zapping (`channels(in:)`) take only the live games.
        #expect(lineup.channels(in: "Favorites").map(\.id) == [Self.nba, Self.redZone])
        #expect(lineup.channels(in: "My Teams").map(\.id) == [Self.nba])
        #expect(lineup.upcomingTeamGames == upcoming)
        // A hidden channel's upcoming game doesn't show; the cap holds.
        let hidden = ChannelLineup(channels: channels, preferences: ChannelPreferences(hiddenChannels: [Self.nfl]),
                                   upcomingTeamGames: upcoming)
        #expect(hidden.upcomingTeamGames.isEmpty)
        let many = Array(repeating: upcoming[0], count: 40)
        #expect(ChannelLineup(channels: channels, upcomingTeamGames: many).upcomingTeamGames.count
                == ChannelLineup.maxUpcomingTeamGames)
        // No visible channel: no groups at all.
        #expect(ChannelLineup(channels: []).groups.isEmpty)
    }

    // MARK: Library and Live TV

    /// NBA TV: the Lakers on now, then at +2 h; NFL Network: a Lakers replay at +1 h, a Lakers game at +5 h and a
    /// Knicks game at +1 h; the Lakers again on NBA TV past 72 h.
    private static func guide() -> String {
        func entry(_ channel: String, hours: Double, _ title: String, _ subtitle: String) -> String {
            let start = now + hours * 3600
            return "<programme start=\"\(IPTVFixtures.stamp(start))\" stop=\"\(IPTVFixtures.stamp(start + 3600))\" "
                + "channel=\"\(channel)\"><title>\(title)</title><sub-title>\(subtitle)</sub-title></programme>\n"
        }
        return """
        <?xml version="1.0"?>
        <tv>
        <channel id="NFL.Network.HD.us2"><display-name>NFL Network HD</display-name></channel>
        <channel id="nbatv.us"><display-name>NBA TV</display-name></channel>
        """
            + entry("nbatv.us", hours: -0.5, "NBA Basketball", "Miami Heat at Los Angeles Lakers")
            + entry("nbatv.us", hours: 2, "NBA Basketball", "Los Angeles Lakers at Boston Celtics")
            + entry("nbatv.us", hours: 80, "NBA Basketball", "Los Angeles Lakers at Denver Nuggets")
            + entry("NFL.Network.HD.us2", hours: 1, "NBA Replay", "Los Angeles Lakers at Utah Jazz")
            + entry("NFL.Network.HD.us2", hours: 1.5, "NBA Basketball", "Boston Celtics at New York Knicks")
            + entry("NFL.Network.HD.us2", hours: 5, "NBA Basketball", "Golden State Warriors at Los Angeles Lakers")
            + "</tv>\n"
    }

    private func makeFixture(preferences: ChannelPreferences? = nil, state: IPTVState? = nil) async throws -> LibraryFixture {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL],
                                      files: [IPTVFixtures.customGuideURL: Self.guide()], state: state,
                                      preferences: preferences, now: Self.now)
        await fixture.library.refreshAll()
        return fixture
    }

    @Test func pickingATeamListsItsUpcomingGames() async throws {
        let fixture = try await makeFixture(preferences: ChannelPreferences(favorites: [Self.redZone]))
        defer { fixture.cleanUp() }
        let library = fixture.library
        #expect(library.lineup.upcomingTeamGames.isEmpty)
        library.setTeamPicked("nba.lal", true)
        await library.teamUpdateTask?.value
        #expect(library.lineup.channels(in: "My Teams").map(\.id) == [Self.nba])
        #expect(library.lineup.upcomingTeamGames.map(\.channel.id) == [Self.nba, Self.nfl])
        #expect(library.lineup.upcomingTeamGames.map(\.label)
                == ["Los Angeles Lakers at Boston Celtics", "Golden State Warriors at Los Angeles Lakers"])
        // Favorites: the live game, then the saved favorites; never the upcoming games. The saved list is unchanged.
        #expect(library.lineup.channels(in: "Favorites").map(\.id) == [Self.nba, Self.redZone])
        #expect(fixture.preferencesFile.load().favorites == [Self.redZone])
        // Unpicked: no upcoming games, My Teams stays.
        library.setTeamPicked("nba.lal", false)
        await library.teamUpdateTask?.value
        #expect(library.lineup.upcomingTeamGames.isEmpty)
        #expect(library.lineup.groups.contains("My Teams"))
    }

    /// QA (8c): an update cancelled during its store read (the read gives nothing) keeps the network channels and
    /// upcoming games it had; game entries need no read.
    @Test func anUpdateCancelledDuringItsReadKeepsTheNetworkAndUpcomingGames() async throws {
        let fixture = try await makeFixture(preferences: ChannelPreferences(teams: ["nba.lal"]))
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.updateTeams()
        let live = library.lineup.channels(in: "My Teams").map(\.id)
        let upcoming = library.lineup.upcomingTeamGames
        #expect(live == [Self.nba])
        #expect(upcoming.count == 2)

        let gate = SlowFetchGate()
        library.beforeTeamProgrammesFetch = { await gate.wait() }
        let update = Task { await library.updateTeams() }
        for _ in 0..<1000 where !gate.isWaiting { await Task.yield() }
        #expect(gate.isWaiting)
        update.cancel()
        gate.release()
        await update.value
        #expect(library.lineup.channels(in: "My Teams").map(\.id) == live)
        #expect(library.lineup.upcomingTeamGames == upcoming)
    }

    @Test func selectOnAnUpcomingGameTunesItsChannel() async throws {
        let fixture = try await makeFixture(preferences: ChannelPreferences(teams: ["nba.lal"]),
                                            state: IPTVState(lastChannelID: Self.redZone))
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.updateTeams()
        let player = FakePlayer()
        let model = LiveTVModel(player: player, makePlayer: { FakePlayer() }, library: library, now: { fixture.clock.now })
        model.open()
        await model.pendingTask?.value
        player.state.phase = .playing
        if model.banner != nil || model.showsTimeshiftBar { _ = model.handle(.back) }
        _ = model.handle(.back)
        #expect(model.mode == .guide)
        // Groups → My Teams.
        _ = model.handle(.left)
        _ = model.handle(.left)
        for _ in 0..<20 where model.guide?.focus != .groups(0) { _ = model.handle(.up) }
        #expect(model.guide?.groups.prefix(2) == ["Favorites", "My Teams"])
        _ = model.handle(.down)
        _ = model.handle(.select)
        #expect(model.guide?.selectedGroup == "My Teams")
        #expect(model.guide?.rows.map(\.kind) == [.chooseTeams, .channel, .upcoming, .upcoming])
        // Menu on Choose Teams does nothing; the last row is NFL Network's game.
        _ = model.handle(.menu)
        #expect(model.menu == nil)
        for _ in 0..<3 { _ = model.handle(.down) }
        #expect(model.guide?.focusedChannel?.id == Self.nfl)
        _ = model.handle(.menu)
        #expect(model.menu == nil)
        _ = model.handle(.select)
        #expect(model.mode == .player)
        #expect(model.currentChannel?.id == Self.nfl)
        #expect(player.played.last == IPTVFixtures.streamURL(1))
        // Zapping in My Teams steps through the live games only: NFL Network isn't one, so its own group.
        #expect(library.state.lastGroup == "My Teams")
        _ = model.handle(.down)
        #expect(model.currentChannel?.id == Self.nba)
    }

    /// A `lastGroup` of "Teams" (before 8c) opens My Teams and zaps through its live games.
    @Test func aRememberedTeamsGroupOpensMyTeams() async throws {
        let fixture = try await makeFixture(preferences: ChannelPreferences(teams: ["nba.lal"]),
                                            state: IPTVState(lastChannelID: Self.nba, lastGroup: "Teams"))
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.updateTeams()
        let model = LiveTVModel(player: FakePlayer(), makePlayer: { FakePlayer() }, library: library,
                                now: { fixture.clock.now })
        model.open()
        await model.pendingTask?.value
        if model.banner != nil || model.showsTimeshiftBar { _ = model.handle(.back) }
        _ = model.handle(.back)
        #expect(model.guide?.selectedGroup == "My Teams")
        #expect(model.guide?.focusedChannel?.id == Self.nba)
    }
}
