import Foundation
import Testing
@testable import MMTVL

/// M7f L12: Live TV search.
struct LiveSearchTests {
    private static let futbolURL = URL(string: "https://cdn.example/t/channel/6/chunks.m3u8")!
    private static let playlistWithFutbol = IPTVFixtures.playlist + """

    #EXTINF:0 tvg-id="futbol.us" tvg-name="Telemundo Fútbol" group-title="Live Channels",Telemundo Fútbol
    \(futbolURL)
    """

    /// The fixture playlist and guide, imported.
    private func makeFixture(texts: [URL: String] = [IPTVFixtures.playlistURL: IPTVFixtures.playlist],
                             state: IPTVState? = nil, preferences: ChannelPreferences? = nil) async throws -> LibraryFixture {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL],
                                      texts: texts, state: state, preferences: preferences)
        await fixture.library.refreshAll()
        return fixture
    }

    private func search(_ fixture: LibraryFixture, _ text: String) async -> LiveSearchModel {
        let model = LiveSearchModel(library: fixture.library, now: { fixture.clock.now }, debounce: .zero, text: text)
        await model.queryTask?.value
        return model
    }

    private func titles(_ results: [LiveSearchModel.Result]) -> [String] {
        results.map { result in
            switch result {
            case .channel(let channel): "channel \(channel.name)"
            case .programme(let channel, let programme): "\(channel.name): \(programme.title)"
            case .team(let team): "team \(team.id)"
            }
        }
    }

    // MARK: LiveSearchModel

    @Test func channelsIgnoreCaseAndDiacriticsAndSkipHiddenOnes() async throws {
        let fixture = try await makeFixture(texts: [IPTVFixtures.playlistURL: Self.playlistWithFutbol],
                                            preferences: ChannelPreferences(hiddenChannels: ["id:nbatv.us"]))
        defer { fixture.cleanUp() }
        #expect(titles(await search(fixture, "FUTBOL").channelResults) == ["channel Telemundo Fútbol"])
        #expect(titles(await search(fixture, "celtics LAKERS").channelResults) == ["channel Lakers @ Celtics"])
        // NBA TV is hidden: neither it nor its programmes are found.
        let nba = await search(fixture, "nba tv")
        #expect(nba.isSearching)
        #expect(nba.results.isEmpty)
        // One character isn't a search.
        let short = await search(fixture, "n ")
        #expect(!short.isSearching)
        #expect(short.results.isEmpty)
    }

    @Test func programmesFollowChannelsFromNowOn() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let model = await search(fixture, "nba tv")
        // The programme that ended at now isn't found; the one on now is first.
        #expect(titles(model.results) == ["channel NBA TV", "NBA TV: NBA TV 1", "NBA TV: NBA TV 2", "NBA TV: NBA TV 3"])
        guard case .programme(_, let onNow) = model.results[1], case .programme(_, let later) = model.results[2] else {
            Issue.record("Expected programmes")
            return
        }
        #expect(model.isOnNow(onNow))
        #expect(!model.isOnNow(later))
    }

    @Test func keyboardResultsAndBack() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let model = await search(fixture, "nba tv")
        // Right from the end of a key row enters the results; Left and Back return to the keyboard.
        for _ in 0..<7 { #expect(model.handle(.right) == .none) }
        #expect(model.focus == .results(0))
        #expect(model.handle(.down) == .none)
        #expect(model.focus == .results(1))
        #expect(model.handle(.back) == .none)
        #expect(model.focus == .keyboard)
        #expect(model.handle(.back) == .close)
        // Typing narrows the programmes at once.
        model.apply(TextEdit(deletions: 0, insertion: " 3"))
        #expect(titles(model.results) == ["NBA TV: NBA TV 3"])
    }

    // MARK: Teams (M7l L12)

    /// The fixture playlist with a guide whose NBA TV programme on now is a Duke game.
    private func makeDukeFixture() async throws -> LibraryFixture {
        let now = Date(timeIntervalSince1970: 1_791_200_000)
        let start = now.addingTimeInterval(-1800), stop = now.addingTimeInterval(3600)
        let guide = """
        <?xml version="1.0"?>
        <tv>
        <channel id="nbatv.us"><display-name>NBA TV</display-name></channel>
        <programme start="\(IPTVFixtures.stamp(start))" stop="\(IPTVFixtures.stamp(stop))" channel="nbatv.us"><title>Duke at North Carolina</title></programme>
        </tv>
        """
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL],
                                      files: [IPTVFixtures.customGuideURL: guide], now: now)
        await fixture.library.refreshAll()
        return fixture
    }

    @Test func teamsComeBetweenChannelsAndProgrammes() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let model = await search(fixture, "nba")
        let found = titles(model.results)
        // NBA TV, then at most `maxTeamResults` (12) NBA teams, then NBA TV's programmes.
        #expect(found.first == "channel NBA TV")
        let teams = Array(found.dropFirst().prefix(LiveSearchModel.maxTeamResults))
        #expect(teams == TeamCatalog.teams(in: .nba).prefix(LiveSearchModel.maxTeamResults).map { "team \($0.id)" })
        #expect(found.dropFirst(1 + LiveSearchModel.maxTeamResults).allSatisfy { $0.hasPrefix("NBA TV: ") })
        #expect(!model.programmeResults.isEmpty)
    }

    @Test func michiganListsCollegeTeamsAndWomenNarrowsToWomensBasketball() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let michigan = await search(fixture, "michigan")
        #expect(michigan.channelResults.isEmpty)
        #expect(michigan.teamResults.count == LiveSearchModel.maxTeamResults)
        #expect(michigan.results.allSatisfy { if case .team(let team) = $0 { team.league.isCollege } else { false } })
        let women = await search(fixture, "Michigan WOMEN")
        let teams = women.teamResults.compactMap { if case .team(let team) = $0 { team } else { nil } }
        #expect(!teams.isEmpty)
        #expect(teams.allSatisfy { $0.league == .ncaaw })
        #expect(teams.contains { $0.id == "ncaaw.michigan-wolverines" })
    }

    @Test func dukeListsDukesFourTeamsBeforeOtherDukes() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let model = await search(fixture, "duke")
        let found = titles(model.teamResults)
        // A whole word of the school or name first, in catalog order; then "Dukes" (a word that starts with it).
        #expect(Array(found.prefix(4)) == ["team ncaaf.duke-blue-devils", "team ncaam.duke-blue-devils",
                                           "team ncaaw.duke-blue-devils", "team ncaabase.duke-blue-devils"])
        #expect(found.count > 4)
        #expect(found.dropFirst(4).allSatisfy { $0.hasSuffix("-dukes") })
        // A word that only starts a word: "duk" ranks by catalog order.
        let prefix = titles(await search(fixture, "duk").teamResults)
        #expect(prefix.first == "team ncaaf.duke-blue-devils")
    }

    /// M7l (QA): words found in the league title or conference don't count for the rank.
    @Test func aSportWordDoesntSpoilTheRank() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let michigan = titles(await search(fixture, "michigan basketball").teamResults)
        // The school Michigan first (men's, then women's), then Michigan State (a whole word), then Central Michigan.
        #expect(Array(michigan.prefix(3)) == ["team ncaam.michigan-wolverines", "team ncaaw.michigan-wolverines",
                                              "team ncaam.michigan-state-spartans"])
        let state = try #require(michigan.firstIndex(of: "team ncaam.michigan-state-spartans"))
        let central = try #require(michigan.firstIndex(of: "team ncaam.central-michigan-chippewas"))
        #expect(state < central)
        let duke = titles(await search(fixture, "duke basketball").teamResults)
        #expect(Array(duke.prefix(2)) == ["team ncaam.duke-blue-devils", "team ncaaw.duke-blue-devils"])
        #expect(duke.dropFirst(2).allSatisfy { $0.hasSuffix("-dukes") })
    }

    /// The school (or an alias) exactly beats a whole word of another school.
    @Test func theExactSchoolComesFirst() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let michigan = titles(await search(fixture, "michigan").teamResults)
        #expect(Array(michigan.prefix(4)) == ["team ncaaf.michigan-wolverines", "team ncaam.michigan-wolverines",
                                              "team ncaaw.michigan-wolverines", "team ncaabase.michigan-wolverines"])
        #expect(michigan.dropFirst(4).first == "team ncaaf.michigan-state-spartans")
        let texas = titles(await search(fixture, "texas").teamResults)
        #expect(Array(texas.prefix(4)) == ["team ncaaf.texas-longhorns", "team ncaam.texas-longhorns",
                                           "team ncaaw.texas-longhorns", "team ncaabase.texas-longhorns"])
        #expect(texas.dropFirst(4).allSatisfy { !$0.hasSuffix(".texas-longhorns") })
        #expect(texas.count == LiveSearchModel.maxTeamResults)
    }

    @Test func teamResultsStopAtTwelve() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        #expect(LiveSearchModel.maxTeamResults == 12)
        let model = await search(fixture, "college basketball")
        #expect(model.teamResults.count == 12)
        // No whole-word name match: catalog order, the first men's basketball teams.
        #expect(titles(model.teamResults) == TeamCatalog.teams(in: .ncaam).prefix(12).map { "team \($0.id)" })
    }

    @Test func firstResultSkipsTeams() async throws {
        let fixture = try await makeDukeFixture()
        defer { fixture.cleanUp() }
        let model = await search(fixture, "duke")
        // Teams first (Duke's, and the Dukes of James Madison and Duquesne), then the game.
        let found = titles(model.results)
        #expect(found.dropLast().allSatisfy { $0.hasPrefix("team ") })
        #expect(found.last == "NBA TV: Duke at North Carolina")
        #expect(titles([model.firstResult].compactMap { $0 }) == ["NBA TV: Duke at North Carolina"])
        // Only teams: no first result.
        let devils = await search(fixture, "blue devils")
        #expect(!devils.results.isEmpty)
        #expect(devils.firstResult == nil)
    }

    // MARK: LiveTVModel

    /// Playing NBA TV, with the guide imported; the search runs without a debounce.
    private func makeLiveTV() async throws -> (LiveTVModel, FakePlayer, LibraryFixture) {
        let fixture = try await makeFixture(state: IPTVState(lastChannelID: "id:nbatv.us"))
        let player = FakePlayer()
        let model = LiveTVModel(player: player, makePlayer: { FakePlayer() }, library: fixture.library,
                                now: { fixture.clock.now })
        model.searchDebounce = .zero
        model.open()
        await model.pendingTask?.value
        player.state.phase = .playing
        return (model, player, fixture)
    }

    /// Types `text` from the phone and waits for the programmes.
    private func type(_ model: LiveTVModel, _ text: String) async {
        model.typeText(TextEdit(deletions: 0, insertion: text))
        await model.search?.queryTask?.value
    }

    private func enterResults(_ model: LiveTVModel, at index: Int) {
        for _ in 0..<7 { _ = model.handle(.right) }
        for _ in 0..<index { _ = model.handle(.down) }
    }

    @Test func phoneTextOpensSearchAndAChannelPlays() async throws {
        let (model, player, fixture) = try await makeLiveTV()
        defer { fixture.cleanUp() }
        #expect(model.mode == .player)
        await type(model, "nfl network")
        #expect(model.search?.keyboard.text == "nfl network")
        #expect(model.banner == nil)
        #expect(titles(model.search?.results ?? []).first == "channel NFL Network")
        enterResults(model, at: 0)
        #expect(model.handle(.select) == .handled)
        #expect(model.search == nil)
        #expect(model.mode == .player)
        #expect(player.played.last == IPTVFixtures.streamURL(1))
    }

    @Test func aProgrammeOnNowPlaysItsChannel() async throws {
        let (model, player, fixture) = try await makeLiveTV()
        defer { fixture.cleanUp() }
        await type(model, "nfl network hd 1")
        #expect(titles(model.search?.results ?? []) == ["NFL Network: NFL Network HD 1"])
        model.submitText()   // the phone's Return: the first result
        #expect(model.search == nil)
        #expect(model.mode == .player)
        #expect(player.played.last == IPTVFixtures.streamURL(1))
    }

    @Test func aLaterProgrammeShowsInTheGuide() async throws {
        let (model, player, fixture) = try await makeLiveTV()
        defer { fixture.cleanUp() }
        let playedBefore = player.played
        await type(model, "nfl network hd 2")
        guard case .programme(_, let later)? = model.search?.results.first else {
            Issue.record("No programme found")
            return
        }
        enterResults(model, at: 0)
        _ = model.handle(.select)
        await model.pendingTask?.value
        #expect(model.search == nil)
        #expect(model.mode == .guide)
        #expect(model.guide?.focusedChannel?.id == "id:nflnetwork.us")
        #expect(model.guide?.focusTime == later.start)
        #expect(model.guide?.focusedCell(now: fixture.clock.now)?.programme?.title == "NFL Network HD 2")
        #expect(player.played == playedBefore)
    }

    @Test func theGuideSearchRowOpensSearchAndBackReturns() async throws {
        let (model, _, fixture) = try await makeLiveTV()
        defer { fixture.cleanUp() }
        _ = model.handle(.select)   // M7c L11: the banner…
        _ = model.handle(.back)     // …hidden
        _ = model.handle(.back)     // the guide
        #expect(model.mode == .guide)
        let group = model.guide?.selectedGroup
        let row = model.guide?.row
        _ = model.handle(.left)     // the channel cell
        _ = model.handle(.left)     // groups
        for _ in 0..<10 { _ = model.handle(.up) }
        #expect(model.guide?.focus == .search)
        _ = model.handle(.select)
        #expect(model.search != nil)
        // Home still leaves while search is open; Back on the keyboard closes it.
        #expect(model.handle(.back) == .handled)
        #expect(model.search == nil)
        #expect(model.mode == .guide)
        #expect(model.guide?.selectedGroup == group)
        #expect(model.guide?.row == row)
        _ = model.handle(.select)
        #expect(model.handle(.home) == .leave)
    }

    @Test func selectOnATeamTogglesItAndSearchStaysOpen() async throws {
        let (model, _, fixture) = try await makeLiveTV()
        defer { fixture.cleanUp() }
        await type(model, "duke")
        guard case .team(let duke)? = model.search?.results.first else {
            Issue.record("No team found")
            return
        }
        #expect(!fixture.library.isTeamPicked(duke.id))
        enterResults(model, at: 0)
        #expect(model.search?.focus == .results(0))
        #expect(model.handle(.select) == .handled)
        #expect(fixture.library.isTeamPicked(duke.id))
        #expect(model.search?.isTeamPicked(duke) == true)
        #expect(model.search?.focus == .results(0))
        #expect(model.mode == .player)
        // Again: removed.
        #expect(model.handle(.select) == .handled)
        #expect(!fixture.library.isTeamPicked(duke.id))
        #expect(model.search != nil)
    }

    @Test func phoneTextIsIgnoredWithoutChannels() async throws {
        let fixture = try makeLibrary(playlist: nil)
        defer { fixture.cleanUp() }
        let model = LiveTVModel(player: FakePlayer(), makePlayer: { FakePlayer() }, library: fixture.library)
        model.open()
        #expect(model.mode == .setupNeeded)
        model.typeText(TextEdit(deletions: 0, insertion: "nba"))
        #expect(model.search == nil)
    }
}
