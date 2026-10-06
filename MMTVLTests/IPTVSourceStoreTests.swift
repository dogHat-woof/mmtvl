import Foundation
import Testing
@testable import MMTVL

struct IPTVSourceStoreTests {
    private let playlist = URL(string: "https://provider.example/app2/token")!
    private let guide = URL(string: "https://guide.example/epg.xml.gz")!

    private let second = URL(string: "https://guide-source.online/guide-source/guide-source_FANDUEL1.xml.gz")!

    @Test func inMemoryRoundTrip() throws {
        let store = IPTVSourceStore.inMemory()
        #expect(store.playlistURL() == nil)
        #expect(store.guideURLs().isEmpty)
        try store.setPlaylistURL(playlist)
        try store.setGuideURLs([guide, second])
        #expect(store.playlistURL() == playlist)
        #expect(store.guideURLs() == [guide, second])
        try store.setGuideURLs([])
        #expect(store.guideURLs().isEmpty)
        try store.setGuideURLs([guide])
        try store.removeAll()
        #expect(store.playlistURL() == nil)
        #expect(store.guideURLs().isEmpty)
        #expect(IPTVSourceStore.inMemory(playlist: playlist).playlistURL() == playlist)
    }

    @Test func keychainRoundTrip() throws {
        let service = "dev.mmtvl.launcher.tests.iptv-\(UUID().uuidString)"
        let store = IPTVSourceStore.keychain(service: service)
        defer { try? store.removeAll() }

        #expect(store.playlistURL() == nil)
        try store.setPlaylistURL(playlist)
        try store.setGuideURLs([second, guide])
        #expect(store.playlistURL() == playlist)
        #expect(store.guideURLs() == [second, guide])
        try store.setGuideURLs([])
        #expect(store.guideURLs().isEmpty)
        #expect(try Keychain.string(account: IPTVSourceStore.guideListAccount, service: service) == nil)
        try store.removeAll()
        #expect(store.playlistURL() == nil)
    }

    @Test func legacyGuideMigrates() throws {
        let service = "dev.mmtvl.launcher.tests.iptv-\(UUID().uuidString)"
        let store = IPTVSourceStore.keychain(service: service)
        defer { try? store.removeAll() }

        try Keychain.set(guide.absoluteString, account: IPTVSourceStore.legacyGuideAccount, service: service)
        #expect(store.guideURLs() == [guide])
        try store.setGuideURLs([guide, second])
        #expect(try Keychain.string(account: IPTVSourceStore.legacyGuideAccount, service: service) == nil)
        #expect(store.guideURLs() == [guide, second])

        try store.setPlaylistURL(playlist)
        try Keychain.set(guide.absoluteString, account: IPTVSourceStore.legacyGuideAccount, service: service)
        try store.removeAll()
        for account in [IPTVSourceStore.playlistAccount, IPTVSourceStore.guideListAccount, IPTVSourceStore.legacyGuideAccount] {
            #expect(try Keychain.string(account: account, service: service) == nil)
        }
    }

    @Test func stateDecodesEmptyObject() throws {
        let state = try JSONDecoder().decode(IPTVState.self, from: Data("{}".utf8))
        #expect(state == IPTVState())
    }

    @Test func stateRoundTrips() throws {
        let state = IPTVState(lastChannelID: "id:nbatv.us", lastGroup: "Live Channels",
                              guideImports: ["abc": Date(timeIntervalSince1970: 1_000)])
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(IPTVState.self, from: data) == state)
    }
}
