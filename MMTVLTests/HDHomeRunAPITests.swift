import Foundation
import Testing
@testable import MMTVL

/// Serves canned tuner responses (status, headers, body) by URL, for `HDHomeRunHTTP.liveFetch`, and records what
/// was asked for. A 3xx with a Location is a real redirect (`wasRedirectedTo`), so the session's redirect delegate
/// decides whether it is followed. Never the network.
nonisolated final class StubTunerProtocol: URLProtocol, @unchecked Sendable {
    struct Canned: Sendable {
        var status: Int
        var headers: [String: String]
        var body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var canned: [String: Canned] = [:]
    nonisolated(unsafe) private static var requested: [String] = []
    /// M7j L18: each request's method and body length, by URL.
    nonisolated(unsafe) private static var methods: [String: String] = [:]
    nonisolated(unsafe) private static var bodyLengths: [String: Int] = [:]

    static func serve(_ url: String, status: Int = 200, headers: [String: String] = [:], body: Data) {
        lock.withLock { canned[url] = Canned(status: status, headers: headers, body: body) }
    }

    static func wasRequested(_ url: String) -> Bool {
        lock.withLock { requested.contains(url) }
    }

    /// M7j L18: the method `url` was asked with ("GET", "POST"); nil when it never was.
    static func method(of url: String) -> String? {
        lock.withLock { methods[url] }
    }

    /// M7j L18: the body length `url` was sent with (0 for none or an empty one).
    static func bodyLength(of url: String) -> Int? {
        lock.withLock { bodyLengths[url] }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubTunerProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let response = Self.lock.withLock { () -> Canned? in
            Self.requested.append(url.absoluteString)
            Self.methods[url.absoluteString] = request.httpMethod ?? "GET"
            Self.bodyLengths[url.absoluteString] = request.httpBody?.count ?? 0
            return Self.canned[url.absoluteString]
        }
        guard let response,
              let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1",
                                         headerFields: response.headers)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        if (300...399).contains(response.status), let location = response.headers["Location"],
           let target = URL(string: location) {
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: http)
            // Ended like a real redirect response: no body. If the redirect isn't followed, this is the response.
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        // In pieces, like a real body.
        var offset = 0
        while offset < response.body.count {
            let end = min(offset + 4096, response.body.count)
            client?.urlProtocol(self, didLoad: response.body.subdata(in: offset..<end))
            offset = end
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// M7j: the tuner's HTTP API. Step 2: the live fetch's status, redirect and size rules (QA). Step 3: the lineup,
/// `status.json` and `lineup_status.json` models and their fetches. Fake LAN addresses and DeviceIDs only.
struct HDHomeRunAPITests {
    static func fetch(_ url: String, maxBytes: Int = HDHomeRunHTTP.smallMaxBytes) async -> Data? {
        await HDHomeRunHTTP.liveFetch(URL(string: url)!, maxBytes: maxBytes, timeout: HDHomeRunHTTP.timeout,
                                      session: StubTunerProtocol.session())
    }

    @Test func okUnderTheCapGivesTheBytes() async {
        let body = Data(repeating: 0x41, count: HDHomeRunHTTP.smallMaxBytes)
        StubTunerProtocol.serve("http://10.0.0.21/discover.json", headers: ["Content-Length": "\(body.count)"],
                                body: body)
        #expect(await Self.fetch("http://10.0.0.21/discover.json") == body)
        // Without a Content-Length too.
        StubTunerProtocol.serve("http://10.0.0.22/discover.json", body: Data("{}".utf8))
        #expect(await Self.fetch("http://10.0.0.22/discover.json") == Data("{}".utf8))
    }

    /// The redirect reaches `RedirectBlocker`, which refuses it: its target is never asked, and the 302 gives nil.
    @Test func redirectGivesNil() async {
        StubTunerProtocol.serve("http://10.0.0.23/discover.json", status: 302,
                                headers: ["Location": "http://10.0.0.24/discover.json"], body: Data())
        StubTunerProtocol.serve("http://10.0.0.24/discover.json", body: Data("{}".utf8))
        #expect(await Self.fetch("http://10.0.0.23/discover.json") == nil)
        #expect(StubTunerProtocol.wasRequested("http://10.0.0.23/discover.json"))
        #expect(!StubTunerProtocol.wasRequested("http://10.0.0.24/discover.json"))
    }

    @Test func notFoundGivesNil() async {
        StubTunerProtocol.serve("http://10.0.0.25/discover.json", status: 404, body: Data("{}".utf8))
        #expect(await Self.fetch("http://10.0.0.25/discover.json") == nil)
    }

    @Test func bodyOverTheCapGivesNil() async {
        let body = Data(repeating: 0x41, count: HDHomeRunHTTP.smallMaxBytes + 1)
        // Announced by Content-Length, and not announced.
        StubTunerProtocol.serve("http://10.0.0.26/discover.json", headers: ["Content-Length": "\(body.count)"],
                                body: body)
        #expect(await Self.fetch("http://10.0.0.26/discover.json") == nil)
        StubTunerProtocol.serve("http://10.0.0.27/discover.json", body: body)
        #expect(await Self.fetch("http://10.0.0.27/discover.json") == nil)
    }

    @Test func disallowedURLIsNeverRequested() async {
        StubTunerProtocol.serve("http://203.0.113.5/discover.json", body: Data("{}".utf8))
        StubTunerProtocol.serve("http://hdhomerun.local/discover.json", body: Data("{}".utf8))
        #expect(await Self.fetch("http://203.0.113.5/discover.json") == nil)
        #expect(await Self.fetch("http://hdhomerun.local/discover.json") == nil)
    }

    // MARK: Step 3: lineup.json

    @Test func lineupDecodesTheRealKeys() throws {
        // The keys of the user's tuner's lineup.json (*Research*), plus `?show=found`'s, at fake addresses.
        let json = """
        [
          {"GuideNumber":"2.1","GuideName":"WTST-HD","VideoCodec":"MPEG2","AudioCodec":"AC3","HD":1,"Favorite":1,
           "SignalStrength":100,"SignalQuality":92,"URL":"http://10.0.0.9:5004/auto/v2.1"},
          {"GuideNumber":"26.12","GuideName":"JTST","VideoCodec":"H264","AudioCodec":"AC3",
           "URL":"http://10.0.0.9:5004/auto/v26.12"},
          {"GuideNumber":"4.1","GuideName":"WDRM","Tags":"favorite, DRM","DRM":true,"Enabled":0,"Subscribed":0,
           "Demo":1,"URL":"http://10.0.0.9:5004/auto/v4.1"},
          {"GuideNumber":702,"HD":true,"DRM":"1","SignalStrength":"strong","URL":"http://10.0.0.9:5004/auto/v702"},
          {"GuideNumber":"8.1","GuideName":"WOLD","DRM":1,"URL":"http://10.0.0.9:5004/auto/v8.1"},
          {"GuideName":"NO NUMBER","URL":"http://10.0.0.9:5004/auto/v9.9"},
          {"GuideNumber":"9.8","GuideName":"NO URL"},
          {"GuideNumber":"9.7","URL":5004},
          "not an object"
        ]
        """
        let entries = try #require(HDHomeRunLineupEntry.decodeLineup(Data(json.utf8)))
        #expect(entries.map(\.guideNumber) == ["2.1", "26.12", "4.1", "702", "8.1"])
        let first = entries[0]
        #expect(first.guideName == "WTST-HD")
        #expect(first.videoCodec == "MPEG2")
        #expect(first.audioCodec == "AC3")
        #expect(first.url == "http://10.0.0.9:5004/auto/v2.1")
        #expect(first.hd == true)
        #expect(first.favorite == true)
        #expect(first.signalStrength == 100)
        #expect(first.signalQuality == 92)
        #expect(first.drm == nil && first.enabled == nil && first.subscribed == nil && first.tags.isEmpty)
        #expect(!first.isDRM && first.isAvailable)
        let second = entries[1]
        #expect(second.hd == nil && second.favorite == nil && second.signalStrength == nil)
        let protected = entries[2]
        #expect(protected.tags == ["favorite", "drm"])
        #expect(protected.drm == true && protected.isDRM)
        #expect(protected.enabled == false && protected.subscribed == false && !protected.isAvailable)
        // Other types: a number GuideNumber reads as text, a string DRM or SignalStrength as missing.
        let odd = entries[3]
        #expect(odd.hd == true)
        #expect(odd.drm == nil && !odd.isDRM)
        #expect(odd.signalStrength == nil)
        // Older firmware's integer flag (QA minor).
        let older = entries[4]
        #expect(older.drm == true && older.tags.isEmpty && older.isDRM)
        #expect(HDHomeRunLineupEntry.decodeLineup(Data("{}".utf8)) == nil)
        #expect(HDHomeRunLineupEntry.decodeLineup(Data("[]".utf8)) == [])
    }

    @Test func lineupEntryHidesItsURL() {
        let entry = HDHomeRunLineupEntry(guideNumber: "5.1", guideName: "WTST", url: "http://10.0.0.9:5004/auto/v5.1")
        for text in [String(describing: entry), String(reflecting: entry), "\(entry)", String(describing: [entry])] {
            #expect(!text.contains("10.0.0.9"))
            #expect(text.contains("5.1"))
        }
        // Security low 4: control, bidi and line characters never reach a description, and the number is capped.
        let hostile = HDHomeRunLineupEntry(guideNumber: "5.1\n" + String(repeating: "9", count: 40),
                                           guideName: "\u{202E}WTST\nFAKE LOG LINE\u{200B}",
                                           url: "http://10.0.0.9:5004/auto/v5.1")
        for text in [String(describing: hostile), String(reflecting: hostile), String(describing: [hostile])] {
            #expect(!text.contains("\u{202E}") && !text.contains("\n") && !text.contains("\u{200B}"), "\(text)")
            #expect(text.contains("WTSTFAKE LOG LINE"))
            #expect(!text.contains(String(repeating: "9", count: 14)))
            #expect(!text.contains("10.0.0.9"))
        }
    }

    // MARK: Step 3: status.json, lineup_status.json

    @Test func statusBusyCount() throws {
        let idle = try #require(HDHomeRunTunerStatus.decode(Data(#"[{"Resource":"tuner0"},{"Resource":"tuner1"}]"#.utf8)))
        #expect(idle == [HDHomeRunTunerStatus(resource: "tuner0", isBusy: false),
                         HDHomeRunTunerStatus(resource: "tuner1", isBusy: false)])
        #expect(HDHomeRunTunerStatus.busyCount(idle) == 0)
        let json = """
        [{"Resource":"tuner0","VctNumber":"5.1","VctName":"WTST-HD","Frequency":177000000,"SignalStrengthPercent":100,
          "SignalQualityPercent":100,"SymbolQualityPercent":100,"TargetIP":"10.0.0.30","NetworkRate":4300000},
         {"Resource":"tuner1"}]
        """
        let oneBusy = try #require(HDHomeRunTunerStatus.decode(Data(json.utf8)))
        #expect(oneBusy.map(\.isBusy) == [true, false])
        #expect(HDHomeRunTunerStatus.busyCount(oneBusy) == 1)
        // Busy means any key beyond Resource; TargetIP is never kept.
        let other = try #require(HDHomeRunTunerStatus.decode(Data(#"[{"Resource":"tuner0","Frequency":0},{}]"#.utf8)))
        #expect(HDHomeRunTunerStatus.busyCount(other) == 1)
        #expect(other[1].resource == nil)
        #expect(!String(reflecting: oneBusy).contains("10.0.0.30"))
        #expect(HDHomeRunTunerStatus.decode(Data(#"{"Resource":"tuner0"}"#.utf8)) == nil)
    }

    @Test func scanInProgressDecodes() {
        let idle = #"{"ScanInProgress":0,"ScanPossible":1,"Source":"Antenna","SourceList":["Antenna","Cable"]}"#
        // M7j step 9b: the idle keys decode too (`HDHomeRunScanTests`).
        #expect(HDHomeRunLineupStatus.decode(Data(idle.utf8)) == HDHomeRunLineupStatus(
            scanInProgress: false, scanPossible: true, source: "Antenna", sourceList: ["Antenna", "Cable"]))
        let scanning = #"{"ScanInProgress":1,"Progress":45,"Found":120}"#
        #expect(HDHomeRunLineupStatus.decode(Data(scanning.utf8))?.scanInProgress == true)
        #expect(HDHomeRunLineupStatus.decode(Data(#"{"ScanInProgress":true}"#.utf8))?.scanInProgress == true)
        #expect(HDHomeRunLineupStatus.decode(Data(#"{"ScanInProgress":"1"}"#.utf8))?.scanInProgress == false)
        #expect(HDHomeRunLineupStatus.decode(Data("{}".utf8))?.scanInProgress == false)
        #expect(HDHomeRunLineupStatus.decode(Data("[]".utf8)) == nil)
    }

    // MARK: Step 3: the fetches

    /// Records each fetch's URL, cap and timeout; answers from `bodies`.
    nonisolated final class FetchRecorder: @unchecked Sendable {
        struct Call: Equatable { var url: String; var maxBytes: Int; var timeout: TimeInterval }
        private let lock = NSLock()
        private var recorded: [Call] = []
        let bodies: [String: Data]

        init(_ bodies: [String: String]) {
            self.bodies = bodies.mapValues { Data($0.utf8) }
        }

        var calls: [Call] { lock.withLock { recorded } }

        var http: HDHomeRunHTTP {
            HDHomeRunHTTP { url, maxBytes, timeout in
                self.lock.withLock { self.recorded.append(Call(url: url.absoluteString, maxBytes: maxBytes,
                                                               timeout: timeout)) }
                return self.bodies[url.absoluteString]
            }
        }
    }

    @Test func fetchesUseTheDeviceURLsAndCaps() async {
        let device = AntennaLineupTests.device()
        let recorder = FetchRecorder([
            "http://10.0.0.9/lineup.json": #"[{"GuideNumber":"5.1","URL":"http://10.0.0.9:5004/auto/v5.1"}]"#,
            "http://10.0.0.9/status.json": #"[{"Resource":"tuner0","VctNumber":"5.1"},{"Resource":"tuner1"}]"#,
            "http://10.0.0.9/lineup_status.json": #"{"ScanInProgress":1}"#,
        ])
        #expect(await recorder.http.lineup(of: device)?.map(\.guideNumber) == ["5.1"])
        #expect(await recorder.http.tunerStatus(of: device).map(HDHomeRunTunerStatus.busyCount) == 1)
        #expect(await recorder.http.lineupStatus(of: device)?.scanInProgress == true)
        #expect(recorder.calls == [
            .init(url: "http://10.0.0.9/lineup.json", maxBytes: HDHomeRunHTTP.lineupMaxBytes,
                  timeout: HDHomeRunHTTP.lineupTimeout),
            .init(url: "http://10.0.0.9/status.json", maxBytes: HDHomeRunHTTP.smallMaxBytes,
                  timeout: HDHomeRunHTTP.timeout),
            .init(url: "http://10.0.0.9/lineup_status.json", maxBytes: HDHomeRunHTTP.smallMaxBytes,
                  timeout: HDHomeRunHTTP.timeout),
        ])
    }

    /// L5 and security low 2: a LineupURL that fails discovery's rule (another host, a percent-encoded host, a port
    /// other than 80, a query or fragment) is never fetched.
    @Test func lineupURLOnAnotherHostIsNotFetched() async {
        for lineupURL in ["http://10.0.0.10/lineup.json", "http://10.0.0%2E9/lineup.json",
                          "http://10.0.0.9:5004/lineup.json", "http://10.0.0.9/lineup.json?show=found",
                          "http://10.0.0.9/lineup.json#x", "https://10.0.0.9/lineup.json"] {
            var device = AntennaLineupTests.device()
            device.lineupURL = URL(string: lineupURL)!
            let recorder = FetchRecorder([lineupURL: "[]"])
            #expect(await recorder.http.lineup(of: device) == nil, "\(lineupURL)")
            #expect(recorder.calls.isEmpty, "\(lineupURL)")
        }
        // Port 80 written out is fine.
        var device = AntennaLineupTests.device()
        device.lineupURL = URL(string: "http://10.0.0.9:80/lineup.json")!
        let recorder = FetchRecorder(["http://10.0.0.9:80/lineup.json": "[]"])
        #expect(await recorder.http.lineup(of: device) == [])
    }

    @Test func failedOrUndecodableFetchesGiveNil() async {
        let device = AntennaLineupTests.device()
        let recorder = FetchRecorder(["http://10.0.0.9/lineup.json": "{}", "http://10.0.0.9/status.json": "nope"])
        #expect(await recorder.http.lineup(of: device) == nil)
        #expect(await recorder.http.tunerStatus(of: device) == nil)
        #expect(await recorder.http.lineupStatus(of: device) == nil)
    }
}
