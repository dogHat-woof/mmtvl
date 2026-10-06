import Foundation
import Testing
@testable import MMTVL

struct LiveTVModelTests {
    /// Last watched: NFL Network, the first channel.
    static let watching = IPTVState(lastChannelID: "id:nflnetwork.us")
    private func makeModel(playlist: URL? = IPTVFixtures.playlistURL, state: IPTVState? = nil) throws
        -> (LiveTVModel, FakePlayer, LibraryFixture) {
        let fixture = try makeLibrary(playlist: playlist, state: state)
        let player = FakePlayer()
        let model = LiveTVModel(player: player, library: fixture.library, now: { fixture.clock.now })
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
        let model = LiveTVModel(player: FakePlayer(), library: fixture.library)
        await open(model)
        #expect(model.mode == .unavailable("The playlist has no channels"))
        #expect(model.handle(.back) == .leave)
    }

    @Test func failedPlaylistIsUnavailableAndSelectRetries() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, texts: [:], state: Self.watching)
        defer { fixture.cleanUp() }
        let player = FakePlayer()
        let model = LiveTVModel(player: player, library: fixture.library)
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
    private func makeGuideModel() async throws -> (LiveTVModel, FakePlayer, LibraryFixture) {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guide: IPTVFixtures.customGuideURL,
                                      state: IPTVState(lastChannelID: "id:nbatv.us"))
        await fixture.library.refreshAll()
        let player = FakePlayer()
        let model = LiveTVModel(player: player, library: fixture.library, now: { fixture.clock.now })
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
        _ = model.handle(.left)                 // the now-cell → groups
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
}
