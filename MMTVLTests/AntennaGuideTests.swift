import Foundation
import Testing
@testable import MMTVL

/// M7j step 8 (L10, L12): SiliconDust's guide URL, its schedule and the antenna channels' matching rules. Fake
/// tokens and fake ids only.
struct AntennaGuideTests {
    private func channel(_ number: String, _ name: String) -> Channel {
        Channel(id: AntennaLineup.idPrefix + number, number: 100, name: name, group: AntennaLineup.group, tvgID: nil,
                tvgName: nil, logoURL: nil, streamURL: AntennaFixtures.streamURL(number),
                source: .antenna(deviceID: AntennaFixtures.deviceID), guideNumber: number)
    }

    private func epg(_ id: String, _ names: String...) -> EPGChannel {
        EPGChannel(id: id.lowercased(), names: names)
    }

    /// Shaped like SiliconDust's file (step 1): the short name, number + names, the bare number, the name, the network.
    private var guide: [EPGChannel] {
        [epg("US10001.hdhomerun.com", "WSBDT", "2.1 WSBDT", "2.1 WSB-HD", "2.1", "WSB-HD", "ABC"),
         epg("US10002.hdhomerun.com", "WAGADT", "5.1 WAGADT", "5.1 WAGA-HD", "5.1", "WAGA-HD", "FOX"),
         epg("US10003.hdhomerun.com", "WXIADT", "11.1 WXIADT", "11.1 WXIA-TV", "11.1", "WXIA-TV", "NBC")]
    }

    // MARK: - URL

    @Test func urlConcatenatesAuthsInDeviceOrder() throws {
        let url = try #require(AntennaGuide.url(deviceAuths: ["AAAAbbbb1111", "CCCCdddd2222"]))
        #expect(url.query(percentEncoded: true) == "DeviceAuth=AAAAbbbb1111CCCCdddd2222")
        let reversed = try #require(AntennaGuide.url(deviceAuths: ["CCCCdddd2222", "AAAAbbbb1111"]))
        #expect(reversed.query(percentEncoded: true) == "DeviceAuth=CCCCdddd2222AAAAbbbb1111")
    }

    /// `URLComponents` would leave `+` alone, which a server reads as a space.
    @Test func urlPercentEncodesPlusSlashAndEquals() throws {
        let url = try #require(AntennaGuide.url(deviceAuths: ["ab+cd/ef==1234"]))
        #expect(url.absoluteString == "https://api.hdhomerun.com/api/xmltv?DeviceAuth=ab%2Bcd%2Fef%3D%3D1234")
        let underscore = try #require(AntennaGuide.url(deviceAuths: ["ab_cd-ef12345"]))
        #expect(underscore.query(percentEncoded: true) == "DeviceAuth=ab%5Fcd%2Def12345")
    }

    @Test func urlIsHTTPSToApiHdhomerunCom() throws {
        let url = try #require(AntennaGuide.url(deviceAuths: [AntennaFixtures.fakeDeviceAuth]))
        #expect(url.scheme == "https")
        #expect(url.host() == "api.hdhomerun.com")
        #expect(url.port == nil)
        #expect(url.path() == "/api/xmltv")
        #expect(url.user == nil && url.fragment == nil)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.map(\.name) == ["DeviceAuth"])
        #expect(items.first?.value == AntennaFixtures.fakeDeviceAuth)
    }

    /// The guide's id is the bare endpoint's hash: the same whatever the token, and never the tokened URL's.
    @Test func sourceIDHasNoToken() throws {
        let first = try #require(AntennaGuide.url(deviceAuths: ["AAAAbbbb1111"]))
        let second = try #require(AntennaGuide.url(deviceAuths: ["ZZZZyyyy9999"]))
        #expect(AntennaGuide.sourceID == IPTVLibrary.hash(AntennaGuide.endpoint))
        #expect(AntennaGuide.sourceID != IPTVLibrary.hash(first))
        #expect(AntennaGuide.sourceID != IPTVLibrary.hash(second))
        #expect(!AntennaGuide.sourceID.contains("AAAAbbbb1111"))
        #expect(AntennaGuide.endpoint.query() == nil)
    }

    /// Step 2 security L5: a missing, short, long or odd-character DeviceAuth means no URL (so no download).
    @Test func badDeviceAuthsGiveNoURL() {
        #expect(AntennaGuide.url(deviceAuths: []) == nil)
        for bad in ["", "short", String(repeating: "a", count: 65), "abcd efgh1234", "abcd&x=1234", "abcd%2B1234",
                    "abcd\n12345678", "abcdé1234567", "abcd?1234567", "abcd#1234567", "abcd.1234567"] {
            #expect(!AntennaGuide.isValidDeviceAuth(bad))
            #expect(AntennaGuide.url(deviceAuths: [bad]) == nil)
            #expect(AntennaGuide.url(deviceAuths: [AntennaFixtures.fakeDeviceAuth, bad]) == nil)
        }
        #expect(AntennaGuide.isValidDeviceAuth(String(repeating: "a", count: 64)))
        #expect(AntennaGuide.isValidDeviceAuth("abcdefgh"))
        #expect(AntennaGuide.isValidDeviceAuth(AntennaFixtures.fakeDeviceAuth))
    }

    // MARK: - Schedule

    @Test func nextDueIsBetween20And28Hours() {
        let now = Date(timeIntervalSince1970: 1_791_200_000)
        #expect(AntennaGuide.nextDue(after: now, random: { 0 }) == now.addingTimeInterval(20 * 3600))
        #expect(AntennaGuide.nextDue(after: now, random: { 0.5 }) == now.addingTimeInterval(24 * 3600))
        #expect(AntennaGuide.nextDue(after: now, random: { 1 }) == now.addingTimeInterval(28 * 3600))
        #expect(AntennaGuide.nextDue(after: now, random: { 7 }) == now.addingTimeInterval(28 * 3600))
        for _ in 0..<200 {
            let due = AntennaGuide.nextDue(after: now).timeIntervalSince(now)
            #expect(due >= 20 * 3600 && due <= 28 * 3600)
        }
    }

    // MARK: - Matching

    @Test func matchesByGuideNumber() {
        let channels = [channel("2.1", "WSB-HD"), channel("5.1", "WAGA-HD"), channel("11.1", "WXIA-HD"),
                        channel("4.3", "WGCL-D3")]
        let result = AntennaGuide.match(channels, to: guide)
        #expect(result == ["antenna:2.1": "us10001.hdhomerun.com", "antenna:5.1": "us10002.hdhomerun.com",
                           "antenna:11.1": "us10003.hdhomerun.com"])
        // The prefix form ("2.1 WSB-HD") alone doesn't match: rule 2 is the exact number only.
        let prefixOnly = [epg("US1.hdhomerun.com", "WSBDT", "2.1 WSB-HD")]
        #expect(AntennaGuide.match([channel("2.1", "Something")], to: prefixOnly).isEmpty)
    }

    /// Rule 3: a name only one antenna channel has matches an unclaimed guide channel; a repeated name never does.
    @Test func uniqueNameMatchesRepeatedNameDoesnt() {
        let guide = [epg("US20001.hdhomerun.com", "JTV", "99.9 JTV", "99.9"),
                     epg("US20002.hdhomerun.com", "WYGA-CD")]
        let channels = [channel("30.1", "JTV"), channel("40.1", "WYGA-CD"), channel("40.2", "WYGA-CD")]
        #expect(AntennaGuide.match(channels, to: guide) == ["antenna:30.1": "us20001.hdhomerun.com"])
    }

    /// Rule 3 (user decision 2026-11-15): a channel without its own guide channel never gets another number's
    /// listings, even when its name is one of that guide channel's display-names (the network, "ABC").
    @Test func nameRuleSkipsClaimedGuideChannels() {
        let channels = [channel("2.1", "WSB-HD"), channel("4.3", "ABC")]
        #expect(AntennaGuide.match(channels, to: guide) == ["antenna:2.1": "us10001.hdhomerun.com"])
        // The same name, against a guide channel whose number isn't on the lineup, matches.
        #expect(AntennaGuide.match([channel("4.3", "ABC")], to: guide) == ["antenna:4.3": "us10001.hdhomerun.com"])
    }

    /// Step 1: one id on two `<channel>` elements (11.11 and 36.4), merged by the parser: both numbers share it.
    @Test func twoNumbersShareARepeatedGuideChannel() {
        let merged = [epg("US30001.hdhomerun.com", "WATLDT4", "11.11 WATLDT4", "11.11", "36.4 WATLDT4", "36.4")]
        let channels = [channel("11.11", "WATLDT4"), channel("36.4", "WATLDT4")]
        #expect(AntennaGuide.match(channels, to: merged)
                == ["antenna:11.11": "us30001.hdhomerun.com", "antenna:36.4": "us30001.hdhomerun.com"])
    }

    /// L12: the override under the channel's id wins over one under its name; "" means no guide; a target not in the
    /// guide falls through to the number.
    @Test func overrideByAntennaKeyWins() {
        let wsb = channel("2.1", "WSB-HD")
        let waga = channel("5.1", "WAGA-HD")
        let wxia = channel("11.1", "WXIA-HD")
        let overrides = ["ANTENNA:5.1": "US10003.hdhomerun.com", "WAGA-HD": "us10001.hdhomerun.com",
                         "wxia-hd": "", "antenna:2.1": "missing.id"]
        let result = AntennaGuide.match([wsb, waga, wxia], to: guide, overrides: overrides)
        #expect(result == ["antenna:5.1": "us10003.hdhomerun.com", "antenna:2.1": "us10001.hdhomerun.com"])
        // By name when there's no key for the id.
        #expect(AntennaGuide.match([waga], to: guide, overrides: ["WAGA-HD": "US10001.hdhomerun.com"])
                == ["antenna:5.1": "us10001.hdhomerun.com"])
    }
}
