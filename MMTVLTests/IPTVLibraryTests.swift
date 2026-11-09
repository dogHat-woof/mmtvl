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
        #expect(library.guideSources.isEmpty)
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
        #expect(library.guideSources.isEmpty)
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

    /// M7f L5: the timer's check. The playlist first (so the guide imports with channels), then the guide.
    @Test func refreshIfStaleFetchesThePlaylistBeforeTheGuide() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshIfStale()
        #expect(fixture.network.fetchCount == 1)
        #expect(fixture.network.downloadCount == 1)
        #expect(!library.channels.isEmpty)
        #expect(library.guideProgrammeCount > 0)

        // Fresh: nothing is fetched.
        await library.refreshIfStale()
        #expect(fixture.network.fetchCount == 1)
        #expect(fixture.network.downloadCount == 1)

        // 15 minutes later the playlist is stale, the guide isn't.
        fixture.clock.advance(IPTVLibrary.autoRefreshInterval)
        await library.refreshIfStale()
        #expect(fixture.network.fetchCount == 2)
        #expect(fixture.network.downloadCount == 1)
    }

    @Test func aChangedLineupIsReported() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL)
        defer { fixture.cleanUp() }
        let library = fixture.library
        var changes = 0
        library.onLineupChange = { changes += 1 }
        await library.refreshPlaylist()
        #expect(changes == 1)
        // The same playlist again: no change.
        await library.refreshPlaylist()
        #expect(changes == 1)
    }

    @Test func playlistGuidesUntilOneIsPasted() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL,
                                      texts: [IPTVFixtures.playlistURL: IPTVFixtures.playlistWithGuide])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        #expect(library.guideSources == [GuideSource(url: IPTVFixtures.playlistGuideURL, isFromPlaylist: true)])
        #expect(fixture.network.downloadCount == 1)
        let playlistID = IPTVLibrary.hash(IPTVFixtures.playlistGuideURL)
        let customID = IPTVLibrary.hash(IPTVFixtures.customGuideURL)

        // The first pasted guide replaces the playlist's.
        await library.addGuideURL(IPTVFixtures.customGuideURL)
        #expect(library.guideSources == [GuideSource(url: IPTVFixtures.customGuideURL, isFromPlaylist: false)])
        #expect(fixture.sources.guideURLs() == [IPTVFixtures.customGuideURL])
        #expect(fixture.network.downloadCount == 2)
        #expect(try await fixture.store.programmeCounts().keys.sorted() == [customID])
        #expect(library.state.guideImports.keys.sorted() == [customID])

        // Removing it brings them back (imported again: their rows were pruned).
        await library.removeGuideSource(customID)
        #expect(library.guideSources == [GuideSource(url: IPTVFixtures.playlistGuideURL, isFromPlaylist: true)])
        #expect(fixture.sources.guideURLs().isEmpty)
        #expect(fixture.network.downloadCount == 3)
        #expect(try await fixture.store.programmeCounts().keys.sorted() == [playlistID])
        #expect(library.guideStatus == .loaded(fixture.clock.now))
    }

    /// M7f L4: the playlist's guide instead of the pasted one; the pasted URL is kept.
    @Test func usePlaylistGuideKeepsPastedGuides() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL],
                                      texts: [IPTVFixtures.playlistURL: IPTVFixtures.playlistWithGuide])
        defer { fixture.cleanUp() }
        let library = fixture.library
        let playlistGuide = GuideSource(url: IPTVFixtures.playlistGuideURL, isFromPlaylist: true)
        let pastedGuide = GuideSource(url: IPTVFixtures.customGuideURL, isFromPlaylist: false)
        await library.refreshAll()
        #expect(library.playlistNamesGuide)
        #expect(library.guideSources == [pastedGuide])
        #expect(fixture.network.downloadCount == 1)

        await library.applyUsePlaylistGuide(true)
        #expect(library.guideSources == [playlistGuide])
        #expect(library.customGuideSources == [pastedGuide])
        #expect(fixture.sources.guideURLs() == [IPTVFixtures.customGuideURL])
        #expect(fixture.network.downloadCount == 2)
        #expect(try await fixture.store.programmeCounts().keys.sorted() == [playlistGuide.id])
        #expect(library.state.guideImports.keys.sorted() == [playlistGuide.id])

        // Back to the pasted guide: imported again (its rows were pruned).
        await library.applyUsePlaylistGuide(false)
        #expect(library.guideSources == [pastedGuide])
        #expect(fixture.network.downloadCount == 3)
        #expect(try await fixture.store.programmeCounts().keys.sorted() == [pastedGuide.id])
    }

    /// M7f L4: without a playlist guide the setting changes nothing.
    @Test func usePlaylistGuideWithoutOneKeepsPastedGuides() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        let pastedGuide = GuideSource(url: IPTVFixtures.customGuideURL, isFromPlaylist: false)
        await library.refreshAll()
        #expect(library.playlistNamesGuide == false)
        #expect(fixture.network.downloadCount == 1)

        await library.applyUsePlaylistGuide(true)
        #expect(library.usePlaylistGuide)
        #expect(library.guideSources == [pastedGuide])
        #expect(fixture.network.downloadCount == 1)
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
        #expect(library.state.guideImports == [IPTVLibrary.hash(IPTVFixtures.playlistGuideURL): fixture.clock.now])

        let now = fixture.clock.now
        let result = await library.programmes(for: library.channels, in: DateInterval(start: now, duration: 2 * hour))
        let nfl = try #require(library.channels.first { $0.name == "NFL Network" })
        let nba = try #require(library.channels.first { $0.name == "NBA TV" })
        #expect(result[nfl.id]?.map(\.title) == ["NFL Network HD 1", "NFL Network HD 2"])
        #expect(result[nba.id]?.map(\.title) == ["NBA TV 1", "NBA TV 2"])
        #expect(result.count == 2)
    }

    @Test func refreshGuideIfStale() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL])
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
        let fresh = IPTVState(guideImports: [IPTVLibrary.hash(IPTVFixtures.customGuideURL): now])
        let same = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL], state: fresh, now: now)
        defer { same.cleanUp() }
        await same.library.refreshPlaylist()
        await same.library.refreshGuideIfStale()
        #expect(same.network.downloadCount == 0)

        let changed = IPTVState(guideImports: [IPTVLibrary.hash(IPTVFixtures.playlistGuideURL): now])
        let other = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL], state: changed, now: now)
        defer { other.cleanUp() }
        await other.library.refreshPlaylist()
        await other.library.refreshGuideIfStale()
        #expect(other.network.downloadCount == 1)
    }

    @Test func overridesApplyOnPlaylistRefreshWithoutImport() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        let redZone = try #require(library.channels.first { $0.name == "Red Zone" })
        #expect(library.epgMatches[redZone.id] == nil)

        // nbatv.us's programmes were imported (NBA TV matched it), so the mapping applies without a download.
        try fixture.overridesFile.save(["red zone": "NBATV.us"])
        let revision = library.guideRevision
        await library.refreshPlaylist()
        #expect(fixture.network.downloadCount == 1)
        #expect(library.epgMatches[redZone.id]?.epgID == "nbatv.us")
        #expect(library.guideRevision > revision)
        let programmes = await library.programmes(for: [redZone], in: DateInterval(start: fixture.clock.now, duration: hour))
        #expect(programmes[redZone.id]?.first?.title == "NBA TV 1")
    }

    @Test func overrideTargetsAreImported() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL],
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
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL],
                                      state: IPTVState(lastChannelID: "id:nbatv.us", lastGroup: "Live Channels"))
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        #expect(try await fixture.store.programmeCount() > 0)

        await library.removeSource()
        #expect(library.hasPlaylist == false)
        #expect(library.channels.isEmpty)
        #expect(library.guideSources.isEmpty)
        #expect(library.guideSourceInfo.isEmpty)
        #expect(fixture.sources.playlistURL() == nil)
        #expect(fixture.sources.guideURLs().isEmpty)
        #expect(try await fixture.store.programmeCount() == 0)
        #expect(library.guideProgrammeCount == 0)
        #expect(library.state == IPTVState())
        #expect(fixture.stateFile.load() == IPTVState())
    }

    // MARK: - Several guides (M6b)

    private var customID: String { IPTVLibrary.hash(IPTVFixtures.customGuideURL) }
    private var secondID: String { IPTVLibrary.hash(IPTVFixtures.secondGuideURL) }

    private func twoGuides() async throws -> LibraryFixture {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL,
                                      guides: [IPTVFixtures.customGuideURL, IPTVFixtures.secondGuideURL])
        await fixture.library.refreshAll()
        return fixture
    }

    private func channel(_ name: String, in library: IPTVLibrary) throws -> Channel {
        try #require(library.channels.first { $0.name == name })
    }

    @Test func twoGuidesMatchByPriority() async throws {
        let fixture = try await twoGuides()
        defer { fixture.cleanUp() }
        let library = fixture.library
        #expect(fixture.network.downloadCount == 2)
        #expect(library.guideSources.map(\.id) == [customID, secondID])
        let matches = library.epgMatches
        #expect(matches[try channel("Red Zone", in: library).id] == EPGRef(sourceID: secondID, epgID: "redzone.alt.us"))
        #expect(matches[try channel("NBA TV", in: library).id] == EPGRef(sourceID: customID, epgID: "nbatv.us"))
        #expect(matches[try channel("NFL Network", in: library).id] == EPGRef(sourceID: customID, epgID: "nfl.network.hd.us2"))
        #expect(library.guideSourceInfo[customID]?.matchedChannels == 2)
        #expect(library.guideSourceInfo[secondID]?.matchedChannels == 1)
        #expect(library.guideSourceInfo[customID]?.status == .loaded(fixture.clock.now))
        #expect(library.matchedChannelCount == 3)
        #expect(Set(library.state.guideImports.keys) == [customID, secondID])
        #expect(library.guideProgrammeCount == (library.guideSourceInfo[customID]?.programmeCount ?? 0)
                + (library.guideSourceInfo[secondID]?.programmeCount ?? 0))
    }

    @Test func moveGuideRematchesWithoutDownload() async throws {
        let fixture = try await twoGuides()
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.moveGuideSource(secondID, by: -1)
        #expect(library.guideSources.map(\.id) == [secondID, customID])
        #expect(fixture.sources.guideURLs() == [IPTVFixtures.secondGuideURL, IPTVFixtures.customGuideURL])
        // Rule 2 (tvg-id) in the lower guide beats rule 3 (name) in the higher one.
        #expect(library.epgMatches[try channel("NBA TV", in: library).id]?.sourceID == customID)
        #expect(fixture.network.downloadCount == 2)
        // Past the end does nothing.
        await library.moveGuideSource(secondID, by: -1)
        #expect(library.guideSources.map(\.id) == [secondID, customID])
    }

    @Test func removeGuideRematchesWithoutDownload() async throws {
        let fixture = try await twoGuides()
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.removeGuideSource(customID)
        #expect(fixture.network.downloadCount == 2)
        let nba = try channel("NBA TV", in: library)
        #expect(library.epgMatches[nba.id] == EPGRef(sourceID: secondID, epgID: "nba.tv.alt.us"))
        #expect(library.epgMatches[try channel("Red Zone", in: library).id]?.sourceID == secondID)
        let programmes = await library.programmes(for: [nba], in: DateInterval(start: fixture.clock.now, duration: hour))
        #expect(programmes[nba.id]?.first?.title == "NBA TV alt 1")
        #expect(try await fixture.store.programmeCounts()[customID] == nil)
        #expect(library.guideSourceInfo[customID] == nil)
        #expect(library.state.guideImports[customID] == nil)
    }

    @Test func onlyStaleGuidesDownload() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        #expect(fixture.network.downloadCount == 1)
        fixture.clock.advance(13 * hour)
        await library.addGuideURL(IPTVFixtures.secondGuideURL)
        #expect(fixture.network.downloadCount == 2)
        await library.refreshGuideIfStale()
        #expect(fixture.network.downloadCount == 3)    // only custom
        await library.refreshGuideIfStale()
        #expect(fixture.network.downloadCount == 3)
    }

    @Test func failingGuide() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL,
                                      guides: [IPTVFixtures.customGuideURL, IPTVFixtures.secondGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        fixture.network.setError(IPTVNetworkError.http(500), for: IPTVFixtures.secondGuideURL)
        await library.refreshAll()
        #expect(library.guideSourceInfo[secondID]?.status == .failed("Server error (HTTP 500)"))
        #expect(library.guideSourceInfo[customID]?.status == .loaded(fixture.clock.now))
        #expect(library.guideStatus == .loaded(fixture.clock.now))

        fixture.network.setError(IPTVNetworkError.http(404), for: IPTVFixtures.customGuideURL)
        await library.refreshGuide()
        #expect(library.guideStatus == .failed("Server error (HTTP 404)"))
        // The failed guide keeps its rows.
        #expect(library.epgMatches[try channel("NBA TV", in: library).id]?.sourceID == customID)
    }

    @Test func requestsDuringARunJoinIt() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL,
                                      guides: [IPTVFixtures.customGuideURL, IPTVFixtures.secondGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshPlaylist()
        var runs = 0
        var last = library.guideStatus
        library.onStatusChange = {
            if library.guideStatus == .loading, last != .loading { runs += 1 }
            last = library.guideStatus
        }
        let run = Task { await library.refreshGuide(sourceIDs: [customID]) }
        await Task.yield()
        await library.refreshGuide(sourceIDs: [secondID])    // returns at once: the run picks it up
        await run.value
        #expect(runs == 1)
        #expect(fixture.network.downloadCount == 2)
        #expect(Set(library.state.guideImports.keys) == [customID, secondID])
        #expect(library.guideStatus == .loaded(fixture.clock.now))
    }

    @Test func addGuideProblems() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        #expect(library.guideAddProblem(IPTVFixtures.customGuideURL) == .duplicate)
        #expect(library.guideAddProblem(IPTVFixtures.secondGuideURL) == nil)
        for n in 2...IPTVLibrary.maxGuideSources {
            await library.addGuideURL(URL(string: "https://guide.example/\(n).xml")!)
        }
        #expect(library.customGuideCount == IPTVLibrary.maxGuideSources)
        #expect(library.guideAddProblem(IPTVFixtures.secondGuideURL) == .full)
        #expect(library.guideAddProblem(IPTVFixtures.customGuideURL) == .duplicate)
    }

    // MARK: - Favorites and hiding (M6b L5)

    @Test func favoritesAndHidingSaveAndUpdateTheLineup() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshPlaylist()
        var statusChanges = 0
        library.onStatusChange = { statusChanges += 1 }

        library.setFavorite("id:nbatv.us", true)
        library.setFavorite("name:red zone", true)
        library.setFavorite("id:nflnetwork.us", true)
        #expect(library.isFavorite("id:nbatv.us"))
        #expect(library.lineup.favorites.map(\.name) == ["NBA TV", "Red Zone", "NFL Network"])
        #expect(fixture.preferencesFile.load().favorites == ["id:nbatv.us", "name:red zone", "id:nflnetwork.us"])
        #expect(statusChanges == 3)

        library.moveFavorite("name:red zone", by: -1)
        #expect(library.lineup.favorites.map(\.name) == ["Red Zone", "NBA TV", "NFL Network"])
        library.moveFavorite("name:red zone", by: -1)    // past the start
        library.moveFavorite("id:nflnetwork.us", by: 1)   // past the end
        #expect(fixture.preferencesFile.load().favorites == ["name:red zone", "id:nbatv.us", "id:nflnetwork.us"])

        library.setFavorite("id:nbatv.us", false)
        #expect(library.lineup.favorites.map(\.name) == ["Red Zone", "NFL Network"])

        library.setChannelHidden("name:red zone", true)
        #expect(!library.lineup.isVisible("name:red zone"))
        #expect(fixture.preferencesFile.load().hiddenChannels == ["name:red zone"])
        library.setGroupHidden("NBA Games", true)
        #expect(library.lineup.groups == ["Favorites", "Live Channels"])
        #expect(fixture.preferencesFile.load().hiddenGroups == ["NBA Games"])
        library.setGroupHidden("NBA Games", false)
        library.setChannelHidden("name:red zone", false)
        #expect(library.lineup.groups == ["Favorites", "All Channels", "Live Channels", "NBA Games"])
        #expect(fixture.preferencesFile.load() == ChannelPreferences(favorites: ["name:red zone", "id:nflnetwork.us"]))
    }

    @Test func removeSourceKeepsPreferences() async throws {
        let preferences = ChannelPreferences(favorites: ["id:nbatv.us"], hiddenGroups: ["NBA Games"])
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, preferences: preferences)
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshPlaylist()
        #expect(library.lineup.groups == ["Favorites", "Live Channels"])
        await library.removeSource()
        #expect(library.preferences == preferences)
        #expect(fixture.preferencesFile.load() == preferences)
        #expect(library.lineup.groups.isEmpty)
    }

    // MARK: - Match Guide (M6b L6, L9)

    @Test func manualMatchReimportsWhenItsProgrammesWerentKept() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        let redZone = try channel("Red Zone", in: library)
        #expect(library.epgMatches[redZone.id] == nil)

        await library.setGuideMatch(.epg(EPGRef(sourceID: customID, epgID: "nfl.redzone.hd.us2")), for: redZone)
        #expect(fixture.overridesFile.load() == ["Red Zone": "nfl.redzone.hd.us2"])
        #expect(fixture.network.downloadCount == 2)
        let programmes = await library.programmes(for: [redZone], in: DateInterval(start: fixture.clock.now, duration: hour))
        #expect(programmes[redZone.id]?.first?.title == "NFL RedZone 1")
    }

    @Test func noGuideAndAutomatic() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        let nba = try channel("NBA TV", in: library)

        await library.setGuideMatch(.none, for: nba)
        #expect(fixture.overridesFile.load() == ["NBA TV": ""])
        #expect(library.epgMatches[nba.id] == nil)
        #expect(await library.guideMatchOptions(for: nba).choice == GuideMatchChoice.none)

        // Automatic removes keys for the name and the tvg-id, in any case. Its programmes are stored: no download.
        try fixture.overridesFile.save(["NBATV.us": "x", "nba tv": ""])
        await library.setGuideMatch(.automatic, for: nba)
        #expect(fixture.overridesFile.load().isEmpty)
        #expect(library.epgMatches[nba.id] == EPGRef(sourceID: customID, epgID: "nbatv.us"))
        #expect(fixture.network.downloadCount == 1)
    }

    @Test func automaticReimportsWhenNoGuideKeptNothing() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL],
                                      overrides: ["NBA TV": ""])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        let nba = try channel("NBA TV", in: library)
        #expect(try await fixture.store.programmeCount(for: EPGRef(sourceID: customID, epgID: "nbatv.us")) == 0)

        await library.setGuideMatch(.automatic, for: nba)
        #expect(fixture.network.downloadCount == 2)
        let programmes = await library.programmes(for: [nba], in: DateInterval(start: fixture.clock.now, duration: hour))
        #expect(programmes[nba.id]?.first?.title == "NBA TV 1")
    }

    @Test func matchOptions() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL])
        defer { fixture.cleanUp() }
        let library = fixture.library
        await library.refreshAll()
        let nfl = try channel("NFL Network", in: library)
        let current = EPGRef(sourceID: customID, epgID: "nfl.network.hd.us2")
        #expect(library.guideLabel(for: current) == "custom")

        let options = await library.guideMatchOptions(for: nfl)
        #expect(options.choice == .automatic)
        #expect(options.current == current)
        #expect(options.candidates.first == GuideCandidate(ref: current, name: "NFL Network HD", sourceLabel: "custom"))
        #expect(options.candidates.filter { $0.ref == current }.count == 1)

        await library.setGuideMatch(.epg(current), for: nfl)
        #expect(await library.guideMatchOptions(for: nfl).choice == .epg(current))
    }

    @Test func nowNext() async throws {
        let fixture = try makeLibrary(playlist: IPTVFixtures.playlistURL, guides: [IPTVFixtures.customGuideURL])
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
        #expect(fixture.stateFile.load() == IPTVState(lastChannelID: "id:nbatv.us", lastGroup: "NBA Games",
                                                      recentChannelIDs: ["id:nbatv.us"]))
    }

    // MARK: Recent channels (M7 L13)

    @Test func recentChannelsAreMostRecentFirstAndCapped() async throws {
        let fixture = try makeLibrary()
        defer { fixture.cleanUp() }
        let library = fixture.library
        for n in 1...12 { library.rememberChannel("id:\(n)") }
        #expect(library.state.recentChannelIDs == (3...12).reversed().map { "id:\($0)" })
        library.rememberChannel("id:5")
        #expect(library.state.recentChannelIDs.first == "id:5")
        #expect(library.state.recentChannelIDs.count == 10)
        #expect(library.state.recentChannelIDs.filter { $0 == "id:5" }.count == 1)
        #expect(fixture.stateFile.load().recentChannelIDs == library.state.recentChannelIDs)
    }

    @Test func rememberingTheLastChannelStillMovesItToTheFront() throws {
        let fixture = try makeLibrary(state: IPTVState(lastChannelID: "id:a", recentChannelIDs: ["id:b", "id:a"]))
        defer { fixture.cleanUp() }
        fixture.library.rememberChannel("id:a")
        #expect(fixture.library.state.recentChannelIDs == ["id:a", "id:b"])
        #expect(fixture.stateFile.load().recentChannelIDs == ["id:a", "id:b"])
    }

    @Test func olderStateFilesHaveNoRecents() throws {
        let state = try JSONDecoder().decode(IPTVState.self, from: Data(#"{"lastChannelID": "id:a"}"#.utf8))
        #expect(state.recentChannelIDs.isEmpty)
    }

    @Test func oldGuideKeysLoad() throws {
        let fixture = try makeLibrary()
        defer { fixture.cleanUp() }
        let json = """
        {"lastChannelID": "id:nbatv.us", "lastGroup": "NBA Games",
         "lastGuideImport": 700000000, "lastGuideSourceHash": "abc"}
        """
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: fixture.directory.appending(path: IPTVState.fileName))
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
