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
