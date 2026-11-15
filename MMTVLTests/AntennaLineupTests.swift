import Foundation
import Testing
@testable import MMTVL

/// M7j step 3: the tuners' lineups as channels (L1, L2, L5). Fake addresses and DeviceIDs only.
struct AntennaLineupTests {
    static func device(_ id: String = "1234ABCD", host: String = "10.0.0.9") -> HDHomeRunDevice {
        HDHomeRunDevice(id: id, name: "HDHomeRun CONNECT", model: "HDHR4-2US", tunerCount: 2,
                        baseURL: URL(string: "http://\(host)")!, lineupURL: URL(string: "http://\(host)/lineup.json")!)
    }

    static func entry(_ number: String, _ name: String? = "WTST-HD", host: String = "10.0.0.9",
                      drm: Bool? = nil, tags: [String] = [], enabled: Bool? = nil,
                      subscribed: Bool? = nil) -> HDHomeRunLineupEntry {
        HDHomeRunLineupEntry(guideNumber: number, guideName: name, url: "http://\(host):5004/auto/v\(number)",
                             drm: drm, enabled: enabled, subscribed: subscribed, tags: tags)
    }

    static func channels(_ entries: [HDHomeRunLineupEntry], firstNumber: Int = 1)
        -> (channels: [Channel], leftOut: Int, sharedNumbers: Int) {
        AntennaLineup.channels(devices: [(device(), entries)], firstNumber: firstNumber)
    }

    @Test func idsAreAntennaGuideNumbers() {
        let channel = Self.channels([Self.entry("5.1", "WAGA-HD")]).channels.first
        #expect(channel?.id == "antenna:5.1")
        #expect(channel?.guideNumber == "5.1")
        #expect(channel?.name == "WAGA-HD")
        #expect(channel?.source == .antenna(deviceID: "1234ABCD"))
        #expect(channel?.streamURL == URL(string: "http://10.0.0.9:5004/auto/v5.1"))
        #expect(channel?.isDirectStream == true)
        // Match Guide's key is the id, since names repeat (L12).
        #expect(channel?.overrideKey == "antenna:5.1")
    }

    @Test func numbersSortNumerically() {
        let shuffled = ["26.12", "2.10", "11.1", "2.2", "4.1", "2.1"].map { Self.entry($0) }
        let result = Self.channels(shuffled).channels
        #expect(result.map(\.guideNumber) == ["2.1", "2.2", "2.10", "4.1", "11.1", "26.12"])
        #expect(AntennaLineup.compareGuideNumbers("2.2", "2.10"))
        #expect(!AntennaLineup.compareGuideNumbers("2.10", "2.2"))
        #expect(AntennaLineup.compareGuideNumbers("9.1", "10.1"))
        #expect(AntennaLineup.compareGuideNumbers("5", "5.1"))
        #expect(!AntennaLineup.compareGuideNumbers("5.1", "5.1"))
    }

    @Test func numbersContinueAfterThePlaylist() {
        let result = Self.channels(["5.1", "2.1", "11.1"].map { Self.entry($0) }, firstNumber: 41).channels
        #expect(result.map(\.number) == [41, 42, 43])
        #expect(result.map(\.guideNumber) == ["2.1", "5.1", "11.1"])
    }

    @Test func displayNumberIsTheGuideNumber() {
        let antenna = Self.channels([Self.entry("26.12")], firstNumber: 8).channels.first
        #expect(antenna?.displayNumber == "26.12")
        #expect(antenna?.number == 8)
        // A playlist channel: its number, plays through the relay, Match Guide keys it by name.
        let playlist = Channel(id: "name:news", number: 7, name: "News", group: "Other", tvgID: nil, tvgName: nil,
                               logoURL: nil, streamURL: URL(string: "https://example.com/7.m3u8")!)
        #expect(playlist.source == .playlist)
        #expect(playlist.guideNumber == nil)
        #expect(playlist.displayNumber == "7")
        #expect(!playlist.isDirectStream)
        #expect(playlist.overrideKey == "News")
    }

    @Test func emptyNameBecomesChannelNumber() {
        let result = Self.channels([Self.entry("5.1", ""), Self.entry("5.2", nil), Self.entry("5.3", " \u{200B}\n"),
                                    Self.entry("5.4", "\u{202E}WTST")]).channels
        #expect(result.map(\.name) == ["Channel 5.1", "Channel 5.2", "Channel 5.3", "WTST"])
    }

    @Test func drmTagsAndFlagAreLeftOutAndCounted() {
        let result = Self.channels([
            Self.entry("2.1"),
            Self.entry("2.2", tags: ["drm"]),
            Self.entry("2.3", tags: ["favorite", "drm"]),
            Self.entry("2.4", drm: true),
            Self.entry("2.5", tags: ["favorite"]),
            Self.entry("2.6", drm: false),
        ])
        #expect(result.channels.map(\.guideNumber) == ["2.1", "2.5", "2.6"])
        #expect(result.leftOut == 3)
    }

    /// Disabled (`Enabled: 0`) and unsubscribed entries are left out, not counted as protected (L5).
    @Test func disabledAndUnsubscribedAreLeftOutUncounted() {
        let result = Self.channels([
            Self.entry("2.1", enabled: true, subscribed: true),
            Self.entry("2.2", enabled: false),
            Self.entry("2.3", subscribed: false),
            Self.entry("2.4", drm: true, enabled: false),
        ])
        #expect(result.channels.map(\.guideNumber) == ["2.1"])
        #expect(result.leftOut == 0)
    }

    /// Not counted in `leftOut`, which is protected channels only (Settings: "N protected channels left out").
    /// Security M1: the host is compared as written, since mpv/ffmpeg load the raw string: a percent-encoded literal
    /// that Foundation decodes to the tuner's address is left out, and so is a port outside 1…65535.
    @Test func urlOnAnotherHostIsLeftOut() {
        func entry(_ number: String, url: String) -> HDHomeRunLineupEntry {
            var entry = Self.entry(number)
            entry.url = url
            return entry
        }
        let result = Self.channels([
            Self.entry("2.1"),
            Self.entry("2.2", host: "10.0.0.10"),
            Self.entry("2.3", host: "203.0.113.5"),
            entry("2.4", url: "http://user@10.0.0.9:5004/auto/v2.4"),
            entry("2.5", url: "http://10.0.0%2E9:5004/auto/v2.5"),
            entry("2.6", url: "http://%31%30.0.0.9:5004/auto/v2.6"),
            entry("2.7", url: "http://10.0.0.9:99999/auto/v2.7"),
            entry("2.8", url: "http://10.0.0.9:0/auto/v2.8"),
            entry("2.9", url: "http://010.0.0.9:5004/auto/v2.9"),
            entry("2.10", url: "http://tuner.local:5004/auto/v2.10"),
            entry("2.11", url: "http://10.0.0.9/auto/v2.11"),        // no port: fine
            entry("2.12", url: "HTTP://10.0.0.9:65535/auto/v2.12"),  // the highest port: fine
        ])
        #expect(result.channels.map(\.guideNumber) == ["2.1", "2.11", "2.12"])
        #expect(result.leftOut == 0)
    }

    /// Step 10 (step 3's port low): the port is read from the URL's string. Foundation reads
    /// `:99999999999999999999` and an empty `:` as no port, but ffmpeg would load the raw string on port 80 or 0:
    /// both are left out, and so is `:0`. A port with leading zeros of at most 5 digits (`:080`, `:05004`) is the
    /// same number to Foundation and ffmpeg, so it's kept.
    @Test func streamPortIsReadAsWritten() {
        func entry(_ number: String, url: String) -> HDHomeRunLineupEntry {
            var entry = Self.entry(number)
            entry.url = url
            return entry
        }
        let result = Self.channels([
            entry("3.1", url: "http://10.0.0.9:99999999999999999999/auto/v3.1"),
            entry("3.2", url: "http://10.0.0.9:/auto/v3.2"),
            entry("3.3", url: "http://10.0.0.9:0/auto/v3.3"),
            entry("3.4", url: "http://10.0.0.9:000000/auto/v3.4"),
            entry("3.5", url: "http://10.0.0.9:65536/auto/v3.5"),
            entry("3.6", url: "http://10.0.0.9:5004/auto/v3.6"),     // fine
            entry("3.7", url: "http://10.0.0.9/auto/v3.7"),          // no port: fine
            entry("3.8", url: "http://10.0.0.9:080/auto/v3.8"),      // 80: fine
            entry("3.9", url: "http://10.0.0.9:05004/auto/v3.9"),    // 5004: fine
            entry("3.10", url: "http://x@10.0.0.9:/auto/v3.10"),
        ])
        #expect(result.channels.map(\.guideNumber) == ["3.6", "3.7", "3.8", "3.9"])
        #expect(result.leftOut == 0)

        let device = AntennaFixtures.device()
        for url in ["http://10.0.0.9:99999999999999999999/auto/v2.1", "http://10.0.0.9:/auto/v2.1",
                    "http://10.0.0.9:0/auto/v2.1", "http://10.0.0.9:"] {
            #expect(!device.isHTTPOnDevice(URL(string: url)!), "\(url)")
        }
        for url in ["http://10.0.0.9:5004/auto/v2.1", "http://10.0.0.9/auto/v2.1", "http://10.0.0.9:080/auto/v2.1",
                    "http://10.0.0.9:5004?x=1", "http://10.0.0.9:5004#x"] {
            #expect(device.isHTTPOnDevice(URL(string: url)!), "\(url)")
        }
    }

    @Test func nonHTTPURLIsLeftOut() {
        var https = Self.entry("2.2")
        https.url = "https://10.0.0.9:5004/auto/v2.2"
        var rtsp = Self.entry("2.3")
        rtsp.url = "rtsp://10.0.0.9/auto/v2.3"
        var file = Self.entry("2.4")
        file.url = "file:///etc/hosts"
        var garbage = Self.entry("2.5")
        garbage.url = "not a url"
        var noHost = Self.entry("2.6")
        noHost.url = "/auto/v2.6"
        let result = Self.channels([Self.entry("2.1"), https, rtsp, file, garbage, noHost])
        #expect(result.channels.map(\.guideNumber) == ["2.1"])
        #expect(result.leftOut == 0)
    }

    /// Devices in DeviceID order, whatever order they're given in (L1); the winner's device names the source.
    @Test func firstDeviceWinsADuplicateNumber() {
        let first = Self.device("1000AAAA", host: "10.0.0.9")
        let second = Self.device("2000BBBB", host: "10.0.0.11")
        let result = AntennaLineup.channels(devices: [
            (second, [Self.entry("5.1", "SECOND", host: "10.0.0.11"), Self.entry("7.1", host: "10.0.0.11")]),
            (first, [Self.entry("5.1", "FIRST", host: "10.0.0.9")]),
        ], firstNumber: 1).channels
        #expect(result.map(\.id) == ["antenna:5.1", "antenna:7.1"])
        #expect(result[0].name == "FIRST")
        #expect(result[0].source == .antenna(deviceID: "1000AAAA"))
        #expect(result[0].streamURL.host() == "10.0.0.9")
        #expect(result[1].source == .antenna(deviceID: "2000BBBB"))
        // Each device's URLs are checked against its own host.
        let crossed = AntennaLineup.channels(devices: [(first, [Self.entry("9.1", host: "10.0.0.11")])],
                                             firstNumber: 1)
        #expect(crossed.channels.isEmpty)
    }

    /// Step 10 (security N2): the GuideNumbers a later device would also have kept are counted (the library logs
    /// "Channel numbers on more than one tuner: N"). Not counted: a number on one device only, a repeat within one
    /// lineup, and a later copy that wouldn't be kept itself (protected, unavailable, or a URL on another host).
    @Test func numbersOnMoreThanOneTunerAreCounted() {
        let first = Self.device("1000AAAA", host: "10.0.0.9")
        let second = Self.device("2000BBBB", host: "10.0.0.11")
        let third = Self.device("3000CCCC", host: "10.0.0.12")
        let result = AntennaLineup.channels(devices: [
            (third, [Self.entry("5.1", host: "10.0.0.12"), Self.entry("6.1", host: "10.0.0.12")]),
            (second, [Self.entry("5.1", host: "10.0.0.11"), Self.entry("7.1", host: "10.0.0.11"),
                      Self.entry("8.1", host: "10.0.0.11", drm: true),
                      Self.entry("9.1", host: "10.0.0.11", enabled: false),
                      Self.entry("10.1", host: "10.0.0.9")]),
            (first, [Self.entry("5.1"), Self.entry("5.1"), Self.entry("7.1"), Self.entry("8.1"), Self.entry("9.1"),
                     Self.entry("10.1")]),
        ], firstNumber: 1)
        #expect(result.sharedNumbers == 2)   // 5.1 (on all three) and 7.1
        #expect(result.channels.map(\.id) == ["antenna:5.1", "antenna:6.1", "antenna:7.1", "antenna:8.1",
                                               "antenna:9.1", "antenna:10.1"])
        #expect(result.channels.filter { $0.source == .antenna(deviceID: "1000AAAA") }.count == 5)
        #expect(Self.channels([Self.entry("5.1"), Self.entry("5.1")]).sharedNumbers == 0)
        // A protected copy on the first device: the second's clear copy is the only kept one.
        let fallback = AntennaLineup.channels(devices: [(first, [Self.entry("5.1", drm: true)]),
                                                        (second, [Self.entry("5.1", host: "10.0.0.11")])],
                                              firstNumber: 1)
        #expect(fallback.sharedNumbers == 0)
    }

    /// Pre-build QA minor 2: the notice only when the count changes; back to 0 says so once.
    @Test func sharedNumbersNoticeOnlyOnAChange() {
        #expect(AntennaSource.sharedNumbersNotice(0, previous: 0) == nil)
        #expect(AntennaSource.sharedNumbersNotice(3, previous: 0)
                == "Channel numbers on more than one tuner: 3 (the first tuner's are used)")
        #expect(AntennaSource.sharedNumbersNotice(3, previous: 3) == nil)
        #expect(AntennaSource.sharedNumbersNotice(2, previous: 3)
                == "Channel numbers on more than one tuner: 2 (the first tuner's are used)")
        #expect(AntennaSource.sharedNumbersNotice(0, previous: 2) == "Channel numbers on more than one tuner: none now")
    }

    /// A protected copy on the first device doesn't hide a clear one on the next, and isn't counted then.
    @Test func protectedCopyFallsToTheNextDevice() {
        let first = Self.device("1000AAAA", host: "10.0.0.9")
        let second = Self.device("2000BBBB", host: "10.0.0.11")
        let result = AntennaLineup.channels(devices: [
            (first, [Self.entry("5.1", drm: true)]),
            (second, [Self.entry("5.1", host: "10.0.0.11")]),
        ], firstNumber: 1)
        #expect(result.channels.map(\.source) == [.antenna(deviceID: "2000BBBB")])
        #expect(result.leftOut == 0)
    }

    @Test func groupIsAntenna() {
        let channel = Self.channels([Self.entry("5.1")]).channels.first
        #expect(AntennaLineup.group == "Antenna")
        #expect(channel?.group == "Antenna")
        #expect(channel?.tvgID == nil)
        #expect(channel?.tvgName == nil)
        #expect(channel?.logoURL == nil)
    }

    /// The number becomes an id and a key in MMTVL's files: digits with at most one dot only.
    @Test func malformedGuideNumbersAreDropped() {
        let bad = ["", "5.", ".1", "5.1.1", "5a", "5,1", "٥.١", "123456.1", "../5", "5.1 ", "-5"]
        let result = Self.channels(bad.map { Self.entry($0) } + [Self.entry("702"), Self.entry("5.1")])
        #expect(result.channels.map(\.id) == ["antenna:5.1", "antenna:702"])
        #expect(result.leftOut == 0)
    }

    /// Security low 3: at most 1,000 kept entries per device; the rest are dropped uncounted.
    @Test func channelsPerDeviceAreCapped() {
        let entries = (1...1001).map { Self.entry("\($0).1") }
        let result = Self.channels(entries)
        #expect(AntennaLineup.maximumChannelsPerDevice == 1000)
        #expect(result.channels.count == 1000)
        #expect(result.channels.last?.guideNumber == "1000.1")
        #expect(result.leftOut == 0)
        // The cap is per device: a second device still adds its own.
        let second = Self.device("2000BBBB", host: "10.0.0.11")
        let both = AntennaLineup.channels(devices: [(Self.device(), entries),
                                                    (second, [Self.entry("2000.1", host: "10.0.0.11")])],
                                          firstNumber: 1)
        #expect(both.channels.count == 1001)
    }

    @Test func duplicateNumberInOneLineupKeepsTheFirst() {
        let result = Self.channels([Self.entry("5.1", "FIRST"), Self.entry("5.1", "SECOND")]).channels
        #expect(result.map(\.name) == ["FIRST"])
    }

    @Test func channelSourceHidesTheDeviceID() {
        let source = ChannelSource.antenna(deviceID: "1234ABCD")
        for text in [String(describing: source), String(reflecting: source), "\(source)"] {
            #expect(!text.contains("1234ABCD"))
        }
    }
}
