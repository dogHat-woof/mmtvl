import Foundation
import Testing
@testable import MMTVL

struct HLSPlaylistTests {
    static let base = URL(string: "https://cdn.example/live/ch1/master.m3u8?token=abc")!

    static let master = """
    #EXTM3U
    #EXT-X-VERSION:3
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aac",NAME="English",DEFAULT=YES,URI="audio/index.m3u8?token=abc"
    #EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1280x720,AUDIO="aac"
    video/index.m3u8?token=abc
    """

    static let media = """
    #EXTM3U
    #EXT-X-TARGETDURATION:5
    #EXT-X-MEDIA-SEQUENCE:100
    #EXTINF:5.0,
    seg100.ts
    #EXTINF:5.0,
    seg101.ts
    #EXTINF:5.0,
    seg102.ts
    #EXTINF:5.0,
    seg103.ts
    #EXTINF:5.0,
    https://other.example/seg104.ts
    """

    @Test func kinds() {
        #expect(HLSPlaylist.kind(of: Self.master) == .master)
        #expect(HLSPlaylist.kind(of: Self.media) == .media)
        #expect(HLSPlaylist.kind(of: "hello") == .unknown)
        #expect(HLSPlaylist.isPlaylist(Data(Self.media.utf8), contentType: nil))
        #expect(HLSPlaylist.isPlaylist(Data(), contentType: "application/vnd.apple.mpegurl"))
        #expect(!HLSPlaylist.isPlaylist(Data([0x47, 0x40]), contentType: "video/mp2t"))
    }

    @Test func rewritesLinesAndURIAttributes() {
        let rewritten = HLSPlaylist.rewrite(Self.master, base: Self.base) { "LOCAL[\($0.absoluteString)]" }
        #expect(rewritten.contains(#"URI="LOCAL[https://cdn.example/live/ch1/audio/index.m3u8?token=abc]""#))
        #expect(rewritten.contains("\nLOCAL[https://cdn.example/live/ch1/video/index.m3u8?token=abc]"))
        #expect(rewritten.contains("#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1280x720,AUDIO=\"aac\""))
        #expect(!rewritten.contains("\nvideo/index"))
    }

    @Test func handlesCRLF() {
        let text = "#EXTM3U\r\n#EXTINF:5,\r\nseg.ts\r\n"
        let rewritten = HLSPlaylist.rewrite(text, base: Self.base) { "L/\($0.lastPathComponent)" }
        #expect(rewritten == "#EXTM3U\n#EXTINF:5,\nL/seg.ts\n")
    }

    @Test func masterListsItsMediaPlaylists() {
        #expect(HLSPlaylist.mediaPlaylists(in: Self.master, base: Self.base) == [
            URL(string: "https://cdn.example/live/ch1/audio/index.m3u8?token=abc")!,
            URL(string: "https://cdn.example/live/ch1/video/index.m3u8?token=abc")!,
        ])
        #expect(HLSPlaylist.mediaPlaylists(in: Self.media, base: Self.base).isEmpty)
    }

    /// ffmpeg starts a live stream 3 segments from the end.
    @Test func liveStartSegment() {
        let base = URL(string: "https://cdn.example/live/ch1/video/index.m3u8")!
        #expect(HLSPlaylist.startSegments(in: Self.media, base: base) == [URL(string: "https://cdn.example/live/ch1/video/seg102.ts")!])
        let finished = Self.media + "\n#EXT-X-ENDLIST"
        #expect(HLSPlaylist.startSegments(in: finished, base: base) == [URL(string: "https://cdn.example/live/ch1/video/seg100.ts")!])
        let short = "#EXTM3U\n#EXTINF:5,\nonly.ts"
        #expect(HLSPlaylist.startSegments(in: short, base: base) == [URL(string: "https://cdn.example/live/ch1/video/only.ts")!])
    }

    @Test func initializationSectionComesFirst() {
        let base = URL(string: "https://cdn.example/v/index.m3u8")!
        let text = "#EXTM3U\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF:4,\na.m4s\n#EXTINF:4,\nb.m4s"
        #expect(HLSPlaylist.startSegments(in: text, base: base) == [
            URL(string: "https://cdn.example/v/init.mp4")!, URL(string: "https://cdn.example/v/a.m4s")!,
        ])
    }
}
