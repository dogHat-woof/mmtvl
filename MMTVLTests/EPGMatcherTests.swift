import Foundation
import Testing
@testable import MMTVL

struct EPGMatcherTests {
    private func channel(_ name: String, tvgID: String? = nil, tvgName: String? = nil) -> Channel {
        Channel(id: "name:" + name.lowercased(), number: 1, name: name, group: "G", tvgID: tvgID, tvgName: tvgName,
                logoURL: nil, streamURL: URL(string: "https://cdn/x.m3u8")!)
    }

    private func epg(_ id: String, _ names: String...) -> EPGChannel {
        EPGChannel(id: id.lowercased(), names: names)
    }

    @Test func normalization() {
        #expect(EPGMatcher.normalize("FanDuel Sports Network Detroit HD") == EPGMatcher.normalize("FanDuel Sports Network Detroit"))
        #expect(EPGMatcher.normalize("Telé 5") == EPGMatcher.normalize("Tele 5"))
        #expect(EPGMatcher.normalize("A&E") == EPGMatcher.normalize("A and E"))
        #expect(EPGMatcher.normalize("NBC Sports Bay Area+") == EPGMatcher.normalize("NBC Sports Bay Area Plus"))
        #expect(EPGMatcher.normalize("NBC Sports Bay Area+") != EPGMatcher.normalize("NBC Sports Bay Area HD"))
    }

    @Test func idMatchIgnoresCase() {
        let nba = channel("NBA TV", tvgID: "NBATV.us")
        #expect(EPGMatcher.match([nba], to: [epg("nbatv.us", "Something else")]) == [nba.id: "nbatv.us"])
    }

    @Test func nameFallbackWhenIDDoesNotMatch() {
        let nfl = channel("NFL Network", tvgID: "nflnetwork.us", tvgName: "NFL Network")
        let result = EPGMatcher.match([nfl], to: [epg("NFL.Network.HD.us2", "NFL Network HD")])
        #expect(result == [nfl.id: "nfl.network.hd.us2"])
    }

    @Test func noMatchIsAbsent() {
        let result = EPGMatcher.match([channel("FanDuel Sports Network Indiana")], to: [epg("x", "ESPN")])
        #expect(result.isEmpty)
    }

    @Test func firstEPGChannelWithTheSameNameWins() {
        let espn = channel("ESPN")
        let result = EPGMatcher.match([espn], to: [epg("ESPN.first", "ESPN"), epg("ESPN.second", "ESPN HD")])
        #expect(result == [espn.id: "espn.first"])
    }

    @Test func plusAndAmpersand() {
        let plus = channel("NBC Sports Bay Area+")
        let ae = channel("A&E")
        let result = EPGMatcher.match([plus, ae], to: [
            epg("NBC.Sports.Bay.Area.HD.us2", "NBC Sports Bay Area HD"),
            epg("NBC.Sports.Bay.Area.Plus.us2", "NBC Sports Bay Area Plus"),
            epg("AE.us2", "A and E"),
        ])
        #expect(result[plus.id] == "nbc.sports.bay.area.plus.us2")
        #expect(result[ae.id] == "ae.us2")
    }

    @Test func overrides() {
        let guide = [epg("nbatv.us", "NBA TV"), epg("Marquee.Sports.Network.HD.us2", "Marquee Sports Network HD"),
                     epg("CBS.Sports.Network.HD.us2", "CBS Sports Network HD"), epg("CBS.News.us", "CBS")]

        // A name key wins over a tvg-id match.
        let nba = channel("NBA TV", tvgID: "nbatv.us")
        #expect(EPGMatcher.match([nba], to: guide, overrides: ["NBA TV": "marquee.sports.network.hd.us2"])[nba.id]
                == "marquee.sports.network.hd.us2")

        // A tvg-id key works; keys and values are case-insensitive.
        let cbs = channel("CBS", tvgID: "cbssportsnetworkusa.us")
        #expect(EPGMatcher.match([cbs], to: guide, overrides: ["CBSSPORTSNETWORKUSA.US": "CBS.Sports.Network.HD.us2"])[cbs.id]
                == "cbs.sports.network.hd.us2")
        let marquee = channel("Marquee Network")
        #expect(EPGMatcher.match([marquee], to: guide, overrides: ["marquee NETWORK": "MARQUEE.Sports.Network.HD.US2"])[marquee.id]
                == "marquee.sports.network.hd.us2")

        // A target missing from the guide falls through to the normal rules.
        #expect(EPGMatcher.match([nba], to: guide, overrides: ["NBA TV": "Gone.us2"])[nba.id] == "nbatv.us")
    }

    @Test func noFuzzyMatching() {
        let redZone = channel("Red Zone")
        let cbs = channel("CBS")
        let result = EPGMatcher.match([redZone, cbs], to: [epg("Red.TV.rs", "Red TV"), epg("CBS.News.us", "CBS News")])
        #expect(result[redZone.id] == nil)
        #expect(result[cbs.id] == nil)
    }

    // MARK: - Several guides (M6b L3)

    private func source(_ id: String, _ channels: EPGChannel...) -> EPGSourceChannels {
        EPGSourceChannels(sourceID: id, channels: channels)
    }

    @Test func emptyOverrideMeansNoGuide() {
        let nba = channel("NBA TV", tvgID: "nbatv.us")
        #expect(EPGMatcher.match([nba], to: [epg("nbatv.us", "NBA TV")], overrides: ["NBA TV": ""]).isEmpty)
        #expect(EPGMatcher.match([nba], to: [epg("nbatv.us", "NBA TV")], overrides: ["NBATV.us": ""]).isEmpty)
    }

    @Test func idInALowerGuideBeatsANameInAHigherOne() {
        let nba = channel("NBA TV", tvgID: "nbatv.us")
        let result = EPGMatcher.match([nba], sources: [source("one", epg("NBA.TV.HD.us2", "NBA TV")),
                                                       source("two", epg("nbatv.us", "Something"))])
        #expect(result[nba.id] == EPGRef(sourceID: "two", epgID: "nbatv.us"))
    }

    @Test func sameRuleHigherGuideWins() {
        let espn = channel("ESPN")
        let byName = EPGMatcher.match([espn], sources: [source("one", epg("ESPN.one", "ESPN")), source("two", epg("ESPN.two", "ESPN"))])
        #expect(byName[espn.id] == EPGRef(sourceID: "one", epgID: "espn.one"))

        let nba = channel("NBA TV", tvgID: "nbatv.us")
        let byID = EPGMatcher.match([nba], sources: [source("one", epg("nbatv.us")), source("two", epg("nbatv.us"))])
        #expect(byID[nba.id] == EPGRef(sourceID: "one", epgID: "nbatv.us"))
    }

    @Test func overrideTargetInTheSecondGuide() {
        let redZone = channel("Red Zone")
        let result = EPGMatcher.match([redZone], sources: [source("one", epg("ESPN.one", "ESPN")),
                                                           source("two", epg("NFL.RedZone.us", "NFL RedZone"))],
                                      overrides: ["Red Zone": "NFL.RedZone.us"])
        #expect(result[redZone.id] == EPGRef(sourceID: "two", epgID: "nfl.redzone.us"))
    }

    @Test func tokens() {
        #expect(EPGMatcher.tokens("NBC Sports Bay Area+ HD") == ["nbc", "sports", "bay", "area", "plus"])
        #expect(EPGMatcher.tokens("NBA TV TV") == ["nba", "tv"])
        #expect(EPGMatcher.normalize("NBA TV TV") == "nbatvtv")
    }

    // MARK: - M7j L12

    /// An antenna channel's override is under its id (`antenna:5.1`), which wins over one under its name (names repeat
    /// on the tuner); a playlist channel's key is its name, as before.
    @Test func overrideKeyComesBeforeName() {
        let antenna = Channel(id: "antenna:5.1", number: 9, name: "WYGA-CD", group: "Antenna", tvgID: nil, tvgName: nil,
                              logoURL: nil, streamURL: URL(string: "http://10.0.0.9:5004/auto/v5.1")!,
                              source: .antenna(deviceID: "1234ABCD"), guideNumber: "5.1")
        let other = Channel(id: "antenna:26.1", number: 10, name: "WYGA-CD", group: "Antenna", tvgID: nil, tvgName: nil,
                            logoURL: nil, streamURL: URL(string: "http://10.0.0.9:5004/auto/v26.1")!,
                            source: .antenna(deviceID: "1234ABCD"), guideNumber: "26.1")
        let guide = [epg("by.id", "Something"), epg("by.name", "Else")]
        let overrides = ["ANTENNA:5.1": "BY.ID", "wyga-cd": "by.name"]
        let result = EPGMatcher.match([antenna, other], to: guide, overrides: overrides)
        #expect(result == [antenna.id: "by.id", other.id: "by.name"])

        let playlist = channel("NBA TV", tvgID: "nbatv.us")
        #expect(playlist.overrideKey == "NBA TV")
        #expect(EPGMatcher.match([playlist], to: guide, overrides: ["nba tv": "by.id"]) == [playlist.id: "by.id"])
    }
}
