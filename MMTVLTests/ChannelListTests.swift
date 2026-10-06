import Foundation
import Testing
@testable import MMTVL

struct ChannelListTests {
    private func entry(_ name: String, tvgID: String? = nil, tvgName: String? = nil, group: String? = "G",
                       url: String = "https://cdn/x/chunks.m3u8", extra: [String: String] = [:]) -> M3UEntry {
        var attributes = extra
        if let tvgID { attributes["tvg-id"] = tvgID }
        if let tvgName { attributes["tvg-name"] = tvgName }
        return M3UEntry(name: name, attributes: attributes, group: group, url: url)
    }

    private func channels(_ entries: [M3UEntry]) -> [Channel] {
        ChannelList.make(from: M3UPlaylist(guideURLs: [], entries: entries))
    }

    @Test func ids() {
        let result = channels([
            entry("NBA TV", tvgID: "NBATV.us"),
            entry("Red Zone2", tvgID: ""),
            entry("NBA TV East", tvgID: "nbatv.us"),
            entry("NBA TV West", tvgID: "nbatv.us"),
        ])
        #expect(result.map(\.id) == ["id:nbatv.us", "name:red zone2", "id:nbatv.us#2", "id:nbatv.us#3"])
    }

    @Test func numberingAndNames() {
        let result = channels([
            entry("One"),
            entry("", tvgName: "Two by tvg-name"),
            entry(""),
        ])
        #expect(result.map(\.number) == [1, 2, 3])
        #expect(result.map(\.name) == ["One", "Two by tvg-name", "Channel 3"])
    }

    @Test func dropsVODButKeepsMovieTypedLiveStreams() {
        let result = channels([
            entry("Film", url: "http://host/movie/u/p/1.mkv"),
            entry("Show", url: "http://host/series/u/p/2.ts"),
            entry("Clip", url: "http://host/clip.mp4"),
            entry("Game", url: "https://cdn/perdias/9/chunks.m3u8", extra: ["tvg-type": "movie"]),
            entry("RTMP", url: "rtmp://host/live"),
        ])
        #expect(result.map(\.name) == ["Game"])
        #expect(result.first?.number == 1)
    }

    @Test func missingGroupIsOther() {
        #expect(channels([entry("A", group: nil)]).first?.group == "Other")
    }

    @Test func groupsInFirstAppearanceOrder() {
        let result = channels([
            entry("a", group: "Live"), entry("b", group: "NBA"), entry("c", group: "Live"), entry("d", group: "NHL"),
        ])
        #expect(ChannelList.groups(of: result) == ["Live", "NBA", "NHL"])
        #expect(ChannelList.guideGroups(of: result) == ["All Channels", "Live", "NBA", "NHL"])
        #expect(ChannelList.channels(in: "Live", of: result).map(\.name) == ["a", "c"])
        #expect(ChannelList.channels(in: "All Channels", of: result).map(\.name) == ["a", "b", "c", "d"])
    }

    @Test func singleGroupHasNoAllChannels() {
        let result = channels([entry("a", group: "Live"), entry("b", group: "Live")])
        #expect(ChannelList.guideGroups(of: result) == ["Live"])
    }
}
