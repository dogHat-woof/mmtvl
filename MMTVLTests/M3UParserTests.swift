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

/// M7n step 4b: `parseAttributes` builds its regex once. These pin the attribute and name results it gave when it
/// built the regex for every line (keys lowercased, the first of a key wins, only `key="value"` counts).
struct M3UParserAttributeTests {
    static let manyAttributes = #"""
    #EXTM3U url-tvg="https://a/x.xml.gz, https://b/y.xml" x-tvg-url="ftp://c/z.xml,https://a/x.xml.gz" tvg-shift="0"
    #EXTINF:-1 TVG-ID="Upper.us" tvg-id="lower.us" Group-Title="Mixed Case",Duplicate Keys
    http://s/1
    #EXTINF:0 tvg_id2="a_b" tvg-logo="https://l/x.png?a=1&b=2=3" tvg-name="" group-title="",Underscore, Digits & Empty
    http://s/2
    #EXTINF:-1 tvg-id=unquoted tvg-name='single' tvg-chno = "5" tvg-logo="http://unterminated,No Closing Quote
    http://s/3
    #EXTINF:-1 a="1"b="2" x:tvg-country="US" tvg.lang="en",Adjacent "Quoted" Name
    http://s/4
    #EXTINF:-1 tvg-name="Café 🇺🇸 Ünïcode" tvg-name="second" group-title="Sports, Live",Café "Name", With Comma
    http://s/5
    #EXTINF:-1 tvg-name="A \"B\" C" catchup="default" catchup-days="7",Escaped Quotes
    http://s/6
    #EXTGRP:From EXTGRP
    #EXTINF:-1 tvg-id="g",tvg-id="in-name" Comma Then Attribute
    http://s/7
    #EXTINF:-1 group-title="Explicit" tvg-ID="MiXeD",
    http://s/8
    #EXTINF:-1  tvg-id="  padded  "  ,  Padded Name  
       http://s/9   
    #EXTINF:-1 tvg-name="x"́ group-title="G",Combining Mark
    http://s/10
    """#

    /// The attribute parsing as it was before step 4b (the regex literal built for each line).
    private static func referenceAttributes(_ line: String) -> [String: String] {
        var attributes: [String: String] = [:]
        for match in line.matches(of: /([A-Za-z0-9_-]+)="([^"]*)"/) {
            let key = String(match.1).lowercased()
            if attributes[key] == nil { attributes[key] = String(match.2) }
        }
        return attributes
    }

    @Test func entriesAreAsBefore() throws {
        let playlist = try M3UParser.parse(Self.manyAttributes)
        #expect(playlist.guideURLs == [URL(string: "https://a/x.xml.gz")!, URL(string: "https://b/y.xml")!])
        #expect(playlist.entries == [
            M3UEntry(name: "Duplicate Keys", attributes: ["tvg-id": "Upper.us", "group-title": "Mixed Case"],
                     group: "Mixed Case", url: "http://s/1"),
            M3UEntry(name: "Underscore, Digits & Empty",
                     attributes: ["tvg_id2": "a_b", "tvg-logo": "https://l/x.png?a=1&b=2=3", "tvg-name": "",
                                  "group-title": ""],
                     group: nil, url: "http://s/2"),
            M3UEntry(name: "", attributes: [:], group: nil, url: "http://s/3"),
            M3UEntry(name: #"Adjacent "Quoted" Name"#,
                     attributes: ["a": "1", "b": "2", "tvg-country": "US", "lang": "en"], group: nil, url: "http://s/4"),
            M3UEntry(name: #"Café "Name", With Comma"#,
                     attributes: ["tvg-name": "Café 🇺🇸 Ünïcode", "group-title": "Sports, Live"],
                     group: "Sports, Live", url: "http://s/5"),
            M3UEntry(name: "Escaped Quotes", attributes: ["tvg-name": #"A \"#, "catchup": "default", "catchup-days": "7"],
                     group: nil, url: "http://s/6"),
            M3UEntry(name: #"tvg-id="in-name" Comma Then Attribute"#, attributes: ["tvg-id": "g"],
                     group: "From EXTGRP", url: "http://s/7"),
            M3UEntry(name: "", attributes: ["group-title": "Explicit", "tvg-id": "MiXeD"], group: "Explicit",
                     url: "http://s/8"),
            M3UEntry(name: "Padded Name", attributes: ["tvg-id": "  padded  "], group: "From EXTGRP", url: "http://s/9"),
            M3UEntry(name: "", attributes: ["tvg-name": "x\"\u{301} group-title="], group: "From EXTGRP",
                     url: "http://s/10"),
        ])
        #expect(playlist.entries[8].tvgID == "padded")
    }

    /// Every `#EXTINF` line's attributes equal the pre-4b parsing's, and parsing twice gives the same result (the
    /// shared regex keeps no state between lines or calls).
    @Test func attributesMatchTheReferenceParsing() throws {
        let lines = Self.manyAttributes.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("#EXTINF:") }
        let playlist = try M3UParser.parse(Self.manyAttributes)
        #expect(playlist.entries.count == lines.count)
        for (entry, line) in zip(playlist.entries, lines) {
            #expect(entry.attributes == Self.referenceAttributes(line))
        }
        #expect(try M3UParser.parse(Self.manyAttributes) == playlist)
    }

    /// Parsing from many tasks at once (the library parses off the main actor) gives the same playlist each time.
    @Test func concurrentParsesAgree() async throws {
        let expected = try M3UParser.parse(Self.manyAttributes)
        let text = Self.manyAttributes
        let results = await withTaskGroup(of: M3UPlaylist?.self) { group in
            for _ in 0..<8 { group.addTask { try? M3UParser.parse(text) } }
            var results: [M3UPlaylist?] = []
            for await result in group { results.append(result) }
            return results
        }
        #expect(results.count == 8)
        #expect(results.allSatisfy { $0 == expected })
    }
}
