import Foundation
import Testing
@testable import MMTVL

struct EPGStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_791_200_000)

    private func programme(_ channel: String, _ startHours: Double, _ stopHours: Double, _ title: String) -> Programme {
        Programme(channelID: channel, start: t0.addingTimeInterval(startHours * 3600),
                  stop: t0.addingTimeInterval(stopHours * 3600), title: title)
    }

    private func ref(_ id: String, _ source: String = "s1") -> EPGRef {
        EPGRef(sourceID: source, epgID: id)
    }

    @Test func overlapQueryAndGrouping() async throws {
        let store = try EPGStore.inMemory()
        try await store.replaceSource("s1", channels: [EPGChannel(id: "a", names: ["A"]), EPGChannel(id: "b", names: ["B"])], programmes: [
            programme("a", -1, 0, "ends at start"),
            programme("a", -0.5, 0.5, "spans start"),
            programme("a", 0.5, 1.5, "inside"),
            programme("a", 2, 3, "after"),
            programme("b", 0, 1, "b inside"),
            programme("c", 0, 1, "c not asked"),
        ])

        let result = try await store.programmes(refs: [ref("a"), ref("b")], overlapping: DateInterval(start: t0, end: t0.addingTimeInterval(2 * 3600)))
        #expect(result[ref("a")]?.map(\.title) == ["spans start", "inside"])
        #expect(result[ref("b")]?.map(\.title) == ["b inside"])
        #expect(result[ref("c")] == nil)
        #expect(try await store.programmeCount() == 6)
    }

    @Test func replaceSourceReplaces() async throws {
        let store = try EPGStore.inMemory()
        try await store.replaceSource("s1", channels: [EPGChannel(id: "a", names: ["A"])], programmes: [programme("a", 0, 1, "old")])
        try await store.replaceSource("s1", channels: [EPGChannel(id: "b", names: ["B"])], programmes: [programme("b", 0, 1, "new")])
        #expect(try await store.channelsBySource()["s1"]?.map(\.id) == ["b"])
        #expect(try await store.programmeCount() == 1)
        let result = try await store.programmes(refs: [ref("a"), ref("b")], overlapping: DateInterval(start: t0, duration: 3600))
        #expect(result.keys.map(\.epgID) == ["b"])
    }

    @Test func removeAll() async throws {
        let store = try EPGStore.inMemory()
        try await store.replaceSource("s1", channels: [EPGChannel(id: "a", names: ["A"])], programmes: [programme("a", 0, 1, "x")])
        try await store.removeAll()
        #expect(try await store.channelsBySource().isEmpty)
        #expect(try await store.programmeCount() == 0)
    }

    @Test func channelsRoundTripWithNames() async throws {
        let store = try EPGStore.inMemory()
        let channels = [EPGChannel(id: "nfl.network.hd.us2", names: ["NFL Network HD", "NFL Network"]), EPGChannel(id: "x", names: [])]
        try await store.replaceSource("s1", channels: channels, programmes: [])
        let stored = try await store.channelsBySource()
        #expect(Set(stored["s1"] ?? []) == Set(channels.map { var c = $0; c.sourceID = "s1"; return c }))
    }

    @Test func programmeFieldsRoundTrip() async throws {
        let store = try EPGStore.inMemory()
        var original = programme("a", 0, 1, "Title")
        original.subtitle = "Sub"
        original.summary = "Desc"
        original.category = "Sports"
        original.episode = "S2 E1"
        try await store.replaceSource("s1", channels: [], programmes: [original])
        let fetched = try #require(try await store.programmes(refs: [ref("a")], overlapping: DateInterval(start: t0, duration: 60))[ref("a")]?.first)
        #expect(fetched.id != nil)
        original.id = fetched.id
        original.sourceID = "s1"
        #expect(fetched == original)
    }

    @Test func sourcesStaySeparate() async throws {
        let store = try EPGStore.inMemory()
        try await store.replaceSource("s1", channels: [EPGChannel(id: "a", names: ["A"])],
                                      programmes: [programme("a", 0, 1, "one a"), programme("b", 0, 1, "one b")])
        try await store.replaceSource("s2", channels: [EPGChannel(id: "a", names: ["A2"]), EPGChannel(id: "c", names: ["C"])],
                                      programmes: [programme("a", 0, 1, "two a")])
        // Replacing one guide leaves the other's rows.
        try await store.replaceSource("s1", channels: [EPGChannel(id: "a", names: ["A"])], programmes: [programme("a", 0, 1, "one a")])
        #expect(try await store.programmeCounts() == ["s1": 1, "s2": 1])
        #expect(try await store.programmeCount(for: ref("a", "s2")) == 1)
        #expect(try await store.programmeCount(for: ref("b", "s1")) == 0)
        let bySource = try await store.channelsBySource()
        #expect(bySource["s1"]?.map(\.id) == ["a"])
        #expect(Set(bySource["s2"]?.map(\.id) ?? []) == ["a", "c"])

        // Same EPG id in two guides: only the pair asked for.
        let window = DateInterval(start: t0, duration: 3600)
        let one = try await store.programmes(refs: [ref("a", "s2")], overlapping: window)
        #expect(Array(one.keys) == [ref("a", "s2")])
        #expect(one[ref("a", "s2")]?.map(\.title) == ["two a"])
        let both = try await store.programmes(refs: [ref("a", "s1"), ref("a", "s2")], overlapping: window)
        #expect(both[ref("a", "s1")]?.map(\.title) == ["one a"])
        #expect(both[ref("a", "s2")]?.map(\.title) == ["two a"])

        try await store.removeSources(keeping: ["s2"])
        #expect(try await store.programmeCounts() == ["s2": 1])
        #expect(try await store.channelsBySource().keys.sorted() == ["s2"])
        #expect(try await store.programmeCount() == 1)
    }

    @Test func openOnDisk() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "EPGStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "guide.sqlite")
        let store = try EPGStore.open(at: url)
        try await store.replaceSource("s1", channels: [EPGChannel(id: "a", names: ["A"])], programmes: [programme("a", 0, 1, "x")])
        #expect(try await EPGStore.open(at: url).programmeCount() == 1)

        // A corrupt file is replaced.
        let corruptURL = directory.appending(path: "corrupt.sqlite")
        try Data("not a database at all, just text that is long enough".utf8).write(to: corruptURL)
        #expect(try await EPGStore.open(at: corruptURL).programmeCount() == 0)
    }

    // MARK: M7f L12

    @Test func searchProgrammes() async throws {
        let store = try EPGStore.inMemory()
        try await store.replaceSource("s1", channels: [EPGChannel(id: "a", names: ["A"]), EPGChannel(id: "b", names: ["B"])], programmes: [
            programme("a", 2, 3, "NBA Basketball: Heat at Lakers"),
            programme("a", 0, 1, "nba basketball: Knicks at Celtics"),
            programme("a", -2, -1, "NBA Basketball: over"),
            programme("a", 25, 26, "NBA Basketball: tomorrow"),
            programme("b", 1, 2, "NBA Basketball: Bulls at Suns"),
            programme("b", 3, 4, "NBA Today"),
            programme("c", 1, 2, "NBA Basketball: not asked"),
            programme("a", 4, 5, "100% Basketball"),
        ])
        let day = DateInterval(start: t0, duration: 24 * 3600)
        // Every word, any case; only the refs given; only the interval; by start.
        let both = try await store.searchProgrammes(words: ["nba", "BASKETBALL"], refs: [ref("a"), ref("b")], interval: day, limit: 40)
        #expect(both.map(\.title) == ["nba basketball: Knicks at Celtics", "NBA Basketball: Bulls at Suns", "NBA Basketball: Heat at Lakers"])
        let onlyB = try await store.searchProgrammes(words: ["nba"], refs: [ref("b")], interval: day, limit: 40)
        #expect(onlyB.map(\.title) == ["NBA Basketball: Bulls at Suns", "NBA Today"])
        // A ref names a source too.
        #expect(try await store.searchProgrammes(words: ["nba"], refs: [ref("a", "s2")], interval: day, limit: 40).isEmpty)
        // The limit.
        let limited = try await store.searchProgrammes(words: ["nba"], refs: [ref("a"), ref("b")], interval: day, limit: 2)
        #expect(limited.map(\.title) == ["nba basketball: Knicks at Celtics", "NBA Basketball: Bulls at Suns"])
        // % and _ match literally.
        #expect(try await store.searchProgrammes(words: ["100%"], refs: [ref("a")], interval: day, limit: 40).map(\.title) == ["100% Basketball"])
        #expect(try await store.searchProgrammes(words: ["n_a"], refs: [ref("a")], interval: day, limit: 40).isEmpty)
        #expect(try await store.searchProgrammes(words: [], refs: [ref("a")], interval: day, limit: 40).isEmpty)
    }
}
