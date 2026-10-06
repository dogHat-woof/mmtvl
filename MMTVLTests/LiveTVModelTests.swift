import Foundation
import Testing
@testable import MMTVL

struct LiveTVModelTests {
    /// Last watched: NFL Network, the first channel.
    static let watching = IPTVState(lastChannelID: "id:nflnetwork.us")
    private func makeModel(playlist: URL? = IPTVFixtures.playlistURL, state: IPTVState? = nil,
                           preferences: ChannelPreferences? = nil) throws
        -> (LiveTVModel, FakePlayer, LibraryFixture) {
        let fixture = try makeLibrary(playlist: playlist, state: state, preferences: preferences)
        let player = FakePlayer()
        let model = LiveTVModel(player: player, makePlayer: { FakePlayer() }, library: fixture.library, now: { fixture.clock.now })
        return (model, player, fixture)
    }

    private func open(_ model: LiveTVModel) async {
        model.open()
        await model.pendingTask?.value
    }

    @Test func noPlaylistNeedsSetup() async throws {
        let (model, player, fixture) = try makeModel(playlist: nil)
        defer { fixture.cleanUp() }
        await open(model)
        #expect(model.mode == .setupNeeded)
        #expect(model.handle(.down) == .handled)
        #expect(model.handle(.select) == .openSettings)
        #expect(model.handle(.back) == .leave)
        #expect(player.played.isEmpty)
    }

    @Test func noLastChannelOpensTheGuide() async throws {
        let (model, player, fixture) = try makeModel()
        defer { fixture.cleanUp() }
        await open(model)
        #expect(model.mode == .guide)
        #expect(player.played.isEmpty)
        #expect(model.guide?.focusedChannel?.name == "NFL Network")
        // Back with nothing playing leaves.
        #expect(model.handle(.back) == .leave)
    }

    @Test func lastChannelResumes() async throws {
        let (model, player, fixture) = try makeModel(state: IPTVState(lastChannelID: "id:nbatv.us"))
        defer { fixture.cleanUp() }
        await open(model)
        #expect(model.mode == .player)
        #expect(player.played == [IPTVFixtures.streamURL(2)])
        #expect(model.banner?.channel.name == "NBA TV")
    }

    @Test func emptyPlaylistIsUnavailable() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, texts: [IPTVFixtures.playlistURL: "#EXTM3U\n"])
        defer { fixture.cleanUp() }
        let model = LiveTVModel(player: FakePlayer(), makePlayer: { FakePlayer() }, library: fixture.library)
        await open(model)
        #expect(model.mode == .unavailable("The playlist has no channels"))
        #expect(model.handle(.back) == .leave)
    }

    @Test func failedPlaylistIsUnavailableAndSelectRetries() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, texts: [:], state: Self.watching)
        defer { fixture.cleanUp() }
        let player = FakePlayer()
        let model = LiveTVModel(player: player, makePlayer: { FakePlayer() }, library: fixture.library)
        await open(model)
        #expect(model.mode == .unavailable("Server error (HTTP 404)"))

        fixture.network.setText(IPTVFixtures.playlist, for: IPTVFixtures.playlistURL)
        #expect(model.handle(.select) == .handled)
        await model.pendingTask?.value
        #expect(model.mode == .player)
        #expect(player.played.count == 1)
    }

    @Test func upDownZapWithinTheRememberedGroupAndWrap() async throws {
        let (model, player, fixture) = try makeModel(state: IPTVState(lastChannelID: "id:lakers @ celtics", lastGroup: "NBA Games"))
        defer { fixture.cleanUp() }
        await open(model)
        #expect(model.currentChannel?.name == "Lakers @ Celtics")

        _ = model.handle(.down)
        #expect(model.currentChannel?.name == "Knicks @ Heat")
        #expect(fixture.library.state.lastChannelID == "id:knicks @ heat")
        _ = model.handle(.down)
        #expect(model.currentChannel?.name == "Lakers @ Celtics")
        _ = model.handle(.up)
        #expect(model.currentChannel?.name == "Knicks @ Heat")
        #expect(player.played == [IPTVFixtures.streamURL(4), IPTVFixtures.streamURL(5), IPTVFixtures.streamURL(4), IPTVFixtures.streamURL(5)])
        #expect(model.banner?.channel.name == "Knicks @ Heat")
    }

    @Test func zapUsesTheChannelsOwnGroupWhenTheRememberedOneLacksIt() async throws {
        let (model, _, fixture) = try makeModel(state: IPTVState(lastChannelID: "id:nflnetwork.us", lastGroup: "NBA Games"))
        defer { fixture.cleanUp() }
        await open(model)
        _ = model.handle(.up)
        #expect(model.currentChannel?.name == "Red Zone")
    }

    // MARK: Lineup (M6b L11)

    @Test func zapSkipsAHiddenChannel() async throws {
        let (model, _, fixture) = try makeModel(state: Self.watching, preferences: ChannelPreferences(hiddenChannels: ["id:nbatv.us"]))
        defer { fixture.cleanUp() }
        await open(model)
        _ = model.handle(.down)
        #expect(model.currentChannel?.name == "Red Zone")
    }

    @Test func zapInFavoritesWraps() async throws {
        let (model, _, fixture) = try makeModel(state: IPTVState(lastChannelID: "name:red zone", lastGroup: "Favorites"),
                                                preferences: ChannelPreferences(favorites: ["id:knicks @ heat", "name:red zone"]))
        defer { fixture.cleanUp() }
        await open(model)
        #expect(model.currentChannel?.name == "Red Zone")
        _ = model.handle(.down)
        #expect(model.currentChannel?.name == "Knicks @ Heat")
        _ = model.handle(.up)
        #expect(model.currentChannel?.name == "Red Zone")
    }

    @Test func zapFromAChannelHiddenWhilePlaying() async throws {
        let (model, player, fixture) = try makeModel(state: Self.watching)
        defer { fixture.cleanUp() }
        await open(model)
        fixture.library.setChannelHidden("id:nflnetwork.us", true)
        #expect(player.played == [IPTVFixtures.streamURL(1)])    // hiding stops nothing
        _ = model.handle(.down)
        #expect(model.currentChannel?.name == "NBA TV")
    }

    @Test func seeks() async throws {
        let (model, player, fixture) = try makeModel(state: Self.watching)
        defer { fixture.cleanUp() }
        await open(model)
        for command in [RemoteCommand.left, .right, .rewind, .fastForward] {
            #expect(model.handle(command) == .handled)
        }
        #expect(player.seeks == [-10, 10, -30, 30])
        #expect(model.showsTimeshiftBar)
    }

    @Test func playPauseToggles() async throws {
        let (model, player, fixture) = try makeModel(state: Self.watching)
        defer { fixture.cleanUp() }
        await open(model)
        _ = model.handle(.playPause)
        #expect(player.pauses == 1)
    }

    @Test func backHidesOverlaysThenLeaves() async throws {
        let (model, _, fixture) = try makeModel(state: Self.watching)
        defer { fixture.cleanUp() }
        await open(model)
        #expect(model.banner != nil)
        #expect(model.handle(.back) == .handled)
        #expect(model.banner == nil)
        #expect(model.handle(.back) == .leave)
    }

    @Test func failureRefreshesThePlaylistOnceThenShowsAnError() async throws {
        let (model, player, fixture) = try makeModel(state: Self.watching)
        defer { fixture.cleanUp() }
        await open(model)
        let fetches = fixture.network.fetchCount

        player.fail()
        await model.pendingTask?.value
        #expect(fixture.network.fetchCount == fetches + 1)
        #expect(player.played.count == 2)
        #expect(model.playbackError == nil)

        player.fail()
        #expect(model.playbackError == "Can't play this channel")
        #expect(player.played.count == 2)

        _ = model.handle(.select)
        #expect(player.played.count == 3)
        #expect(model.playbackError == nil)
    }

    @Test func leaveStops() async throws {
        let (model, player, fixture) = try makeModel(state: Self.watching)
        defer { fixture.cleanUp() }
        await open(model)
        model.leave()
        #expect(player.stops == 1)
        #expect(model.banner == nil)
        #expect(model.currentChannel?.name == "NFL Network")
    }

    @Test func homeLeaves() async throws {
        let (model, _, fixture) = try makeModel(state: Self.watching)
        defer { fixture.cleanUp() }
        await open(model)
        #expect(model.handle(.home) == .leave)
    }

    @Test func canvasGeometry() {
        let rect = CanvasGeometry.windowRect(forCanvasRect: CGRect(x: 1160, y: 60, width: 640, height: 360),
                                             in: CGSize(width: 960, height: 540))
        #expect(rect == CGRect(x: 580, y: 30, width: 320, height: 180))
        // A taller window centers the canvas vertically.
        let tall = CanvasGeometry.windowRect(forCanvasRect: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                             in: CGSize(width: 1920, height: 1200))
        #expect(tall == CGRect(x: 0, y: 60, width: 1920, height: 1080))
    }
    // MARK: Guide

    /// Playing NBA TV (row 2 of "All Channels"), with the fixture guide imported.
    private func makeGuideModel(preferences: ChannelPreferences? = nil) async throws -> (LiveTVModel, FakePlayer, LibraryFixture) {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL],
                                      state: IPTVState(lastChannelID: "id:nbatv.us"), preferences: preferences)
        await fixture.library.refreshAll()
        let player = FakePlayer()
        let model = LiveTVModel(player: player, makePlayer: { FakePlayer() }, library: fixture.library, now: { fixture.clock.now })
        await open(model)
        player.state.phase = .playing
        return (model, player, fixture)
    }

    @Test func selectInThePlayerOpensTheGuideOnTheCurrentChannel() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        #expect(model.handle(.select) == .handled)
        #expect(model.mode == .guide)
        #expect(model.guide?.selectedGroup == "All Channels")
        #expect(model.guide?.focusedChannel?.id == "id:nbatv.us")
        #expect(model.banner == nil)
    }

    @Test func programmesAreLoadedForTheGuide() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        _ = model.handle(.select)
        await model.pendingTask?.value
        #expect(model.guide?.programmes["id:nbatv.us"]?.first?.title == "NBA TV 0")
        #expect(model.guide?.programmes["id:nflnetwork.us"]?.count == 4)
        #expect(model.guide?.focusedCell(now: fixture.clock.now)?.programme?.title == "NBA TV 1")
    }

    @Test func selectOnAnotherRowPlaysIt() async throws {
        let (model, player, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        _ = model.handle(.select)
        _ = model.handle(.up)
        #expect(model.handle(.select) == .handled)
        #expect(model.mode == .player)
        #expect(model.guide == nil)
        #expect(model.currentChannel?.name == "NFL Network")
        #expect(player.played == [IPTVFixtures.streamURL(2), IPTVFixtures.streamURL(1)])
    }

    @Test func selectOnTheCurrentRowReturnsWithoutReloading() async throws {
        let (model, player, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        _ = model.handle(.select)
        _ = model.handle(.select)
        #expect(model.mode == .player)
        #expect(player.played == [IPTVFixtures.streamURL(2)])
        #expect(model.banner?.channel.id == "id:nbatv.us")
    }

    @Test func backInTheGuideReturnsToThePlayer() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        _ = model.handle(.select)
        #expect(model.handle(.back) == .handled)
        #expect(model.mode == .player)
    }

    @Test func playPauseInTheGuidePausesThePreview() async throws {
        let (model, player, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        _ = model.handle(.select)
        _ = model.handle(.playPause)
        #expect(player.pauses == 1)
        #expect(model.mode == .guide)
    }

    @Test func groupChangeIsRemembered() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        _ = model.handle(.select)
        _ = model.handle(.left)                 // the now-cell → the channel cell
        _ = model.handle(.left)                 // → groups
        #expect(model.guide?.focus == .groups(0))
        _ = model.handle(.down)
        _ = model.handle(.down)
        _ = model.handle(.select)
        #expect(model.guide?.selectedGroup == "NBA Games")
        #expect(fixture.library.state.lastGroup == "NBA Games")
        await model.pendingTask?.value
        #expect(model.guide?.channels.map(\.name) == ["Lakers @ Celtics", "Knicks @ Heat"])
    }

    @Test func leaveClearsTheGuide() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        _ = model.handle(.select)
        model.leave()
        #expect(model.guide == nil)
    }

    // MARK: Channel menu (M6 L8)

    @Test func selectOnTheChannelCellOpensTheChannelMenu() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        _ = model.handle(.select)
        _ = model.handle(.up)
        _ = model.handle(.left)
        #expect(model.handle(.select) == .handled)
        #expect(model.menu?.title == "NFL Network")
        #expect(model.menu?.items.map(\.id) == ["watch", "addToMultiview", "favorite", "matchGuide", "hide"])
    }

    // MARK: Channel menu (M6b L8)

    /// Guide on NBA TV, then Up to NFL Network, Left to its channel cell, Select.
    private func openNFLMenu(_ model: LiveTVModel) {
        _ = model.handle(.select)
        _ = model.handle(.up)
        _ = model.handle(.left)
        _ = model.handle(.select)
    }

    private func choose(_ itemID: String, in model: LiveTVModel) {
        guard let index = model.menu?.items.firstIndex(where: { $0.id == itemID }) else {
            Issue.record("No \(itemID) item")
            return
        }
        for _ in 0..<index { _ = model.handle(.down) }
        _ = model.handle(.select)
    }

    @Test func addToFavorites() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openNFLMenu(model)
        #expect(model.menu?.items.first { $0.id == "favorite" }?.title == "Add to Favorites")
        choose("favorite", in: model)
        #expect(model.menu == nil)
        #expect(fixture.library.isFavorite("id:nflnetwork.us"))
        #expect(model.guide?.groups.first == "Favorites")
        #expect(model.guide?.focusedChannel?.name == "NFL Network")
        _ = model.handle(.select)
        #expect(model.menu?.items.first { $0.id == "favorite" }?.title == "Remove from Favorites")
    }

    @Test func moveInFavoritesKeepsTheMenuOpen() async throws {
        let (model, _, fixture) = try await makeGuideModel(
            preferences: ChannelPreferences(favorites: ["id:nflnetwork.us", "id:nbatv.us"]))
        defer { fixture.cleanUp() }
        openNFLMenu(model)
        #expect(model.guide?.selectedGroup == "Favorites")
        #expect(model.menu?.items.map(\.id) == ["watch", "addToMultiview", "favorite", "moveDown", "matchGuide", "hide"])
        choose("moveDown", in: model)
        #expect(fixture.library.preferences.favorites == ["id:nbatv.us", "id:nflnetwork.us"])
        #expect(model.menu?.items.map(\.id) == ["watch", "addToMultiview", "favorite", "moveUp", "matchGuide", "hide"])
        #expect(model.menu?.focusedItem?.id == "moveUp")
        #expect(model.guide?.focusedChannel?.name == "NFL Network")
        #expect(model.guide?.channels.map(\.name) == ["NBA TV", "NFL Network"])
    }

    // MARK: Match Guide (M6b L9)

    @Test func matchGuideValueNamesTheGuide() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openNFLMenu(model)
        #expect(model.menu?.items.first { $0.id == "matchGuide" }?.value == "custom")
        _ = model.handle(.back)
        _ = model.handle(.down)
        _ = model.handle(.down)
        _ = model.handle(.select)
        #expect(model.menu?.title == "Red Zone")
        #expect(model.menu?.items.first { $0.id == "matchGuide" }?.value == "None")
    }

    @Test func matchGuideMenu() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        _ = model.handle(.select)
        _ = model.handle(.down)
        _ = model.handle(.left)
        _ = model.handle(.select)
        #expect(model.menu?.title == "Red Zone")
        choose("matchGuide", in: model)
        #expect(model.menu == nil)
        await model.pendingTask?.value
        let menu = try #require(model.menu)
        #expect(menu.title == "Guide for Red Zone")
        #expect(menu.isWide)
        #expect(Array(menu.items.map(\.id).prefix(2)) == ["match.automatic", "match.none"])
        #expect(menu.focusedItem?.id == "match.automatic")
        #expect(menu.focusedItem?.value == "Selected")
    }

    @Test func choosingACandidateMatches() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openNFLMenu(model)
        choose("matchGuide", in: model)
        await model.pendingTask?.value
        let customID = IPTVLibrary.hash(IPTVFixtures.customGuideURL)
        let current = "match.\(customID).nfl.network.hd.us2"
        let redZone = "match.\(customID).nfl.redzone.hd.us2"
        #expect(model.menu?.items.map(\.id).dropFirst(2).first == current)
        #expect(model.menu?.items.first { $0.id == current }?.value == "custom · Automatic")
        choose(redZone, in: model)
        await model.pendingTask?.value
        #expect(fixture.library.epgMatches["id:nflnetwork.us"] == EPGRef(sourceID: customID, epgID: "nfl.redzone.hd.us2"))
        #expect(fixture.overridesFile.load() == ["NFL Network": "nfl.redzone.hd.us2"])
    }

    @Test func hideChannel() async throws {
        let (model, player, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        openNFLMenu(model)
        choose("hide", in: model)
        #expect(model.menu == nil)
        #expect(model.guide?.channels.contains { $0.name == "NFL Network" } == false)
        #expect(model.guide?.focusedChannel?.name == "NBA TV")
        #expect(model.currentChannel?.name == "NBA TV")
        #expect(player.played == [IPTVFixtures.streamURL(2)])
    }

    @Test func watchInTheChannelMenuPlays() async throws {
        let (model, player, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        _ = model.handle(.select)
        _ = model.handle(.up)
        _ = model.handle(.left)
        _ = model.handle(.select)
        _ = model.handle(.select)
        #expect(model.mode == .player)
        #expect(model.menu == nil)
        #expect(model.currentChannel?.name == "NFL Network")
        #expect(player.played == [IPTVFixtures.streamURL(2), IPTVFixtures.streamURL(1)])
    }

    @Test func backClosesTheChannelMenu() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        _ = model.handle(.select)
        _ = model.handle(.left)
        _ = model.handle(.select)
        #expect(model.menu != nil)
        #expect(model.handle(.back) == .handled)
        #expect(model.menu == nil)
        #expect(model.mode == .guide)
    }

    @Test func homeWithTheMenuOpenLeaves() async throws {
        let (model, _, fixture) = try await makeGuideModel()
        defer { fixture.cleanUp() }
        _ = model.handle(.select)
        _ = model.handle(.left)
        _ = model.handle(.select)
        #expect(model.handle(.home) == .leave)
    }
}
