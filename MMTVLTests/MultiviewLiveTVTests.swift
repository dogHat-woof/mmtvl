import Foundation
import Testing
@testable import MMTVL

/// Multiview through LiveTVModel, driven only by remote commands (M6). NFL Network plays first.
struct MultiviewLiveTVTests {
    static let nfl = "id:nflnetwork.us"
    static let nba = "id:nbatv.us"

    struct Setup {
        let model: LiveTVModel
        let player: FakePlayer
        let factory: PlayerFactory
        let fixture: LibraryFixture

        func id(_ name: String) -> Channel.ID {
            fixture.library.channels.first { $0.name == name }!.id
        }
    }

    /// The fixture playlist plus a sixth channel, for changing a window while 1 + 4 is full.
    static let sixChannels = IPTVFixtures.playlist + """

    #EXTINF:0 tvg-id="espn.us" group-title="Live Channels",ESPN
    \(IPTVFixtures.streamURL(6))
    """

    private func makeSetup(state: IPTVState = IPTVState(lastChannelID: "id:nflnetwork.us"),
                           playlist: String = IPTVFixtures.playlist) async throws -> Setup {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, texts: [IPTVFixtures.playlistURL: playlist],
                                      state: state)
        let player = FakePlayer()
        let factory = PlayerFactory()
        let model = LiveTVModel(player: player, makePlayer: factory.make, library: fixture.library,
                                now: { fixture.clock.now })
        model.open()
        await model.pendingTask?.value
        return Setup(model: model, player: player, factory: factory, fixture: fixture)
    }

    /// Full screen if needed, the guide, the channel's row, its channel cell, its menu, then the second item.
    private func addToMultiview(_ model: LiveTVModel, _ id: Channel.ID) {
        if model.mode == .multiview { _ = model.handle(.back) }
        _ = model.handle(.select)
        for _ in 0..<10 where model.guide?.focusedChannel?.id != id { _ = model.handle(.down) }
        for _ in 0..<10 where model.guide?.focusedChannel?.id != id { _ = model.handle(.up) }
        _ = model.handle(.left)
        _ = model.handle(.select)
        _ = model.handle(.down)
        _ = model.handle(.select)
    }

    /// Moves the open menu to the item, then selects it.
    private func choose(_ model: LiveTVModel, _ itemID: String) {
        for _ in 0..<10 where model.menu?.focusedItem?.id != itemID { _ = model.handle(.down) }
        for _ in 0..<10 where model.menu?.focusedItem?.id != itemID { _ = model.handle(.up) }
        #expect(model.menu?.focusedItem?.id == itemID)
        _ = model.handle(.select)
    }

    /// Moves the picker guide to the channel's row, then selects it.
    private func pick(_ model: LiveTVModel, _ id: Channel.ID) {
        for _ in 0..<10 where model.guide?.focusedChannel?.id != id { _ = model.handle(.down) }
        for _ in 0..<10 where model.guide?.focusedChannel?.id != id { _ = model.handle(.up) }
        _ = model.handle(.select)
    }

    private func fillOnePlusFour(_ setup: Setup) {
        for name in ["NBA TV", "Red Zone", "Lakers @ Celtics", "Knicks @ Heat"] {
            addToMultiview(setup.model, setup.id(name))
        }
    }

    private func allPlayers(_ setup: Setup) -> [FakePlayer] {
        [setup.player] + setup.factory.made
    }

    // MARK: Entering

    @Test func addWhilePlaying() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        addToMultiview(model, Self.nba)

        #expect(model.mode == .multiview)
        #expect(model.multiview?.slots == [Self.nfl, Self.nba, nil, nil, nil])
        #expect(model.multiview?.focusedSlot == 1)
        #expect(setup.factory.made.count == 1)
        let tile = try #require(setup.factory.made.first)
        #expect(tile.played == [IPTVFixtures.streamURL(2)])
        #expect(setup.player.played.count == 1)
        #expect(setup.player.bufferProfile == .tile)
        #expect(setup.player.audible == false)
        #expect(tile.audible)
        #expect(tile.bufferProfile == .tile)
        #expect(setup.fixture.library.state.multiview?.isActive == true)
        #expect(model.banner?.channel.name == "NBA TV")
    }

    @Test func theChannelMenuSaysAddThenShow() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        _ = model.handle(.select)
        _ = model.handle(.down)
        _ = model.handle(.left)
        _ = model.handle(.select)
        #expect(model.menu?.items.map(\.id) == ["watch", "addToMultiview"])
        #expect(model.menu?.items.last?.title == "Add to Multiview")
        _ = model.handle(.down)
        _ = model.handle(.select)
        _ = model.handle(.back)

        _ = model.handle(.select)
        _ = model.handle(.left)
        _ = model.handle(.select)
        #expect(model.menu?.items.last?.title == "Show in Multiview")
    }

    // MARK: Inside Multiview

    @Test func arrowsMoveTheHighlightAndTheSound() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        addToMultiview(model, Self.nba)
        let tile = setup.factory.made[0]

        _ = model.handle(.up)
        #expect(model.multiview?.focusedSlot == 0)
        #expect(setup.player.audible)
        #expect(tile.audible == false)
        #expect(model.banner?.channel.name == "NFL Network")

        _ = model.handle(.down)
        #expect(model.multiview?.focusedSlot == 2)
        #expect(setup.player.audible)
        #expect(model.banner == nil)

        _ = model.handle(.right)
        #expect(model.multiview?.focusedSlot == 3)
    }

    @Test func transportActsOnTheHighlightedWindow() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        addToMultiview(model, Self.nba)
        let tile = setup.factory.made[0]

        for command in [RemoteCommand.rewind, .fastForward, .playPause] {
            #expect(model.handle(command) == .handled)
        }
        #expect(tile.seeks == [-30, 30])
        #expect(tile.pauses == 1)
        #expect(setup.player.seeks.isEmpty)
        #expect(setup.player.pauses == 0)
        #expect(model.showsTimeshiftBar)
    }

    // MARK: Leaving

    @Test func backGoesFullScreenWithTheHighlightedWindow() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        addToMultiview(model, Self.nba)
        let tile = setup.factory.made[0]

        #expect(model.handle(.back) == .handled)
        #expect(model.mode == .player)
        #expect(model.player === tile)
        #expect(model.currentChannel?.name == "NBA TV")
        #expect(setup.player.stops == 1)
        #expect(tile.played.count == 1)
        #expect(tile.bufferProfile == .full)
        #expect(tile.audible)
        #expect(setup.player.audible)
        #expect(model.multiview == nil)
        #expect(setup.fixture.library.state.multiview?.isActive == false)
        #expect(setup.fixture.library.state.multiview?.slots == [Self.nfl, Self.nba, nil, nil, nil])
        #expect(setup.fixture.library.state.lastChannelID == Self.nba)
        #expect(model.banner?.channel.name == "NBA TV")
    }

    @Test func reenteringBringsBackTheWindows() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        addToMultiview(model, Self.nba)
        _ = model.handle(.back)

        addToMultiview(model, Self.nba)
        #expect(model.mode == .multiview)
        #expect(model.multiview?.slots == [Self.nfl, Self.nba, nil, nil, nil])
        #expect(model.multiview?.focusedSlot == 1)
        #expect(setup.player.played == [IPTVFixtures.streamURL(1), IPTVFixtures.streamURL(1)])
        #expect(setup.factory.made.count == 1)
        #expect(setup.factory.made[0].played.count == 1)
    }

    @Test func fiveWindowsUseFivePlayers() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        for name in ["NBA TV", "Red Zone", "Lakers @ Celtics", "Knicks @ Heat"] {
            addToMultiview(model, setup.id(name))
        }
        #expect(model.mode == .multiview)
        #expect(model.multiview?.channelIDs.count == 5)
        #expect(setup.factory.made.count == 4)
        #expect(Set(model.tilePlayers.values.map { ObjectIdentifier($0) }).count == 5)
    }

    @Test func leaveStopsEveryPlayerAndOpenRestores() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        for name in ["NBA TV", "Red Zone"] {
            addToMultiview(model, setup.id(name))
        }
        let slots = model.multiview?.slots
        let players = allPlayers(setup)
        let stops = players.map(\.stops)

        model.leave()
        let allStopped = zip(players, stops).allSatisfy { $0.stops > $1 }
        #expect(allStopped)
        #expect(model.multiview == nil)
        #expect(model.tilePlayers.isEmpty)
        #expect(setup.fixture.library.state.multiview?.isActive == true)

        let plays = players.map(\.played.count)
        model.open()
        await model.pendingTask?.value
        #expect(model.mode == .multiview)
        #expect(model.multiview?.slots == slots)
        #expect(players.count == 3)
        let allReplayed = zip(players, plays).allSatisfy { $0.played.count == $1 + 1 }
        #expect(allReplayed)
        let urls = Set(model.tilePlayers.values.compactMap { ($0 as? FakePlayer)?.played.last })
        #expect(urls == [IPTVFixtures.streamURL(1), IPTVFixtures.streamURL(2), IPTVFixtures.streamURL(3)])
    }

    @Test func openWithAnInactiveSnapshotResumesTheLastChannel() async throws {
        let snapshot = MultiviewSnapshot(layout: .onePlusFour, slots: [Self.nfl, Self.nba, nil, nil, nil],
                                         focusedSlot: 1, isActive: false)
        let setup = try await makeSetup(state: IPTVState(lastChannelID: Self.nfl, multiview: snapshot))
        defer { setup.fixture.cleanUp() }
        #expect(setup.model.mode == .player)
        #expect(setup.factory.made.isEmpty)
    }

    @Test func openWithStaleSnapshotChannelsMarksItInactive() async throws {
        let snapshot = MultiviewSnapshot(layout: .onePlusFour, slots: ["id:gone", nil, nil, nil, nil],
                                         focusedSlot: 0, isActive: true)
        let setup = try await makeSetup(state: IPTVState(lastChannelID: Self.nfl, multiview: snapshot))
        defer { setup.fixture.cleanUp() }
        #expect(setup.model.mode == .player)
        #expect(setup.fixture.library.state.multiview?.isActive == false)
    }

    // MARK: Volume

    @Test func appVolumeReachesEveryPlayer() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        model.setAppVolume(30, muted: false)
        #expect(setup.player.volume?.level == 30)
        addToMultiview(model, Self.nba)
        #expect(setup.factory.made[0].volume?.level == 30)
        #expect(setup.factory.made[0].volume?.muted == false)
    }

    // MARK: Placements

    @Test func placements() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model

        let full = model.videoPlacements
        #expect(full.count == 1)
        #expect(full.first?.player === setup.player)
        #expect(full.first?.canvasRect == nil)
        #expect(full.first?.isVisible == true)

        _ = model.handle(.select)
        #expect(model.videoPlacements.map(\.canvasRect) == [Theme.guidePreviewRect])
        _ = model.handle(.back)

        addToMultiview(model, Self.nba)
        let windows = model.videoPlacements
        #expect(windows.count == 2)
        #expect(windows[0].player === setup.player)
        #expect(windows[1].player === setup.factory.made[0])
        #expect(windows.map(\.canvasRect) == Array(MultiviewLayout.onePlusFour.slots.prefix(2)))
        let allVisible = windows.allSatisfy(\.isVisible)
        #expect(allVisible)
    }

    // MARK: Failures

    @Test func aWindowFailureRefreshesOnceThenShowsAnError() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        addToMultiview(model, Self.nba)
        let tile = setup.factory.made[0]
        let fetches = setup.fixture.network.fetchCount

        tile.fail()
        await model.pendingTask?.value
        #expect(setup.fixture.network.fetchCount == fetches + 1)
        #expect(tile.played == [IPTVFixtures.streamURL(2), IPTVFixtures.streamURL(2)])
        #expect(model.failedWindows.isEmpty)

        tile.fail()
        #expect(model.failedWindows == [Self.nba])
        #expect(tile.played.count == 2)

        _ = model.handle(.back)
        #expect(model.mode == .player)
        #expect(model.playbackError == LiveTVModel.playbackErrorMessage)
    }

    @Test func aReleasedPlayerFailingIsIgnored() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        addToMultiview(model, Self.nba)
        _ = model.handle(.back)
        setup.player.fail()
        #expect(model.playbackError == nil)
        #expect(setup.player.played.count == 1)
    }

    // MARK: Window menu (step 6)

    @Test func windowMenuItems() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        addToMultiview(model, Self.nba)

        _ = model.handle(.select)
        #expect(model.menu?.title == "NBA TV")
        #expect(model.menu?.items.map(\.id) == ["fullScreen", "makeMain", "changeChannel", "layout", "remove"])
        #expect(model.menu?.items.first { $0.id == "layout" }?.value == "1 + 4")

        choose(model, "layout")
        #expect(model.menu?.title == "Layout")
        #expect(model.menu?.focusedItem?.id == "layout.onePlusFour")
        #expect(model.menu?.focusedItem?.value == "Current")
        choose(model, "layout.grid")
        #expect(model.menu == nil)
        #expect(model.multiview?.layout == .grid)

        _ = model.handle(.select)
        #expect(model.menu?.items.map(\.id) == ["fullScreen", "changeChannel", "layout", "remove"])
        _ = model.handle(.back)

        setup.factory.made[0].fail()
        await model.pendingTask?.value
        setup.factory.made[0].fail()
        _ = model.handle(.select)
        #expect(model.menu?.items.map(\.id) == ["fullScreen", "changeChannel", "retry", "layout", "remove"])
    }

    @Test func fullScreenFromTheMenu() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        addToMultiview(model, Self.nba)
        _ = model.handle(.select)
        choose(model, "fullScreen")
        #expect(model.mode == .player)
        #expect(model.player === setup.factory.made[0])
    }

    // MARK: Picker guide

    @Test func selectOnAnEmptyWindowPicksItsChannel() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        addToMultiview(model, Self.nba)
        _ = model.handle(.right)
        #expect(model.multiview?.focusedSlot == 2)

        _ = model.handle(.select)
        #expect(model.mode == .guide)
        #expect(model.guidePurpose == .pick(slot: 2))
        #expect(model.guide?.focusedChannel?.id == Self.nba)
        #expect(model.previewPlayer === setup.factory.made[0])
        #expect(model.previewChannel?.id == Self.nba)

        let redZone = setup.id("Red Zone")
        pick(model, redZone)
        #expect(model.mode == .multiview)
        #expect(model.guidePurpose == .watch)
        #expect(model.multiview?.slots == [Self.nfl, Self.nba, redZone, nil, nil])
        #expect(model.multiview?.focusedSlot == 2)
        #expect(model.multiview?.audioSlot == 2)
        #expect(setup.factory.made.count == 2)
        #expect(setup.factory.made[1].played == [IPTVFixtures.streamURL(3)])
        #expect(setup.factory.made[1].audible)
        #expect(setup.factory.made[0].audible == false)
        #expect(setup.fixture.library.state.multiview?.slots == [Self.nfl, Self.nba, redZone, nil, nil])
    }

    @Test func selectOnTheChannelCellAlsoPicks() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        addToMultiview(model, Self.nba)
        _ = model.handle(.right)
        _ = model.handle(.select)
        _ = model.handle(.down)
        _ = model.handle(.left)
        _ = model.handle(.select)
        #expect(model.menu == nil)
        #expect(model.mode == .multiview)
        #expect(model.multiview?.slots[2] == setup.id("Red Zone"))
    }

    @Test func changeChannelReleasesTheOldPlayerAndKeepsThePoolAtFive() async throws {
        let setup = try await makeSetup(playlist: Self.sixChannels)
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        fillOnePlusFour(setup)
        let focused = try #require(model.multiview?.focusedSlot)
        let oldID = try #require(model.multiview?.focusedChannelID)
        let old = try #require(model.tilePlayers[oldID] as? FakePlayer)
        let stops = old.stops

        _ = model.handle(.select)
        choose(model, "changeChannel")
        #expect(model.guidePurpose == .pick(slot: focused))
        pick(model, "id:espn.us")

        #expect(model.mode == .multiview)
        #expect(model.multiview?.slots[focused] == "id:espn.us")
        #expect(old.stops == stops + 1)
        #expect(setup.factory.made.count == 4)
        #expect(model.tilePlayers[oldID] == nil)
        let espn = try #require(model.tilePlayers["id:espn.us"] as? FakePlayer)
        #expect(espn.played.last == IPTVFixtures.streamURL(6))
    }

    @Test func changeChannelToAShownChannelSwaps() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        addToMultiview(model, Self.nba)
        let plays = allPlayers(setup).map(\.played.count)

        _ = model.handle(.select)
        choose(model, "changeChannel")
        pick(model, Self.nfl)
        #expect(model.multiview?.slots == [Self.nba, Self.nfl, nil, nil, nil])
        #expect(model.multiview?.focusedSlot == 1)
        #expect(allPlayers(setup).map(\.played.count) == plays)
        #expect(setup.player.audible)
        #expect(setup.factory.made[0].audible == false)
    }

    @Test func backInThePickerReturnsUnchanged() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        addToMultiview(model, Self.nba)
        _ = model.handle(.select)
        choose(model, "changeChannel")
        _ = model.handle(.down)
        #expect(model.handle(.back) == .handled)
        #expect(model.mode == .multiview)
        #expect(model.multiview?.slots == [Self.nfl, Self.nba, nil, nil, nil])
        #expect(model.multiview?.focusedSlot == 1)
    }

    @Test func playPauseInThePickerPausesTheWindowWithSound() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        addToMultiview(model, Self.nba)
        _ = model.handle(.select)
        choose(model, "changeChannel")
        _ = model.handle(.playPause)
        #expect(setup.factory.made[0].pauses == 1)
        #expect(setup.player.pauses == 0)
    }

    @Test func pickerPlacements() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        addToMultiview(model, Self.nba)
        _ = model.handle(.select)
        choose(model, "changeChannel")

        let placements = model.videoPlacements
        #expect(placements.count == 2)
        #expect(placements[0].player === setup.player)
        #expect(placements[0].canvasRect == MultiviewLayout.onePlusFour.slots[0])
        #expect(placements[0].isVisible == false)
        #expect(placements[1].player === setup.factory.made[0])
        #expect(placements[1].canvasRect == Theme.guidePreviewRect)
        #expect(placements[1].isVisible)
    }

    // MARK: Make Main, layouts, removal, retry

    @Test func makeMain() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        addToMultiview(model, Self.nba)
        _ = model.handle(.select)
        choose(model, "makeMain")
        #expect(model.multiview?.slots == [Self.nba, Self.nfl, nil, nil, nil])
        #expect(model.multiview?.focusedSlot == 0)
        #expect(model.multiview?.audioSlot == 0)
        #expect(setup.factory.made[0].audible)
        #expect(setup.player.audible == false)
        #expect(setup.fixture.library.state.multiview?.slots == [Self.nba, Self.nfl, nil, nil, nil])
        #expect(model.videoPlacements.first?.player === setup.factory.made[0])
    }

    @Test func smallerLayoutKeepsTheWindowWithSound() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        fillOnePlusFour(setup)
        _ = model.handle(.left)
        #expect(model.multiview?.focusedSlot == 3)
        let first = try #require(model.multiview?.slots[0])
        let kept = try #require(model.multiview?.slots[3])
        let players = model.tilePlayers.compactMapValues { $0 as? FakePlayer }
        let stops = players.mapValues(\.stops)

        _ = model.handle(.select)
        choose(model, "layout")
        choose(model, "layout.sideBySide")
        #expect(model.multiview?.layout == .sideBySide)
        #expect(model.multiview?.slots == [first, kept])
        #expect(model.multiview?.focusedSlot == 1)
        let stopped = players.filter { $0.value.stops > stops[$0.key]! }.map(\.key)
        #expect(Set(stopped) == Set(players.keys).subtracting([first, kept]))
        #expect(model.tilePlayers.count == 2)
        #expect(setup.fixture.library.state.multiview?.layout == .sideBySide)
        #expect(setup.fixture.library.state.multiview?.slots == [first, kept])
    }

    @Test func removeWindowsUntilEmpty() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        addToMultiview(model, Self.nba)
        let tile = setup.factory.made[0]
        let stops = tile.stops

        _ = model.handle(.select)
        choose(model, "remove")
        #expect(tile.stops == stops + 1)
        #expect(model.multiview?.slots == [Self.nfl, nil, nil, nil, nil])
        #expect(model.multiview?.audioSlot == 0)
        #expect(setup.player.audible)
        #expect(model.mode == .multiview)

        _ = model.handle(.up)
        _ = model.handle(.select)
        choose(model, "remove")
        #expect(model.mode == .guide)
        #expect(model.guidePurpose == .watch)
        #expect(model.multiview == nil)
        #expect(model.tilePlayers.isEmpty)
        #expect(setup.fixture.library.state.multiview == nil)
        #expect(allPlayers(setup).allSatisfy { $0.state.phase == .idle })
        // Nothing plays, so Back leaves.
        #expect(model.handle(.back) == .leave)
    }

    @Test func retryAfterTwoFailures() async throws {
        let setup = try await makeSetup()
        defer { setup.fixture.cleanUp() }
        let model = setup.model
        addToMultiview(model, Self.nba)
        let tile = setup.factory.made[0]
        tile.fail()
        await model.pendingTask?.value
        tile.fail()
        #expect(model.failedWindows == [Self.nba])

        _ = model.handle(.select)
        choose(model, "retry")
        #expect(model.failedWindows.isEmpty)
        #expect(tile.played.count == 3)
        #expect(tile.played.last == IPTVFixtures.streamURL(2))
    }
}
