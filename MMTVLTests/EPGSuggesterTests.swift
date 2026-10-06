import Foundation
import Testing
@testable import MMTVL

/// M6b L7.
struct EPGSuggesterTests {
    private func channel(_ name: String, tvgID: String? = nil) -> Channel {
        Channel(id: "name:" + name.lowercased(), number: 1, name: name, group: "G", tvgID: tvgID, tvgName: nil,
                logoURL: nil, streamURL: URL(string: "https://cdn/x.m3u8")!)
    }

    private func source(_ id: String, _ channels: [(String, String)]) -> EPGSourceChannels {
        EPGSourceChannels(sourceID: id, channels: channels.map { EPGChannel(id: $0.0.lowercased(), names: [$0.1]) })
    }

    /// Like FANDUEL1, plus ESPN.
    private var fanDuel: EPGSourceChannels {
        source("fd", [
            ("FanDuel.Sports.Network.Detroit.HD.us", "FanDuel Sports Network Detroit HD"),
            ("FanDuel.Sports.Network.Florida.us", "FanDuel Sports Network Florida"),
            ("FanDuel.Sports.Indiana.us", "FanDuel Sports Indiana"),
            ("FanDuel.TV.us", "FanDuel TV"),
            ("Fanduel.Racing.us", "Fanduel Racing"),
            ("ESPN.us", "ESPN"),
        ])
    }

    @Test func rareTokensWin() {
        let result = EPGSuggester.rank(channel("FanDuel Sports Network Indiana"), in: [fanDuel], limit: 30)
        #expect(result.first?.ref == EPGRef(sourceID: "fd", epgID: "fanduel.sports.indiana.us"))
        #expect(result.first?.name == "FanDuel Sports Indiana")
        #expect(result.allSatisfy { $0.score > 0 && $0.score <= 1 })
        // ESPN shares no token.
        #expect(!result.contains { $0.ref.epgID == "espn.us" })
        #expect(result.count == 5)
    }

    @Test func limit() {
        #expect(EPGSuggester.rank(channel("FanDuel Sports Network Indiana"), in: [fanDuel], limit: 2).count == 2)
    }

    @Test func ties() {
        let one = source("one", [("NBA.TV.Canada.us", "NBA TV Canada"), ("NBA.TV.us", "NBA TV"), ("NBA.TV.HD.us", "NBA TV HD")])
        let two = source("two", [("NBA.TV.us", "NBA TV")])
        let result = EPGSuggester.rank(channel("NBA TV"), in: [one, two], limit: 30)
        // Equal scores: fewer extra tokens, then guide order, then id.
        #expect(result.map { "\($0.ref.sourceID)/\($0.ref.epgID)" }
                == ["one/nba.tv.hd.us", "one/nba.tv.us", "two/nba.tv.us", "one/nba.tv.canada.us"])
    }

    @Test func tvgIDDropsItsLastToken() {
        let guide = source("g", [("nflnetwork.us2", "Something"), ("X.y", "US")])
        let result = EPGSuggester.rank(channel("NFL Net", tvgID: "nflnetwork.us"), in: [guide], limit: 30)
        #expect(result.map(\.ref.epgID) == ["nflnetwork.us2"])
    }

    @Test func suggestRunsOffTheMainActor() async {
        let result = await EPGSuggester.suggest(for: channel("FanDuel TV"), in: [fanDuel])
        #expect(result.first?.ref.epgID == "fanduel.tv.us")
    }
}
