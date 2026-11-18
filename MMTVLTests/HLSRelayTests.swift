import Foundation
import Testing
@testable import MMTVL

/// The relay on a real loopback port with a fake upstream (M7c L30).
struct HLSRelayTests {
    /// Serves the fixtures by URL; counts fetches; "/forbidden" answers 403.
    nonisolated final class Upstream: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]
        private var hosts: [String] = []
        private let bodies: [String: String]

        init(_ bodies: [String: String]) { self.bodies = bodies }

        func count(_ path: String) -> Int { lock.withLock { counts[path, default: 0] } }
        /// Every fetched URL's scheme and host ("https://cdn.example").
        var fetchedOrigins: [String] { lock.withLock { hosts } }

        var fetch: HLSRelay.Fetch {
            { [self] url, _ in
                lock.withLock {
                    counts[url.path(), default: 0] += 1
                    hosts.append("\(url.scheme ?? "")://\(url.host() ?? "")")
                }
                if url.path() == "/forbidden" {
                    return HLSRelay.Upstream(data: Data(), contentType: nil, status: 403, finalURL: url)
                }
                guard let body = bodies[url.path()] else { throw URLError(.fileDoesNotExist) }
                let type = url.pathExtension == "m3u8" ? "application/vnd.apple.mpegurl" : "video/mp2t"
                return HLSRelay.Upstream(data: Data(body.utf8), contentType: type, status: 200, finalURL: url)
            }
        }
    }

    static let fixtures: [String: String] = [
        "/live/ch1/master.m3u8": HLSPlaylistTests.master,
        "/live/ch1/video/index.m3u8": HLSPlaylistTests.media,
        "/live/ch1/audio/index.m3u8": HLSPlaylistTests.media,
        "/live/ch1/video/seg102.ts": "VIDEO-102",
        "/live/ch1/audio/seg102.ts": "AUDIO-102",
    ]

    private func startedRelay(_ upstream: Upstream) async throws -> HLSRelay {
        let relay = HLSRelay(fetch: upstream.fetch)
        relay.start()
        for _ in 0..<200 where relay.port == nil { try await Task.sleep(for: .milliseconds(10)) }
        try #require(relay.port != nil)
        return relay
    }

    private func get(_ url: URL, range: String? = nil) async throws -> (String, Int, String?) {
        var request = URLRequest(url: url)
        if let range { request.setValue(range, forHTTPHeaderField: "Range") }
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        let http = response as! HTTPURLResponse
        return (String(decoding: data, as: UTF8.self), http.statusCode, http.value(forHTTPHeaderField: "Content-Range"))
    }

    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    private let master = URL(string: "https://cdn.example/live/ch1/master.m3u8")!

    @Test func servesARewrittenPlaylistAndPrefetchesWhatFollows() async throws {
        let upstream = Upstream(Self.fixtures)
        let relay = try await startedRelay(upstream)
        defer { relay.stop() }
        let local = try #require(relay.localURL(for: master))
        #expect(local.host() == "127.0.0.1")
        #expect(!local.absoluteString.contains("cdn.example"))

        let (body, status, _) = try await get(local)
        #expect(status == 200)
        #expect(body.contains("http://127.0.0.1:\(relay.port!)/r/"))
        #expect(!body.contains("cdn.example"))

        // The media playlists and their start segments are fetched without being asked for.
        await settle { upstream.count("/live/ch1/video/seg102.ts") == 1 && upstream.count("/live/ch1/audio/seg102.ts") == 1 }
        #expect(upstream.count("/live/ch1/video/index.m3u8") == 1)
        #expect(upstream.count("/live/ch1/audio/index.m3u8") == 1)
        #expect(upstream.count("/live/ch1/video/seg102.ts") == 1)

        // ffmpeg opening the master again, then the playlist and segment, all come from the cache.
        _ = try await get(local)
        let videoPlaylist = try #require(relay.localURL(for: URL(string: "https://cdn.example/live/ch1/video/index.m3u8?token=abc")!))
        let (playlist, _, _) = try await get(videoPlaylist)
        #expect(playlist.contains("/r/"))
        let segment = try #require(relay.localURL(for: URL(string: "https://cdn.example/live/ch1/video/seg102.ts")!))
        let (data, segmentStatus, _) = try await get(segment)
        #expect(segmentStatus == 200)
        #expect(data == "VIDEO-102")
        #expect(upstream.count("/live/ch1/master.m3u8") == 1)
        #expect(upstream.count("/live/ch1/video/index.m3u8") == 1)
        #expect(upstream.count("/live/ch1/video/seg102.ts") == 1)
    }

    @Test func aRangeResumesASegment() async throws {
        let relay = try await startedRelay(Upstream(Self.fixtures))
        defer { relay.stop() }
        let segment = try #require(relay.localURL(for: URL(string: "https://cdn.example/live/ch1/video/seg102.ts")!))
        let (data, status, contentRange) = try await get(segment, range: "bytes=6-")
        #expect(status == 206)
        #expect(data == "102")
        #expect(contentRange == "bytes 6-8/9")
    }

    @Test func unknownTokensAndUpstreamErrors() async throws {
        let relay = try await startedRelay(Upstream(Self.fixtures))
        defer { relay.stop() }
        let unknown = URL(string: "http://127.0.0.1:\(relay.port!)/r/nope/x")!
        #expect(try await get(unknown).1 == 404)
        let forbidden = try #require(relay.localURL(for: URL(string: "https://cdn.example/forbidden")!))
        #expect(try await get(forbidden).1 == 403)
        let missing = try #require(relay.localURL(for: URL(string: "https://cdn.example/missing.ts")!))
        #expect(try await get(missing).1 == 502)
    }

    /// Security review item 5: a playlist naming a local file or a Mac/LAN address that isn't the stream's own host
    /// gets neither fetched nor rewritten to the relay; the stream's normal https URIs still are.
    @Test func refusesNonWebAndInternalURIs() async throws {
        let master = """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aac",NAME="Local",URI="file:///etc/hosts"
        #EXT-X-STREAM-INF:BANDWIDTH=1
        file:///etc/hosts
        #EXT-X-STREAM-INF:BANDWIDTH=2
        http://127.0.0.1:1/x
        #EXT-X-STREAM-INF:BANDWIDTH=3
        http://192.168.1.5/lan.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=4
        http://[::1]:1/v6
        #EXT-X-STREAM-INF:BANDWIDTH=5
        video/index.m3u8
        """
        var fixtures = Self.fixtures
        fixtures["/live/ch1/master.m3u8"] = master
        let upstream = Upstream(fixtures)
        let relay = try await startedRelay(upstream)
        defer { relay.stop() }
        let local = try #require(relay.localURL(for: self.master))

        let (body, status, _) = try await get(local)
        #expect(status == 200)
        #expect(!body.contains("/etc/hosts"))
        #expect(!body.contains("file:"))
        #expect(!body.contains("127.0.0.1:1/"))
        #expect(!body.contains("192.168.1.5"))
        #expect(!body.contains("::1"))
        // Only the https media playlist is rewritten to the relay, and it's prefetched with its start segment.
        #expect(body.components(separatedBy: "/r/").count == 2)
        #expect(body.contains("http://127.0.0.1:\(relay.port!)/r/"))
        await settle { upstream.count("/live/ch1/video/seg102.ts") == 1 }
        #expect(upstream.count("/live/ch1/video/seg102.ts") == 1)
        #expect(Set(upstream.fetchedOrigins) == ["https://cdn.example"])
        #expect(upstream.count("/etc/hosts") == 0)
        #expect(upstream.count("/x") == 0)

        // Registering or prefetching a non-http(s) URL does nothing either.
        #expect(relay.localURL(for: URL(string: "file:///etc/hosts")!) == nil)
        #expect(await relay.fetch(URL(string: "file:///etc/hosts")!, stream: URL(string: "file:///etc/hosts")!) == nil)
        #expect(await relay.fetch(URL(string: "http://127.0.0.1:1/x")!, stream: self.master) == nil)
        #expect(Set(upstream.fetchedOrigins) == ["https://cdn.example"])
        // Re-review L2: the refusals are recorded for the stream (and its media playlist), so the player skips its
        // direct retry; another stream has none.
        #expect(relay.refusedSomething(forStreamOf: self.master))
        #expect(relay.refusedSomething(forStreamOf: URL(string: "https://cdn.example/live/ch1/video/index.m3u8")!))
        #expect(!relay.refusedSomething(forStreamOf: URL(string: "https://cdn.example/live/ch2/master.m3u8")!))
    }

    /// A stream on a LAN server keeps working: its own host is allowed, a link-local host isn't.
    @Test func aLANStreamMayUseItsOwnHost() async throws {
        let master = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1
        video/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2
        http://169.254.1.6/other.m3u8
        """
        let upstream = Upstream(["/live/master.m3u8": master, "/live/video/index.m3u8": HLSPlaylistTests.media,
                                 "/live/video/seg102.ts": "LAN-102"])
        let relay = try await startedRelay(upstream)
        defer { relay.stop() }
        let local = try #require(relay.localURL(for: URL(string: "http://192.168.1.5:8080/live/master.m3u8")!))
        let (body, status, _) = try await get(local)
        #expect(status == 200)
        #expect(body.components(separatedBy: "/r/").count == 2)
        #expect(!body.contains("169.254.1.6"))
        await settle { upstream.count("/live/video/seg102.ts") == 1 }
        #expect(upstream.count("/live/video/seg102.ts") == 1)
        #expect(Set(upstream.fetchedOrigins) == ["http://192.168.1.5"])
    }

    @Test func urlPolicy() {
        let cdn = URL(string: "https://cdn.example/master.m3u8")!
        let lan = URL(string: "http://192.168.1.5:8080/master.m3u8")!
        func allows(_ text: String, _ stream: URL) -> Bool { RelayURLPolicy.allows(URL(string: text)!, stream: stream) }
        #expect(allows("https://cdn2.example/seg.ts", cdn))
        #expect(allows("HTTP://cdn.example/seg.ts", cdn))
        #expect(!allows("file:///etc/hosts", cdn))
        #expect(!allows("data:text/plain,hi", cdn))
        #expect(!allows("ftp://cdn.example/x", cdn))
        for lanURL in ["http://127.0.0.1:1/x", "http://127.1/x", "http://2130706433/x", "http://0x7f.0.0.1/x",
                       "http://localhost/x", "http://LocalHost./x", "http://[::1]/x", "http://[::ffff:127.0.0.1]/x",
                       "http://0.0.0.0/x", "http://10.0.0.1/x", "http://172.16.0.1/x", "http://192.168.1.5/x",
                       "http://169.254.169.254/x", "http://[fe80::1%25en0]/x", "http://[fd00::1]/x",
                       "http://nas.local/x", "http://router/x"] {
            #expect(!allows(lanURL, cdn), "\(lanURL)")
        }
        #expect(allows("http://192.168.1.5/seg.ts", lan))
        #expect(allows("https://192.168.1.5:9000/seg.ts", lan))
        #expect(!allows("http://127.0.0.1/seg.ts", lan))
        #expect(allows("https://cdn.example/seg.ts", lan))
        #expect(!RelayURLPolicy.isInternal("8.8.8.8"))
        #expect(!RelayURLPolicy.isInternal("cdn.example"))
        #expect(!RelayURLPolicy.isInternal("2001:4860:4860::8888"))
        #expect(!RelayURLPolicy.isInternal("172.32.0.1"))
    }

    /// Pre-release lows (c): a stream on a LAN host (address or LAN name) may reach another LAN device by its
    /// private address (a Threadfin/xTeVe proxy to a tuner); never the Mac (loopback, its own addresses), link-local,
    /// 0/8, shared addresses or LAN names; a public stream still reaches no internal host.
    @Test func aLANStreamMayReachAnotherLANDevice() {
        let own = { ["192.168.1.5", "fd00::5", "127.0.0.1", "::1"] }
        func allows(_ text: String, _ stream: String) -> Bool {
            RelayURLPolicy.allows(URL(string: text)!, stream: URL(string: stream)!, ownAddresses: own)
        }
        for entry in ["http://192.168.1.9:34400/auto/v5.1", "http://10.0.0.2/live.m3u8", "http://172.20.1.1/x",
                      "http://[fd12::9]:34400/x", "http://threadfin.local:34400/x", "http://xteve/x",
                      "http://nas.lan/x", "http://tuner.home.arpa/x"] {
            #expect(allows("http://192.168.1.20:5004/auto/v5.1", entry), "\(entry)")
            #expect(allows("http://10.1.2.3/seg.ts", entry), "\(entry)")
            #expect(allows("http://[fd00::20]:5004/x", entry), "\(entry)")
            #expect(allows("http://[::ffff:192.168.1.20]/x", entry), "\(entry)")
            for refused in ["http://127.0.0.1:1/x", "http://127.1/x", "http://localhost/x", "http://[::1]/x",
                            "http://0.0.0.0/x", "http://0.1.2.3/x", "http://169.254.169.254/x",
                            "http://[fe80::1%25en0]/x", "http://100.64.0.1/x", "http://192.168.1.5/x",
                            "http://[fd00::5]/x", "http://[::ffff:127.0.0.1]/x", "http://other.local/x",
                            "http://router/x", "http://255.255.255.255/x"] {
                #expect(!allows(refused, entry), "\(entry) → \(refused)")
            }
        }
        // Public, loopback, link-local and shared entries reach no other internal host.
        for entry in ["https://cdn.example/x", "http://127.0.0.1:8080/x", "http://localhost:8080/x",
                      "http://169.254.1.1/x", "http://100.64.0.9/x", "http://[fe80::9%25en0]/x"] {
            #expect(!allows("http://192.168.1.20/x", entry), "\(entry)")
            #expect(!allows("http://[fd00::20]/x", entry), "\(entry)")
        }
        // With the Mac's real addresses: none of its private ones is reachable from a LAN entry.
        for address in LANAddress.ownAddresses() where RelayURLPolicy.isPrivateLANAddress(address) {
            let host = address.contains(":") ? "[\(address)]" : address
            #expect(!RelayURLPolicy.allows(URL(string: "http://\(host)/x")!,
                                           stream: URL(string: "http://192.168.250.250/x")!))
        }
    }

    /// Pre-release lows (c): the relay's redirect guard and the stream resolver agree with the policy: a LAN entry
    /// that redirects to another LAN device resolves and plays; one that redirects to the Mac doesn't.
    @Test func aLANEntryMayRedirectToAnotherLANDevice() async throws {
        let entry = URL(string: "http://192.168.77.2:34400/stream/lows-c")!
        let tuner = "http://192.168.77.20:5004/auto/v5.1"
        StubTunerProtocol.serve(entry.absoluteString, status: 302, headers: ["Location": tuner], body: Data())
        StubTunerProtocol.serve(tuner, headers: ["Content-Type": "video/mp2t"], body: Data("TS".utf8))
        let resolver = StreamResolver(resolve: { try await StreamResolver.liveResolve($0, session: StubTunerProtocol.session()) })
        #expect(await resolver.resolve(entry).absoluteString == tuner)
        let fetched = try await HLSRelay.liveFetch(entry, stream: entry, session: StubTunerProtocol.session())
        #expect(fetched.status == 200)
        #expect(!fetched.refusedRedirect)
        #expect(HLSRelay.RedirectGuard(stream: entry).follows(URL(string: tuner)))

        let toMac = URL(string: "http://192.168.77.2:34400/stream/lows-c-mac")!
        let loopback = "http://127.0.0.1:1/lows-c"
        StubTunerProtocol.serve(toMac.absoluteString, status: 302, headers: ["Location": loopback], body: Data())
        StubTunerProtocol.serve(loopback, body: Data("MAC".utf8))
        #expect(await resolver.resolve(toMac) == toMac)
        #expect(!StubTunerProtocol.wasRequested(loopback))
        #expect(!HLSRelay.RedirectGuard(stream: entry).follows(URL(string: loopback)))

        // A public entry still never reaches the LAN.
        let publicEntry = URL(string: "https://provider-lows-c.example/live/1")!
        let lanTarget = "http://192.168.77.21:5004/auto/v5.1"
        StubTunerProtocol.serve(publicEntry.absoluteString, status: 302, headers: ["Location": lanTarget], body: Data())
        StubTunerProtocol.serve(lanTarget, body: Data("TS".utf8))
        #expect(await resolver.resolve(publicEntry) == publicEntry)
        #expect(!StubTunerProtocol.wasRequested(lanTarget))
        #expect(!HLSRelay.RedirectGuard(stream: publicEntry).follows(URL(string: lanTarget)))
    }

    /// Security review item 5: the live fetch follows a CDN's redirect to another public host, never to the Mac, the
    /// LAN or a non-http(s) URL (the 3xx comes back instead); a LAN stream may still redirect on its own host.
    /// `StubTunerProtocol` makes each 3xx a real redirect for the session's delegate, without the network.
    @Test func liveFetchRefusesRedirectsToInternalHosts() async throws {
        let stream = URL(string: "https://redirect-cdn.example/live/master.m3u8")!
        func fetch(_ url: String, stream: URL) async throws -> HLSRelay.Upstream {
            try await HLSRelay.liveFetch(URL(string: url)!, stream: stream, session: StubTunerProtocol.session())
        }
        for (index, target) in ["http://127.0.0.1:1/x", "http://192.168.7.9/lan.m3u8", "http://[::1]:1/v6",
                                "file:///etc/hosts"].enumerated() {
            let from = "https://redirect-cdn.example/live/refused\(index).m3u8"
            StubTunerProtocol.serve(from, status: 302, headers: ["Location": target], body: Data())
            StubTunerProtocol.serve(target, body: Data("INTERNAL".utf8))
            let upstream = try await fetch(from, stream: stream)
            #expect(upstream.status == 302, "\(target)")
            #expect(upstream.data.isEmpty, "\(target)")
            #expect(upstream.finalURL.absoluteString == from, "\(target)")
            #expect(upstream.refusedRedirect, "\(target)")
            #expect(!StubTunerProtocol.wasRequested(target), "\(target)")
        }

        let publicFrom = "https://redirect-cdn.example/live/moved.m3u8"
        let publicTarget = "https://redirect-cdn2.example/live/moved.m3u8"
        StubTunerProtocol.serve(publicFrom, status: 302, headers: ["Location": publicTarget], body: Data())
        StubTunerProtocol.serve(publicTarget, headers: ["Content-Type": "application/vnd.apple.mpegurl"],
                                body: Data("#EXTM3U".utf8))
        let moved = try await fetch(publicFrom, stream: stream)
        #expect(StubTunerProtocol.wasRequested(publicTarget))
        #expect(moved.status == 200)
        #expect(moved.data == Data("#EXTM3U".utf8))
        #expect(moved.finalURL.absoluteString == publicTarget)
        #expect(!moved.refusedRedirect)

        let lanStream = URL(string: "http://192.168.7.5:8080/live/master.m3u8")!
        let lanFrom = "http://192.168.7.5:8080/live/old.m3u8"
        let lanTarget = "http://192.168.7.5:8080/live/new.m3u8"
        StubTunerProtocol.serve(lanFrom, status: 302, headers: ["Location": lanTarget], body: Data())
        StubTunerProtocol.serve(lanTarget, body: Data("LAN".utf8))
        #expect(try await fetch(lanFrom, stream: lanStream).status == 200)
        #expect(StubTunerProtocol.wasRequested(lanTarget))

        let guardForCDN = HLSRelay.RedirectGuard(stream: stream)
        #expect(guardForCDN.follows(URL(string: "https://other-cdn.example/seg.ts")))
        #expect(!guardForCDN.follows(URL(string: "http://192.168.1.5/seg.ts")))
        #expect(!guardForCDN.follows(URL(string: "http://localhost/seg.ts")))
        #expect(!guardForCDN.follows(nil))
    }

    /// Re-review L2: an M3U entry on a public host that redirects to the Mac isn't resolved to it: the resolver keeps
    /// the entry, the relay registers only the entry, refuses the same redirect when mpv asks (recording it, so the
    /// player won't go direct), and the Mac's address is never registered or requested. A redirect to another public
    /// host still resolves.
    @Test func streamResolverRefusesARedirectToTheMac() async throws {
        let entry = URL(string: "https://provider-l2.example/live/7.m3u8")!
        let target = "http://127.0.0.1:1/x"
        StubTunerProtocol.serve(entry.absoluteString, status: 302, headers: ["Location": target], body: Data())
        StubTunerProtocol.serve(target, body: Data("#EXTM3U".utf8))
        let resolver = StreamResolver(resolve: { try await StreamResolver.liveResolve($0, session: StubTunerProtocol.session()) })
        let resolved = await resolver.resolve(entry)
        #expect(resolved == entry)
        #expect(resolver.cached(entry) == nil)
        #expect(!StubTunerProtocol.wasRequested(target))

        // A resolver that hands back the Mac's address anyway is refused too.
        let lying = StreamResolver(resolve: { _ in URL(string: target)! })
        #expect(await lying.resolve(entry) == entry)
        #expect(lying.cached(entry) == nil)

        let relay = HLSRelay(fetch: { url, stream in
            try await HLSRelay.liveFetch(url, stream: stream, session: StubTunerProtocol.session())
        })
        relay.start()
        defer { relay.stop() }
        for _ in 0..<200 where relay.port == nil { try await Task.sleep(for: .milliseconds(10)) }
        let local = try #require(relay.localURL(for: resolved))
        let (_, status, _) = try await get(local)
        #expect(status == 302)
        #expect(relay.isRegistered(entry))
        #expect(!relay.isRegistered(URL(string: target)!))
        #expect(relay.refusedSomething(forStreamOf: entry))
        #expect(!StubTunerProtocol.wasRequested(target))

        let moving = URL(string: "https://provider-l2.example/live/8.m3u8")!
        let cdn = "https://cdn-l2.example/live/8.m3u8"
        StubTunerProtocol.serve(moving.absoluteString, status: 302, headers: ["Location": cdn], body: Data())
        StubTunerProtocol.serve(cdn, body: Data("#EXTM3U".utf8))
        #expect(await resolver.resolve(moving).absoluteString == cdn)
        #expect(!relay.refusedSomething(forStreamOf: URL(string: cdn)!))
    }

    @Test func noURLWhileStopped() {
        let relay = HLSRelay(fetch: Upstream([:]).fetch)
        #expect(relay.localURL(for: master) == nil)
    }

    @Test func rangeHeaderParsing() {
        #expect(HLSRelay.rangeStart(in: Data("GET / HTTP/1.1\r\nRange: bytes=100-\r\n\r\n".utf8)) == 100)
        #expect(HLSRelay.rangeStart(in: Data("GET / HTTP/1.1\r\nrange: bytes=0-\r\n\r\n".utf8)) == 0)
        #expect(HLSRelay.rangeStart(in: Data("GET / HTTP/1.1\r\nHost: x\r\n\r\n".utf8)) == nil)
    }
}
