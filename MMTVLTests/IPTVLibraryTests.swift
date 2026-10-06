import Foundation
import Testing
@testable import MMTVL

struct IPTVLibraryTests {
    private let hour: TimeInterval = 3600

    @Test func noPlaylist() async throws {
        let fixture = try makeLibrary()
        defer { fixture.cleanUp() }
        let library = fixture.library
        #expect(library.hasPlaylist == false)
        #expect(library.guideSource == .none)
        await library.refreshAll()
        await library.refreshPlaylistIfStale()
        await library.refreshGuideIfStale()
        #expect(fixture.network.fetchCount == 0)
        #expect(fixture.network.downloadCount == 0)
        #expect(library.playlistStatus == .idle)
        #expect(library.guideStatus == .idle)
    }

    @Test func setPlaylistURLLoadsChannels() async throws {
        let fixture = try makeLibrary()
        defer { fixture.cleanUp() }
        let library = fixture.library
        var statusChanges = 0
        library.onStatusChange = { statusChanges += 1 }

        await library.setPlaylistURL(IPTVFixtures.playlistURL)

        #expect(library.hasPlaylist)
        #expect(fixture.sources.playlistURL() == IPTVFixtures.playlistURL)
        #expect(library.channels.map(\.name) == ["NFL Network", "NBA TV", "Red Zone", "Lakers @ Celtics", "Knicks @ Heat"])
        #expect(library.playlistStatus == .loaded(fixture.clock.now))
        #expect(library.playlistHost == "provider.example")
        #expect(statusChanges >= 2)
        // No guide anywhere: nothing downloaded.
        #expect(library.guideSource == .none)
        #expect(fixture.network.downloadCount == 0)
    }

    @Test func httpFailureKeepsChannels() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshPlaylist()
        #expect(library.channels.count == 5)

        fixture.network.setError(IPTVNetworkError.http(403), for: IPTVFixtures.playlistURL)
        await library.refreshPlaylist()
        #expect(library.playlistStatus == .failed("Server error (HTTP 403)"))
        #expect(library.channels.count == 5)
    }

    @Test func notAPlaylistMessage() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL,
                                      texts: [IPTVFixtures.playlistURL: "<html><body>Error</body></html>"])
        defer { fixture.cleanUp() }
        await fixture.library.refreshPlaylist()
        #expect(fixture.library.playlistStatus == .failed("The address didn't return a playlist"))
        #expect(fixture.library.channels.isEmpty)
    }

    @Test func refreshPlaylistIfStale() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshPlaylistIfStale()
        #expect(fixture.network.fetchCount == 1)
        fixture.clock.advance(9 * 60)
        await library.refreshPlaylistIfStale()
        #expect(fixture.network.fetchCount == 1)
        fixture.clock.advance(2 * 60)
        await library.refreshPlaylistIfStale()
        #expect(fixture.network.fetchCount == 2)
    }

    @Test func guideSource() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL,
                                      texts: [IPTVFixtures.playlistURL: IPTVFixtures.playlistWithGuide])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshPlaylist()
        #expect(library.guideSource == .playlist(IPTVFixtures.playlistGuideURL))

        await library.setGuideURL(IPTVFixtures.customGuideURL)
        #expect(library.guideSource == .custom(IPTVFixtures.customGuideURL))
        #expect(fixture.sources.guideURL() == IPTVFixtures.customGuideURL)

        await library.setGuideURL(nil)
        #expect(library.guideSource == .playlist(IPTVFixtures.playlistGuideURL))
        #expect(fixture.sources.guideURL() == nil)
    }

    @Test func guideImport() async throws {
        let fixture = try makeLibrary(texts: [IPTVFixtures.playlistURL: IPTVFixtures.playlistWithGuide])
        defer { fixture.cleanUp() }
        let library = fixture.library
        let revisionBefore = library.guideRevision

        await library.setPlaylistURL(IPTVFixtures.playlistURL)

        #expect(fixture.network.downloadCount == 1)
        #expect(library.guideStatus == .loaded(fixture.clock.now))
        #expect(library.guideRevision > revisionBefore)
        #expect(library.guideProgrammeCount == 8)
        #expect(library.state.lastGuideImport == fixture.clock.now)
        #expect(library.state.lastGuideSourceHash == IPTVLibrary.hash(IPTVFixtures.playlistGuideURL))

        let now = fixture.clock.now
        let result = await library.programmes(for: library.channels, in: DateInterval(start: now, duration: 2 * hour))
        let nfl = try #require(library.channels.first { $0.name == "NFL Network" })
        let nba = try #require(library.channels.first { $0.name == "NBA TV" })
        #expect(result[nfl.id]?.map(\.title) == ["NFL Network HD 1", "NFL Network HD 2"])
        #expect(result[nba.id]?.map(\.title) == ["NBA TV 1", "NBA TV 2"])
        #expect(result.count == 2)
    }

    @Test func refreshGuideIfStale() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guide: IPTVFixtures.customGuideURL)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        #expect(fixture.network.downloadCount == 1)

        fixture.clock.advance(11 * hour)
        await library.refreshGuideIfStale()
        #expect(fixture.network.downloadCount == 1)

        fixture.clock.advance(2 * hour)
        await library.refreshGuideIfStale()
        #expect(fixture.network.downloadCount == 2)
    }

    @Test func refreshGuideIfStaleRunsWhenTheURLChanged() async throws {
        let now = Date(timeIntervalSince1970: 1_791_200_000)
        let fresh = IPTVState(lastGuideImport: now, lastGuideSourceHash: IPTVLibrary.hash(IPTVFixtures.customGuideURL))
        let same = try makeLibrary(playlist: IPTVFixtures.playlistURL, guide: IPTVFixtures.customGuideURL, state: fresh, now: now)
        defer { same.cleanUp() }
        await same.library.refreshPlaylist()
        await same.library.refreshGuideIfStale()
        #expect(same.network.downloadCount == 0)

        let changed = IPTVState(lastGuideImport: now, lastGuideSourceHash: IPTVLibrary.hash(IPTVFixtures.playlistGuideURL))
        let other = try makeLibrary(playlist: IPTVFixtures.playlistURL, guide: IPTVFixtures.customGuideURL, state: changed, now: now)
        defer { other.cleanUp() }
        await other.library.refreshPlaylist()
        await other.library.refreshGuideIfStale()
        #expect(other.network.downloadCount == 1)
    }

    @Test func overridesApplyOnPlaylistRefreshWithoutImport() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guide: IPTVFixtures.customGuideURL)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        let redZone = try #require(library.channels.first { $0.name == "Red Zone" })
        #expect(library.epgIDs[redZone.id] == nil)

        // nbatv.us's programmes were imported (NBA TV matched it), so the mapping applies without a download.
        try fixture.overridesFile.save(["red zone": "NBATV.us"])
        let revision = library.guideRevision
        await library.refreshPlaylist()
        #expect(fixture.network.downloadCount == 1)
        #expect(library.epgIDs[redZone.id] == "nbatv.us")
        #expect(library.guideRevision > revision)
        let programmes = await library.programmes(for: [redZone], in: DateInterval(start: fixture.clock.now, duration: hour))
        #expect(programmes[redZone.id]?.first?.title == "NBA TV 1")
    }

    @Test func overrideTargetsAreImported() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guide: IPTVFixtures.customGuideURL,
                                      overrides: ["Red Zone": "NFL.RedZone.HD.us2"])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        let redZone = try #require(library.channels.first { $0.name == "Red Zone" })
        let programmes = await library.programmes(for: [redZone], in: DateInterval(start: fixture.clock.now, duration: hour))
        #expect(programmes[redZone.id]?.first?.title == "NFL RedZone 1")
        #expect(library.guideProgrammeCount == 12)
    }

    @Test func removeSource() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guide: IPTVFixtures.customGuideURL,
                                      state: IPTVState(lastChannelID: "id:nbatv.us", lastGroup: "Live Channels"))
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        #expect(try await fixture.store.programmeCount() > 0)

        await library.removeSource()
        #expect(library.hasPlaylist == false)
        #expect(library.channels.isEmpty)
        #expect(library.guideSource == .none)
        #expect(fixture.sources.playlistURL() == nil)
        #expect(fixture.sources.guideURL() == nil)
        #expect(try await fixture.store.programmeCount() == 0)
        #expect(library.guideProgrammeCount == 0)
        #expect(library.state == IPTVState())
        #expect(fixture.stateFile.load() == IPTVState())
    }

    @Test func nowNext() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guide: IPTVFixtures.customGuideURL)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        let nfl = try #require(library.channels.first { $0.name == "NFL Network" })
        let result = await library.nowNext(for: nfl, at: fixture.clock.now.addingTimeInterval(10 * 60))
        #expect(result.now?.title == "NFL Network HD 1")
        #expect(result.next?.title == "NFL Network HD 2")

        let redZone = try #require(library.channels.first { $0.name == "Red Zone" })
        let none = await library.nowNext(for: redZone, at: fixture.clock.now)
        #expect(none.now == nil && none.next == nil)
    }

    @Test func rememberedStateIsSaved() async throws {
        let fixture = try makeLibrary()
        defer { fixture.cleanUp() }
        fixture.library.rememberChannel("id:nbatv.us")
        fixture.library.rememberGroup("NBA Games")
        #expect(fixture.stateFile.load() == IPTVState(lastChannelID: "id:nbatv.us", lastGroup: "NBA Games"))
    }

    @Test func multiviewSnapshotRoundTrips() throws {
        let snapshot = MultiviewSnapshot(layout: .grid, slots: ["id:nbatv.us", nil, "id:nflnetwork.us", nil],
                                         focusedSlot: 2, isActive: true)
        let state = IPTVState(lastChannelID: "id:nbatv.us", multiview: snapshot)
        let fixture = try makeLibrary(state: state)
        defer { fixture.cleanUp() }
        #expect(fixture.stateFile.load() == state)
        #expect(fixture.library.state.multiview == snapshot)
    }

    @Test func badMultiviewSnapshotReadsAsNil() throws {
        let fixture = try makeLibrary()
        defer { fixture.cleanUp() }
        let json = """
        {"lastChannelID": "id:nbatv.us",
         "multiview": {"layout": "bogus", "slots": ["id:nbatv.us"], "focusedSlot": 0, "isActive": true}}
        """
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: fixture.directory.appending(path: IPTVState.fileName))
        let state = fixture.stateFile.load()
        #expect(state.multiview == nil)
        #expect(state.lastChannelID == "id:nbatv.us")
    }

    @Test func rememberMultiviewSaves() throws {
        let fixture = try makeLibrary()
        defer { fixture.cleanUp() }
        let snapshot = MultiviewSnapshot(layout: .onePlusFour, slots: ["id:nbatv.us", nil, nil, nil, nil],
                                         focusedSlot: 0, isActive: false)
        fixture.library.rememberMultiview(snapshot)
        #expect(fixture.stateFile.load().multiview == snapshot)
        fixture.library.rememberMultiview(nil)
        #expect(fixture.stateFile.load().multiview == nil)
    }
}
