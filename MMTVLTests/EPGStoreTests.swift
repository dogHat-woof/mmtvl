import Foundation
import Testing
@testable import MMTVL

struct EPGStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_791_200_000)

    private func programme(_ channel: String, _ startHours: Double, _ stopHours: Double, _ title: String) -> Programme {
        Programme(channelID: channel, start: t0.addingTimeInterval(startHours * 3600),
                  stop: t0.addingTimeInterval(stopHours * 3600), title: title)
    }

    @Test func overlapQueryAndGrouping() async throws {
        let store = try EPGStore.inMemory()
        try await store.replaceAll(channels: [EPGChannel(id: "a", names: ["A"]), EPGChannel(id: "b", names: ["B"])], programmes: [
            programme("a", -1, 0, "ends at start"),
            programme("a", -0.5, 0.5, "spans start"),
            programme("a", 0.5, 1.5, "inside"),
            programme("a", 2, 3, "after"),
            programme("b", 0, 1, "b inside"),
            programme("c", 0, 1, "c not asked"),
        ])

        let result = try await store.programmes(channelIDs: ["a", "b"], overlapping: DateInterval(start: t0, end: t0.addingTimeInterval(2 * 3600)))
        #expect(result["a"]?.map(\.title) == ["spans start", "inside"])
        #expect(result["b"]?.map(\.title) == ["b inside"])
        #expect(result["c"] == nil)
        #expect(try await store.programmeCount() == 6)
    }

    @Test func replaceAllReplaces() async throws {
        let store = try EPGStore.inMemory()
        try await store.replaceAll(channels: [EPGChannel(id: "a", names: ["A"])], programmes: [programme("a", 0, 1, "old")])
        try await store.replaceAll(channels: [EPGChannel(id: "b", names: ["B"])], programmes: [programme("b", 0, 1, "new")])
        #expect(try await store.channels().map(\.id) == ["b"])
        #expect(try await store.programmeCount() == 1)
        let result = try await store.programmes(channelIDs: ["a", "b"], overlapping: DateInterval(start: t0, duration: 3600))
        #expect(result.keys.sorted() == ["b"])
    }

    @Test func removeAll() async throws {
        let store = try EPGStore.inMemory()
        try await store.replaceAll(channels: [EPGChannel(id: "a", names: ["A"])], programmes: [programme("a", 0, 1, "x")])
        try await store.removeAll()
        #expect(try await store.channels().isEmpty)
        #expect(try await store.programmeCount() == 0)
    }

    @Test func channelsRoundTripWithNames() async throws {
        let store = try EPGStore.inMemory()
        let channels = [EPGChannel(id: "nfl.network.hd.us2", names: ["NFL Network HD", "NFL Network"]), EPGChannel(id: "x", names: [])]
        try await store.replaceAll(channels: channels, programmes: [])
        #expect(Set(try await store.channels()) == Set(channels))
    }

    @Test func programmeFieldsRoundTrip() async throws {
        let store = try EPGStore.inMemory()
        var original = programme("a", 0, 1, "Title")
        original.subtitle = "Sub"
        original.summary = "Desc"
        original.category = "Sports"
        original.episode = "S2 E1"
        try await store.replaceAll(channels: [], programmes: [original])
        let fetched = try #require(try await store.programmes(channelIDs: ["a"], overlapping: DateInterval(start: t0, duration: 60))["a"]?.first)
        #expect(fetched.id != nil)
        original.id = fetched.id
        #expect(fetched == original)
    }

    @Test func openOnDisk() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "EPGStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "guide.sqlite")
        let store = try EPGStore.open(at: url)
        try await store.replaceAll(channels: [EPGChannel(id: "a", names: ["A"])], programmes: [programme("a", 0, 1, "x")])
        #expect(try await EPGStore.open(at: url).programmeCount() == 1)

        // A corrupt file is replaced.
        let corruptURL = directory.appending(path: "corrupt.sqlite")
        try Data("not a database at all, just text that is long enough".utf8).write(to: corruptURL)
        #expect(try await EPGStore.open(at: corruptURL).programmeCount() == 0)
    }
}
