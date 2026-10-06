import Foundation
import Testing
@testable import MMTVL

struct XMLTVTests {
    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    // MARK: Dates

    @Test func dates() {
        #expect(XMLTVDate.parse("20261005143000 +0000") == utc(2026, 10, 5, 14, 30))
        #expect(XMLTVDate.parse("20261005143000 -0500") == utc(2026, 10, 5, 19, 30))
        #expect(XMLTVDate.parse("20261005143000") == utc(2026, 10, 5, 14, 30))
        #expect(XMLTVDate.parse("202610051430") == utc(2026, 10, 5, 14, 30))
        #expect(XMLTVDate.parse("20261005143015+0100") == utc(2026, 10, 5, 13, 30, 15))
        #expect(XMLTVDate.parse("garbage") == nil)
        #expect(XMLTVDate.parse("2026100514") == nil)
        #expect(XMLTVDate.parse("20261305143000") == nil)
        #expect(XMLTVDate.parse("20261005143000 EST") == nil)
    }

    // MARK: Parser

    static let fixture = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE tv SYSTEM "xmltv.dtd">
    <tv generator-info-name="test">
      <channel id="NFL.Network.HD.us2"><display-name>NFL Network HD</display-name><display-name>NFL Network</display-name></channel>
      <channel id="ESPN.us2"><display-name>ESPN</display-name></channel>
      <channel id="Other.us2"><display-name>Other</display-name></channel>
      <programme start="20261005120000 +0000" stop="20261005130000 +0000" channel="NFL.Network.HD.us2">
        <title lang="en">Good Morning Football</title><title lang="es">Buenos días</title>
        <sub-title>Week 5</sub-title>
        <desc>Part one &amp; </desc>
        <category>Sports</category><category>Football</category>
        <episode-num system="xmltv_ns">1.0.0/1</episode-num>
      </programme>
      <programme start="20261005130000 +0000" channel="NFL.Network.HD.us2">
        <title>NFL Total Access</title>
        <episode-num system="xmltv_ns">2.3.</episode-num>
        <episode-num system="onscreen">Ep 104</episode-num>
      </programme>
      <programme start="20261005150000 +0000" stop="20261005160000 +0000" channel="NFL.Network.HD.us2">
        <title>Later</title>
      </programme>
      <programme start="20261001120000 +0000" stop="20261001130000 +0000" channel="NFL.Network.HD.us2">
        <title>Too old</title>
      </programme>
      <programme start="20261005120000 +0000" stop="20261005130000 +0000" channel="Other.us2">
        <title>Unwanted</title>
      </programme>
      <programme start="bad" stop="20261005130000 +0000" channel="ESPN.us2">
        <title>Bad start</title>
      </programme>
      <programme start="20261005120000 +0000" stop="20261005130000 +0000" channel="ESPN.us2">
        <title>SportsCenter</title>
      </programme>
    </tv>
    """

    private func writeFixture(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "xmltv-\(UUID().uuidString).xml")
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test func parsesFixture() throws {
        let url = try writeFixture(Self.fixture)
        defer { try? FileManager.default.removeItem(at: url) }

        var calls: [[EPGChannel]] = []
        let window = DateInterval(start: utc(2026, 10, 5, 0, 0), end: utc(2026, 10, 9, 0, 0))
        let result = try XMLTVParser.parse(fileURL: url, window: window) { channels in
            calls.append(channels)
            return ["nfl.network.hd.us2", "espn.us2"]
        }

        #expect(calls.count == 1)
        #expect(calls.first?.map(\.id) == ["nfl.network.hd.us2", "espn.us2", "other.us2"])
        #expect(result.channels.first?.names == ["NFL Network HD", "NFL Network"])

        let titles = result.programmes.map(\.title)
        #expect(titles.sorted() == ["Good Morning Football", "Later", "NFL Total Access", "SportsCenter"])

        let first = try #require(result.programmes.first { $0.title == "Good Morning Football" })
        #expect(first.channelID == "nfl.network.hd.us2")
        #expect(first.subtitle == "Week 5")
        #expect(first.summary == "Part one &")
        #expect(first.category == "Sports")
        #expect(first.episode == "S2 E1")
        #expect(first.start == utc(2026, 10, 5, 12, 0))
        #expect(first.stop == utc(2026, 10, 5, 13, 0))

        let missingStop = try #require(result.programmes.first { $0.title == "NFL Total Access" })
        #expect(missingStop.stop == utc(2026, 10, 5, 15, 0))
        #expect(missingStop.episode == "Ep 104")
    }

    @Test func lastProgrammeWithoutStopGetsHalfHour() throws {
        let url = try writeFixture("""
        <tv><channel id="a"><display-name>A</display-name></channel>
        <programme start="20261005120000" channel="a"><title>Only</title></programme></tv>
        """)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try XMLTVParser.parse(fileURL: url, window: DateInterval(start: .distantPast, end: .distantFuture)) { _ in ["a"] }
        #expect(result.programmes.first?.stop == utc(2026, 10, 5, 12, 30))
    }

    @Test func descriptionChunksAreJoined() throws {
        let url = try writeFixture("""
        <tv><channel id="a"><display-name>A</display-name></channel>
        <programme start="20261005120000" stop="20261005130000" channel="a"><title>T</title>
        <desc>Tom &amp; Jerry &lt;3 and a long
        line that continues</desc></programme></tv>
        """)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try XMLTVParser.parse(fileURL: url, window: DateInterval(start: .distantPast, end: .distantFuture)) { _ in ["a"] }
        #expect(result.programmes.first?.summary == "Tom & Jerry <3 and a long\nline that continues")
    }

    @Test func episodeText() {
        #expect(XMLTVParser.episodeText(xmltvNS: "1.0.0/1") == "S2 E1")
        #expect(XMLTVParser.episodeText(xmltvNS: ".4.") == "E5")
        #expect(XMLTVParser.episodeText(xmltvNS: "0/2.11/20.") == "S1 E12")
        #expect(XMLTVParser.episodeText(xmltvNS: "..") == nil)
    }

    @Test func malformedFileThrows() throws {
        let url = try writeFixture("<tv><channel id=\"a\">")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: (any Error).self) {
            try XMLTVParser.parse(fileURL: url, window: DateInterval(start: .distantPast, end: .distantFuture)) { _ in [] }
        }
    }
}
