import Foundation
import Testing
@testable import MMTVL

struct IPTVSourceStoreTests {
    private let playlist = URL(string: "https://provider.example/app2/token")!
    private let guide = URL(string: "https://guide.example/epg.xml.gz")!

    @Test func inMemoryRoundTrip() throws {
        let store = IPTVSourceStore.inMemory()
        #expect(store.playlistURL() == nil)
        #expect(store.guideURL() == nil)
        try store.setPlaylistURL(playlist)
        try store.setGuideURL(guide)
        #expect(store.playlistURL() == playlist)
        #expect(store.guideURL() == guide)
        try store.setGuideURL(nil)
        #expect(store.guideURL() == nil)
        try store.setGuideURL(guide)
        try store.removeAll()
        #expect(store.playlistURL() == nil)
        #expect(store.guideURL() == nil)
        #expect(IPTVSourceStore.inMemory(playlist: playlist).playlistURL() == playlist)
    }

    @Test func keychainRoundTrip() throws {
        let store = IPTVSourceStore.keychain(service: "dev.mmtvl.launcher.tests.iptv-\(UUID().uuidString)")
        defer { try? store.removeAll() }

        #expect(store.playlistURL() == nil)
        try store.setPlaylistURL(playlist)
        try store.setGuideURL(guide)
        #expect(store.playlistURL() == playlist)
        #expect(store.guideURL() == guide)
        try store.setGuideURL(nil)
        #expect(store.guideURL() == nil)
        try store.removeAll()
        #expect(store.playlistURL() == nil)
    }

    @Test func stateDecodesEmptyObject() throws {
        let state = try JSONDecoder().decode(IPTVState.self, from: Data("{}".utf8))
        #expect(state == IPTVState())
    }

    @Test func stateRoundTrips() throws {
        let state = IPTVState(lastChannelID: "id:nbatv.us", lastGroup: "Live Channels",
                              lastGuideImport: Date(timeIntervalSince1970: 1_000), lastGuideSourceHash: "abc")
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(IPTVState.self, from: data) == state)
    }
}
