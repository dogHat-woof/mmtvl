import Foundation
import Testing
@testable import MMTVL

/// M7j L18 (step 9b): the channel scan's two `lineup.post` requests, `lineup_status.json`'s scan keys, and the POST
/// itself. Fake LAN addresses only; the live POST goes through `StubTunerProtocol` (never the network), and every
/// other `HDHomeRunHTTP` posts nothing.
struct HDHomeRunScanTests {
    private static func idle(source: String? = "Antenna", list: [String] = ["Antenna", "Cable"]) -> HDHomeRunLineupStatus {
        HDHomeRunLineupStatus(scanInProgress: false, scanPossible: true, source: source, sourceList: list)
    }

    @Test func startURLIsLineupPostWithTheCurrentSource() {
        let device = AntennaLineupTests.device()
        #expect(HDHomeRunScan.startURL(device: device, status: Self.idle())?.absoluteString
            == "http://10.0.0.9/lineup.post?scan=start&source=Antenna")
        // The device's host and port, as its BaseURL has them.
        var withPort = AntennaLineupTests.device(host: "10.0.0.12")
        withPort.baseURL = URL(string: "http://10.0.0.12:80")!
        #expect(HDHomeRunScan.startURL(device: withPort, status: Self.idle())?.absoluteString
            == "http://10.0.0.12:80/lineup.post?scan=start&source=Antenna")
        // The current source, never another one in the list.
        #expect(HDHomeRunScan.startURL(device: device, status: Self.idle(source: "Cable"))?.absoluteString
            == "http://10.0.0.9/lineup.post?scan=start&source=Cable")
        // A space is percent-encoded.
        #expect(HDHomeRunScan.startURL(device: device, status: Self.idle(source: "Air 2", list: ["Air 2"]))?
            .absoluteString == "http://10.0.0.9/lineup.post?scan=start&source=Air%202")
    }

    @Test func sourceOutsideTheListDoesntStart() {
        let device = AntennaLineupTests.device()
        #expect(HDHomeRunScan.startURL(device: device, status: Self.idle(source: "Cable", list: ["Antenna"])) == nil)
        #expect(HDHomeRunScan.startURL(device: device, status: Self.idle(source: nil)) == nil)
        #expect(HDHomeRunScan.startURL(device: device, status: Self.idle(list: [])) == nil)
        // Case matters: "antenna" isn't "Antenna".
        #expect(HDHomeRunScan.startURL(device: device, status: Self.idle(source: "antenna")) == nil)
    }

    @Test func oddSourceCharactersDontStart() {
        let device = AntennaLineupTests.device()
        let long = String(repeating: "A", count: 40)
        for source in ["Antenna&scan=abort", long, "Antënna", "", "Antenna\n", "Antenna/../x", "Antenna%20"] {
            #expect(HDHomeRunScan.startURL(device: device, status: Self.idle(source: source, list: [source])) == nil,
                    "\(source)")
            #expect(HDHomeRunScan.startURL(device: device, source: source) == nil, "\(source)")
        }
        #expect(HDHomeRunScan.isValidSource(String(repeating: "A", count: 32)))
        #expect(!HDHomeRunScan.isValidSource(String(repeating: "A", count: 33)))
    }

    @Test func abortURL() {
        #expect(HDHomeRunScan.abortURL(device: AntennaLineupTests.device())?.absoluteString
            == "http://10.0.0.9/lineup.post?scan=abort")
        // Only on an origin BaseURL with a canonical IPv4 host.
        for base in ["http://10.0.0.9/path", "http://10.0.0.9/?x=1", "http://hdhomerun.local", "http://10.0.0.09",
                     "https://10.0.0.9", "http://10.0.0.9:5004"] {
            var device = AntennaLineupTests.device()
            device.baseURL = URL(string: base)!
            #expect(HDHomeRunScan.abortURL(device: device) == nil, "\(base)")
            #expect(HDHomeRunScan.startURL(device: device, status: Self.idle()) == nil, "\(base)")
        }
    }

    @Test func statusDecodesProgressAndFound() throws {
        let scanning = try #require(HDHomeRunLineupStatus.decode(Data(#"{"ScanInProgress":1,"Progress":45,"Found":120}"#.utf8)))
        #expect(scanning == HDHomeRunLineupStatus(scanInProgress: true, progress: 45, found: 120))
        // Clamped; a value of another type is nil.
        let odd = try #require(HDHomeRunLineupStatus.decode(Data(#"{"ScanInProgress":1,"Progress":150,"Found":-3}"#.utf8)))
        #expect(odd.progress == 100)
        #expect(odd.found == 0)
        #expect(HDHomeRunLineupStatus.decode(Data(#"{"ScanInProgress":1,"Progress":-5}"#.utf8))?.progress == 0)
        // Security M1: a huge Found is capped, so the sum over devices can't overflow.
        let huge = try #require(HDHomeRunLineupStatus.decode(Data(#"{"ScanInProgress":1,"Found":9223372036854775807}"#.utf8)))
        #expect(huge.found == HDHomeRunLineupStatus.maximumFound)
        #expect(HDHomeRunLineupStatus.maximumFound == 100_000)
        #expect(AntennaSource.total([Int.max, Int.max, 5]) == Int.max)
        #expect(AntennaSource.total([3, 4]) == 7)
        let text = try #require(HDHomeRunLineupStatus.decode(Data(#"{"ScanInProgress":1,"Progress":"45","Found":"x"}"#.utf8)))
        #expect(text.progress == nil)
        #expect(text.found == nil)
        #expect(text.scanInProgress)
    }

    @Test func idleStatusDecodesTheSourceList() throws {
        let idle = #"{"ScanInProgress":0,"ScanPossible":1,"Source":"Antenna","SourceList":["Antenna","Cable"]}"#
        let status = try #require(HDHomeRunLineupStatus.decode(Data(idle.utf8)))
        #expect(!status.scanInProgress)
        #expect(status.scanPossible == true)
        #expect(status.source == "Antenna")
        #expect(status.sourceList == ["Antenna", "Cable"])
        // ScanPossible 0 or missing; a list with other types keeps its strings, at most 16.
        let busy = try #require(HDHomeRunLineupStatus.decode(Data(#"{"ScanInProgress":0,"ScanPossible":0}"#.utf8)))
        #expect(busy.scanPossible == false)
        #expect(busy.sourceList.isEmpty)
        #expect(HDHomeRunLineupStatus.decode(Data(#"{"ScanInProgress":0}"#.utf8))?.scanPossible == nil)
        let mixed = try #require(HDHomeRunLineupStatus.decode(Data(#"{"Source":"Antenna","SourceList":["Antenna",5,null,"Cable"]}"#.utf8)))
        #expect(mixed.sourceList == ["Antenna", "Cable"])
        let many = "[" + (0..<40).map { "\"S\($0)\"" }.joined(separator: ",") + "]"
        let capped = try #require(HDHomeRunLineupStatus.decode(Data(#"{"SourceList":\#(many)}"#.utf8)))
        #expect(capped.sourceList.count == HDHomeRunLineupStatus.maximumSources)
        #expect(HDHomeRunLineupStatus.decode(Data(#"{"SourceList":"Antenna"}"#.utf8))?.sourceList == [])
    }

    // MARK: The POST

    /// Every `HDHomeRunHTTP` but `AppDelegate`'s posts nothing: the default, and one made with only a fetch (as tests
    /// and discovery make them).
    @Test func onlyAnExplicitLivePostSends() async {
        let device = AntennaLineupTests.device(host: "10.0.0.41")
        StubTunerProtocol.serve("http://10.0.0.41/lineup.post?scan=abort", body: Data())
        #expect(await HDHomeRunHTTP().abortScan(on: device) == nil)
        #expect(await HDHomeRunHTTP(fetch: { _, _, _ in nil }).startScan(on: device, status: Self.idle()) == nil)
        #expect(await AntennaSource().http.abortScan(on: device) == nil)
        #expect(!StubTunerProtocol.wasRequested("http://10.0.0.41/lineup.post?scan=abort"))
    }

    /// The scan requests go to the URLs above with the 5 s timeout; an invalid source sends nothing.
    @Test func scanRequestsPostTheBuiltURLs() async {
        nonisolated final class Recorder: @unchecked Sendable {
            let lock = NSLock()
            var calls: [String] = []
        }
        let recorder = Recorder()
        let http = HDHomeRunHTTP(fetch: { _, _, _ in nil }, post: { url, timeout in
            recorder.lock.withLock { recorder.calls.append("\(url.absoluteString) \(timeout)") }
            return 200
        })
        let device = AntennaLineupTests.device()
        #expect(await http.startScan(on: device, status: Self.idle()) == 200)
        #expect(await http.abortScan(on: device) == 200)
        #expect(await http.startScan(on: device, status: Self.idle(source: "Antenna&favorite=x5.1",
                                                                    list: ["Antenna&favorite=x5.1"])) == nil)
        #expect(recorder.calls == ["http://10.0.0.9/lineup.post?scan=start&source=Antenna 5.0",
                                   "http://10.0.0.9/lineup.post?scan=abort 5.0"])
    }

    @Test func livePostIsAPostWithAnEmptyBody() async {
        let url = "http://10.0.0.42/lineup.post?scan=abort"
        StubTunerProtocol.serve(url, body: Data("<html>ok</html>".utf8))
        #expect(await HDHomeRunHTTP.livePost(URL(string: url)!, timeout: HDHomeRunHTTP.postTimeout,
                                             session: StubTunerProtocol.session()) == 200)
        #expect(StubTunerProtocol.method(of: url) == "POST")
        #expect(StubTunerProtocol.bodyLength(of: url) == 0)
        // Another status is returned as it is; a body over the cap still gives the status.
        let refused = "http://10.0.0.43/lineup.post?scan=abort"
        StubTunerProtocol.serve(refused, status: 403, body: Data(repeating: 0x41, count: HDHomeRunHTTP.smallMaxBytes * 2))
        #expect(await HDHomeRunHTTP.livePost(URL(string: refused)!, timeout: HDHomeRunHTTP.postTimeout,
                                             session: StubTunerProtocol.session()) == 403)
    }

    @Test func livePostFollowsNoRedirect() async {
        let url = "http://10.0.0.44/lineup.post?scan=abort"
        let target = "http://10.0.0.45/lineup.post?scan=abort"
        StubTunerProtocol.serve(url, status: 302, headers: ["Location": target], body: Data())
        StubTunerProtocol.serve(target, body: Data())
        #expect(await HDHomeRunHTTP.livePost(URL(string: url)!, timeout: HDHomeRunHTTP.postTimeout,
                                             session: StubTunerProtocol.session()) == 302)
        #expect(!StubTunerProtocol.wasRequested(target))
    }

    @Test func livePostToADisallowedHostIsNeverSent() async {
        for url in ["http://203.0.113.7/lineup.post?scan=abort", "http://hdhomerun.local/lineup.post?scan=abort",
                    "https://10.0.0.46/lineup.post?scan=abort", "http://user@10.0.0.47/lineup.post?scan=abort"] {
            StubTunerProtocol.serve(url, body: Data())
            #expect(await HDHomeRunHTTP.livePost(URL(string: url)!, timeout: HDHomeRunHTTP.postTimeout,
                                                 session: StubTunerProtocol.session()) == nil, "\(url)")
            #expect(!StubTunerProtocol.wasRequested(url), "\(url)")
        }
    }
}
