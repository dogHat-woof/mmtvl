import Foundation
import Testing
@testable import MMTVL

struct M3UParserTests {
    /// Shaped like the user's provider: bare header, sports channels, game events, an empty tvg-id.
    static let userShaped = """
    #EXTM3U
    #EXTINF:0 tvg-id="nbatv.us" tvg-logo="https://x/y.png" tvg-name="NBA TV" group-title="Live Channels",NBA TV
    https://cdn.example/abc/channel/1/chunks.m3u8
    #EXTINF:0 tvg-type="movie" tvg-id="Philadelphia @ Tampa Bay-A" group-title="NHL Games",Philadelphia @ Tampa Bay
    https://cdn.example/abc/perdias/2/chunks.m3u8
    #EXTINF:0 tvg-id="" tvg-name="Red Zone2" group-title="Live Channels",Red Zone2
    https://cdn.example/abc/channel/3/chunks.m3u8
    """

    @Test func parsesUserShapedPlaylist() throws {
        let playlist = try M3UParser.parse(Self.userShaped)
        #expect(playlist.guideURLs.isEmpty)
        #expect(playlist.entries.count == 3)

        let nba = playlist.entries[0]
        #expect(nba.name == "NBA TV")
        #expect(nba.tvgID == "nbatv.us")
        #expect(nba.tvgName == "NBA TV")
        #expect(nba.logo == "https://x/y.png")
        #expect(nba.group == "Live Channels")
        #expect(nba.url == "https://cdn.example/abc/channel/1/chunks.m3u8")

        let game = playlist.entries[1]
        #expect(game.name == "Philadelphia @ Tampa Bay")
        #expect(game.attributes["tvg-type"] == "movie")
        #expect(game.tvgID == "Philadelphia @ Tampa Bay-A")
        #expect(game.group == "NHL Games")

        let redZone = playlist.entries[2]
        #expect(redZone.tvgID == nil)
        #expect(redZone.attributes["tvg-id"] == "")
        #expect(redZone.name == "Red Zone2")
    }

    @Test func nameMayContainCommas() throws {
        let playlist = try M3UParser.parse("""
        #EXTM3U
        #EXTINF:-1 tvg-id="a",News, Weather
        http://a/1
        """)
        #expect(playlist.entries.first?.name == "News, Weather")
    }

    @Test func commaInsideQuotedAttribute() throws {
        let playlist = try M3UParser.parse("""
        #EXTM3U
        #EXTINF:-1 tvg-name="A, B" group-title="G",Name
        http://a/1
        """)
        let entry = try #require(playlist.entries.first)
        #expect(entry.tvgName == "A, B")
        #expect(entry.name == "Name")
        #expect(entry.group == "G")
    }

    @Test func crlfAndBOM() throws {
        let text = "\u{FEFF}#EXTM3U\r\n#EXTINF:-1 tvg-id=\"x\",Channel X\r\nhttp://a/x.m3u8\r\n"
        let playlist = try M3UParser.parse(text)
        #expect(playlist.entries == [M3UEntry(name: "Channel X", attributes: ["tvg-id": "x"], group: nil, url: "http://a/x.m3u8")])
    }

    @Test func extgrpAppliesUntilChangedAndGroupTitleWins() throws {
        let playlist = try M3UParser.parse("""
        #EXTM3U
        #EXTGRP:Sports
        #EXTINF:-1,One
        http://a/1
        #EXTINF:-1 group-title="News",Two
        http://a/2
        #EXTINF:-1,Three
        http://a/3
        #EXTGRP:Movies
        #EXTINF:-1,Four
        http://a/4
        """)
        #expect(playlist.entries.map(\.group) == ["Sports", "News", "Sports", "Movies"])
    }

    @Test func headerGuideURLs() throws {
        let urlTvg = try M3UParser.parse("""
        #EXTM3U url-tvg="https://a/x.xml.gz,https://b/y.xml"
        """)
        #expect(urlTvg.guideURLs == [URL(string: "https://a/x.xml.gz")!, URL(string: "https://b/y.xml")!])

        let xTvg = try M3UParser.parse("""
        #EXTM3U x-tvg-url="http://c/z.xml"
        """)
        #expect(xTvg.guideURLs == [URL(string: "http://c/z.xml")!])
    }

    @Test func skipsExtvlcoptBetweenEntryAndURL() throws {
        let playlist = try M3UParser.parse("""
        #EXTM3U
        #EXTINF:-1,One
        #EXTVLCOPT:http-user-agent=Foo
        http://a/1
        """)
        #expect(playlist.entries.map(\.url) == ["http://a/1"])
    }

    @Test func urlWithoutExtinfIsIgnored() throws {
        let playlist = try M3UParser.parse("""
        #EXTM3U
        http://a/orphan
        #EXTINF:-1,One
        http://a/1
        http://a/another-orphan
        """)
        #expect(playlist.entries.map(\.url) == ["http://a/1"])
    }

    @Test func htmlIsNotAPlaylist() {
        #expect(throws: M3UParser.ParseError.notAPlaylist) {
            try M3UParser.parse("<!DOCTYPE html><html><body>Not found</body></html>")
        }
    }
}
