import Foundation
import Network
import SystemConfiguration
import Testing
@testable import MMTVL

@MainActor
@Suite(.serialized)
struct RemoteServerTests {
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func servesThePageAndEchoesOverTheSocket() async throws {
        let server = RemoteServer()
        var closed: [RemoteSessionID] = []
        server.onMessage = { [weak server] id, _ in server?.send(.toast("echo"), to: id) }
        server.onSessionClosed = { closed.append($0) }
        server.start(httpPort: .any, socketPort: .any)
        defer { server.stop() }

        try await waitUntil { server.state == .running }
        #expect(server.state == .running)
        let httpPort = try #require(server.httpPort)
        let socketPort = try #require(server.socketPort)

        // HTTP
        let (body, response) = try await URLSession.shared.data(from: URL(string: "http://localhost:\(httpPort)/")!)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        #expect(http.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("text/html") == true)
        #expect(String(decoding: body, as: UTF8.self).contains("MMTVL Remote"))

        let (_, missing) = try await URLSession.shared.data(from: URL(string: "http://localhost:\(httpPort)/nope")!)
        #expect((missing as? HTTPURLResponse)?.statusCode == 404)

        // WebSocket round trip
        let task = URLSession.shared.webSocketTask(with: URL(string: "ws://localhost:\(socketPort)/")!)
        task.resume()
        try await task.send(.string(#"{"type":"textBegin"}"#))
        let reply = try await task.receive()
        guard case .string(let json) = reply else {
            Issue.record("Expected a text frame, got \(reply)")
            return
        }
        #expect(json == #"{"message":"echo","type":"toast"}"#)

        server.stop()
        #expect(server.state == .stopped)
        #expect(closed.count == 1)
        task.cancel(with: .goingAway, reason: nil)
    }

    // MARK: Security (pre-release review)

    private func echoServer(signInTimeout: TimeInterval = RemoteServer.defaultSignInTimeout,
                            authenticates: Bool = false) async throws -> (RemoteServer, http: UInt16, socket: UInt16) {
        let server = RemoteServer(signInTimeout: signInTimeout)
        server.onMessage = { [weak server] id, _ in
            if authenticates { server?.sessionAuthenticated(id) }
            server?.send(.toast("echo"), to: id)
        }
        server.start(httpPort: .any, socketPort: .any)
        try await waitUntil { server.state == .running }
        return (server, try #require(server.httpPort), try #require(server.socketPort))
    }

    private func socket(_ port: UInt16, origin: String? = nil) -> URLSessionWebSocketTask {
        var request = URLRequest(url: URL(string: "ws://127.0.0.1:\(port)/")!)
        if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
        let task = URLSession.shared.webSocketTask(with: request)
        task.resume()
        return task
    }

    /// True when a message round-trips (the session is open and served).
    private func echoes(_ task: URLSessionWebSocketTask) async -> Bool {
        do {
            try await task.send(.string(#"{"type":"textBegin"}"#))
            guard case .string(let json) = try await task.receive() else { return false }
            return json.contains("echo")
        } catch {
            return false
        }
    }

    /// High: a page on another site can't open the socket; the phone page's own origin and native clients can.
    @Test func refusesUpgradesFromAnotherOrigin() async throws {
        let (server, http, port) = try await echoServer()
        defer { server.stop() }
        var messages = 0
        let onMessage = server.onMessage
        server.onMessage = { messages += 1; onMessage?($0, $1) }

        let evil = socket(port, origin: "https://evil.example")
        #expect(await echoes(evil) == false)
        let rebound = socket(port, origin: "http://evil.example:\(http)")
        #expect(await echoes(rebound) == false)
        let third = socket(port, origin: "https://evil.example")
        #expect(await echoes(third) == false)
        #expect(messages == 0)
        // Refused upgrades are closed at once, so they don't hold the address's 3 waiting slots.
        try await Task.sleep(for: .milliseconds(100))

        let page = socket(port, origin: "http://127.0.0.1:\(http)")
        #expect(await echoes(page))
        let native = socket(port)
        #expect(await echoes(native))
        for task in [evil, rebound, third, page, native] { task.cancel(with: .goingAway, reason: nil) }
    }

    /// Low: 8 sockets that never sign in don't keep a phone out: at most 3 wait per address, and they're closed
    /// after the sign-in timeout, so the next one connects.
    @Test func silentSocketsTimeOutAndFreeTheirSlots() async throws {
        let (server, _, port) = try await echoServer(signInTimeout: 1.5)
        defer { server.stop() }
        let silent = (0..<8).map { _ in socket(port) }
        try await Task.sleep(for: .milliseconds(300))
        let early = socket(port)
        #expect(await echoes(early) == false)

        try await Task.sleep(for: .milliseconds(1800))
        let ninth = socket(port)
        #expect(await echoes(ninth))
        for task in silent + [early, ninth] { task.cancel(with: .goingAway, reason: nil) }
    }

    /// Low: a signed-in session stays past the timeout.
    @Test func authenticatedSessionsDontTimeOut() async throws {
        let (server, _, port) = try await echoServer(signInTimeout: 0.5, authenticates: true)
        defer { server.stop() }
        let task = socket(port)
        #expect(await echoes(task))
        try await Task.sleep(for: .milliseconds(900))
        #expect(await echoes(task))
        task.cancel(with: .goingAway, reason: nil)
    }

    /// Re-review L3: 16 sockets waiting to sign in from 6 addresses (3 + 3 + 3 + 3 + 2 + 2) fill the pool; a new one
    /// from a seventh address gets in by closing the oldest waiting one, never a signed-in session; an address that
    /// already has 3 waiting is still refused.
    @Test func aFullPendingPoolEvictsItsOldest() {
        let hosts = ["10.0.0.1", "10.0.0.2", "10.0.0.3", "10.0.0.4", "10.0.0.5", "10.0.0.6"]
        var entries = (1...8).map { PendingPool.Entry(id: $0, host: "10.0.0.\(100 + $0)", isAuthenticated: true) }
        var id = 9
        for (index, host) in hosts.enumerated() {
            for _ in 0..<(index < 4 ? 3 : 2) {
                entries.append(PendingPool.Entry(id: id, host: host, isAuthenticated: false))
                id += 1
            }
        }
        #expect(entries.count(where: { !$0.isAuthenticated }) == RemoteServer.maxPending)
        func admit(_ host: String?, _ entries: [PendingPool.Entry]) -> PendingPool.Decision {
            PendingPool.admit(host: host, sessions: entries, maxPending: RemoteServer.maxPending,
                              maxPendingPerHost: RemoteServer.maxPendingPerHost)
        }
        #expect(admit("10.0.0.50", entries) == .acceptEvicting(9))
        #expect(admit("10.0.0.6", entries) == .acceptEvicting(9))
        #expect(admit("10.0.0.1", entries) == .refuse)
        // Signed-in sessions don't count and are never chosen, wherever they are in the list.
        entries.shuffle()
        #expect(admit("10.0.0.50", entries) == .acceptEvicting(9))
        #expect(admit("10.0.0.50", entries.filter { $0.isAuthenticated }) == .accept)
        #expect(admit("10.0.0.50", entries.filter { $0.id != 24 }) == .accept)
    }

    /// Re-review L3 on real sockets (pool of 3 here): a signed-in session, then 3 silent ones; the next socket closes
    /// the oldest silent one, signs in and is served, and the first signed-in session still is.
    @Test func aNewSocketGetsInWhenThePoolIsFull() async throws {
        let server = RemoteServer(maxPending: 3, maxPendingPerHost: 5)
        var closed: [RemoteSessionID] = []
        server.onMessage = { [weak server] id, _ in
            server?.sessionAuthenticated(id)
            server?.send(.toast("echo"), to: id)
        }
        server.onSessionClosed = { closed.append($0) }
        server.start(httpPort: .any, socketPort: .any)
        defer { server.stop() }
        try await waitUntil { server.state == .running }
        let port = try #require(server.socketPort)

        let first = socket(port)
        #expect(await echoes(first))
        let silent = (0..<3).map { _ in socket(port) }
        try await Task.sleep(for: .milliseconds(300))
        #expect(closed.isEmpty)
        let newcomer = socket(port)
        #expect(await echoes(newcomer))
        #expect(closed == [2])
        #expect(await echoes(first))
        for task in silent + [first, newcomer] { task.cancel(with: .goingAway, reason: nil) }
    }

    @Test func originRules() {
        let own: Set<String> = ["mm", "mac-mini"]
        func allowed(_ origin: String?, host: String = "192.168.1.20:8766") -> Bool {
            var headers: [(name: String, value: String)] = [(name: "Host", value: host)]
            if let origin { headers.append((name: "origin", value: origin)) }
            return WebSocketOrigin.isAllowed(headers: headers, httpPort: 8765, ownNames: own)
        }
        #expect(allowed(nil))
        #expect(allowed("http://192.168.1.20:8765"))
        #expect(allowed("HTTP://192.168.1.20:8765"))
        #expect(allowed("http://mac-mini.local:8765", host: "mac-mini.local:8766"))
        #expect(allowed("http://[fe80::1]:8765", host: "[fe80::1]:8766"))
        #expect(!allowed("https://evil.example"))
        #expect(!allowed("null"))
        #expect(!allowed("http://192.168.1.20:8766"))
        #expect(!allowed("https://192.168.1.20:8765"))
        #expect(!allowed("http://192.168.1.21:8765"))
        // DNS rebinding: the attacker's name points at this Mac; Host and Origin agree, but it isn't a local name.
        #expect(!allowed("http://evil.example:8765", host: "evil.example:8766"))
        #expect(!allowed("http://999.1.1.1:8765", host: "999.1.1.1:8766"))
        // Re-review L4: the router's names for the Mac (dotless, .lan, .home.arpa) are allowed; Origin must still match.
        // Pre-release lows (d): only the Mac's own names.
        #expect(allowed("http://mm.home.arpa:8765", host: "mm.home.arpa:8766"))
        #expect(allowed("http://mm.lan:8765", host: "mm.lan:8766"))
        #expect(allowed("http://mm:8765", host: "mm:8766"))
        #expect(allowed("http://mac-mini.office.lan:8765", host: "MAC-MINI.office.lan:8766"))
        #expect(!allowed("http://other.lan:8765", host: "other.lan:8766"))
        #expect(!allowed("http://other.home.arpa:8765", host: "other.home.arpa:8766"))
        #expect(!allowed("http://other:8765", host: "other:8766"))
        #expect(!allowed("http://other.local:8765", host: "other.local:8766"))
        #expect(!allowed("http://lan:8765", host: "lan:8766"))
        #expect(!allowed("http://mm.lan:8765", host: "mm.home.arpa:8766"))
        #expect(!allowed("http://mm.lan:8766", host: "mm.lan:8766"))
        #expect(!allowed("https://mm.lan:8765", host: "mm.lan:8766"))
        #expect(!allowed("http://mm.lan.evil.example:8765", host: "mm.lan.evil.example:8766"))
        #expect(!allowed("http://mm.home.arpa.evil.example:8765", host: "mm.home.arpa.evil.example:8766"))
        #expect(!allowed("http://evil.example:8765", host: "evil.example:8766"))
        for name in ["mm", "mac-mini", "mm.lan", "mm.home.arpa", "mm.b.home.arpa", "mac-mini.local", "localhost",
                     "192.168.1.20", "[fe80::1]"] {
            #expect(WebSocketOrigin.isLocalName(name, ownNames: own), "\(name)")
        }
        for name in ["evil.example", "mm.lan.evil.example", "lan.example", ".lan", "-mm", "mm_x", "a..lan",
                     "x.home.arpa.", "home.arpa", ".home.arpa", "other.lan", "other.home.arpa", "a.mm.home.arpa",
                     "lan", "other", "other.local", ".local", "mm.home.arpa.evil.example", "mm.local.evil.example"] {
            #expect(!WebSocketOrigin.isLocalName(name, ownNames: own), "\(name)")
        }
        // Without names for the Mac, only addresses and localhost.
        #expect(!WebSocketOrigin.isLocalName("mm.lan", ownNames: []))
        #expect(!WebSocketOrigin.isLocalName("mac-mini.local", ownNames: []))
        #expect(WebSocketOrigin.isLocalName("192.168.1.20", ownNames: []))
        let twoOrigins: [(name: String, value: String)] = [
            (name: "Host", value: "192.168.1.20:8766"),
            (name: "Origin", value: "http://192.168.1.20:8765"), (name: "Origin", value: "https://evil.example"),
        ]
        #expect(!WebSocketOrigin.isAllowed(headers: twoOrigins, httpPort: 8765, ownNames: own))
        #expect(!WebSocketOrigin.isAllowed(headers: [(name: "Origin", value: "http://192.168.1.20:8765")], httpPort: 8765,
                                           ownNames: own))
    }

    /// Pre-release lows (d): the Mac's names are first labels, lowercased; addresses and localhost aren't names. The
    /// real names include this Mac's Bonjour name, so its `<name>.local` page keeps working.
    @Test func macHostNames() {
        #expect(MacHostNames.firstLabel("Mac-mini.lan") == ["mac-mini"])
        #expect(MacHostNames.firstLabel("MM") == ["mm"])
        #expect(MacHostNames.firstLabel("localhost").isEmpty)
        #expect(MacHostNames.firstLabel("192.168.1.20").isEmpty)
        #expect(MacHostNames.firstLabel("fe80::1").isEmpty)
        #expect(MacHostNames.firstLabel("").isEmpty)
        let names = MacHostNames.current()
        if let local = SCDynamicStoreCopyLocalHostName(nil) as String? {
            #expect(names.contains(local.lowercased()))
            #expect(WebSocketOrigin.isLocalName("\(local.lowercased()).local", ownNames: names))
            #expect(WebSocketOrigin.isLocalName("\(local.lowercased()).lan", ownNames: names))
            #expect(WebSocketOrigin.isLocalName("\(local.lowercased()).home.arpa", ownNames: names))
            #expect(!WebSocketOrigin.isLocalName("\(local.lowercased()).lan.evil.example", ownNames: names))
        }
        #expect(!WebSocketOrigin.isLocalName("not-this-mac-\(UUID().uuidString.prefix(8).lowercased()).lan", ownNames: names))
    }

    // MARK: Pre-release lows (b)

    /// IPv4 as is, IPv4-mapped IPv6 as IPv4, other IPv6 by its /64 (zones and brackets ignored).
    @Test func peerAddressKeys() {
        #expect(PeerAddress.key("192.168.1.7") == "192.168.1.7")
        #expect(PeerAddress.key("::ffff:192.168.1.7") == "192.168.1.7")
        let a = PeerAddress.key("2001:db8:1:2::1")
        #expect(a == "2001:db8:1:2::/64")
        for other in ["2001:db8:1:2:ffff:ffff:ffff:ffff", "[2001:db8:1:2:abcd::9]", "2001:DB8:1:2:0:0:0:5%en0"] {
            #expect(PeerAddress.key(other) == a, "\(other)")
        }
        #expect(PeerAddress.key("2001:db8:1:3::1") != a)
        #expect(PeerAddress.key("fe80::1%en0") == PeerAddress.key("fe80::2:3:4:5%en1"))
    }

    /// A full pool closes the oldest waiting socket of the address with the most waiting, not the oldest overall.
    @Test func aFullPoolEvictsFromTheBusiestAddress() {
        func entry(_ id: Int, _ host: String) -> PendingPool.Entry { .init(id: id, host: host, isAuthenticated: false) }
        // The phone's socket (id 1) is the oldest; B has the most.
        var entries = [entry(1, "phone"), entry(2, "A"), entry(3, "B"), entry(4, "B"), entry(5, "A"), entry(6, "B")]
        #expect(PendingPool.admit(host: "C", sessions: entries, maxPending: 6, maxPendingPerHost: 3) == .acceptEvicting(3))
        // Ties between A and B: the oldest of their sockets.
        entries.removeAll { $0.id == 6 }
        #expect(PendingPool.admit(host: "C", sessions: entries, maxPending: 5, maxPendingPerHost: 3) == .acceptEvicting(2))
        // An IPv6 host varying its low 64 bits is one address: its 4th waiting socket is refused.
        let v6 = ["2001:db8:5:6::1", "2001:db8:5:6::2", "2001:db8:5:6:aaaa::3"].enumerated()
            .map { entry(10 + $0.offset, PeerAddress.key($0.element)) }
        #expect(PendingPool.admit(host: PeerAddress.key("2001:db8:5:6:ffff::4"), sessions: v6, maxPending: 16,
                                  maxPendingPerHost: 3) == .refuse)
        #expect(PendingPool.admit(host: PeerAddress.key("2001:db8:5:7::4"), sessions: v6, maxPending: 16,
                                  maxPendingPerHost: 3) == .accept)
    }

    @Test func connectionRatePerAddress() {
        var rate = ConnectionRate(limit: 10)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        func allows(_ host: String, _ seconds: Double) -> Bool { rate.allows(host, now: start + seconds) }
        let first10 = (0..<10).map { allows("10.0.0.1", Double($0) * 0.01) }
        #expect(first10.allSatisfy { $0 })
        let eleventh = allows("10.0.0.1", 0.5)
        let otherAddress = allows("10.0.0.2", 0.5)
        let nextSecond = allows("10.0.0.1", 1.0)
        #expect(!eleventh && otherAddress && nextSecond)
        // One /64.
        var v6 = ConnectionRate(limit: 2)
        let results = ["2001:db8::1", "2001:db8::2:1", "2001:db8::ffff:1"].map { v6.allows(PeerAddress.key($0), now: start) }
        #expect(results == [true, true, false])
    }

    /// Six addresses each open a socket every 3 ms for 3 s (the pool full the whole time); a seventh opens one at
    /// 1.5 s and says hello 50 ms later: its socket is still there and signs in. With and without the rate limit
    /// (the pool's choice alone keeps it), and with the six as IPv6 hosts each varying its low 64 bits.
    @Test func sixFloodingAddressesDontKeepASeventhOut() {
        let v4 = (1...6).map { index in { (_: Int) in "10.0.0.\(index)" } }
        let v6 = (1...6).map { index in { (n: Int) in PeerAddress.key("2001:db8:\(index)::\(String(n % 65_536, radix: 16))") } }
        for (attackers, limit) in [(v4, RemoteServer.maxNewConnectionsPerSecond), (v4, Int.max), (v6, Int.max)] {
            var rate = ConnectionRate(limit: limit)
            var sessions: [PendingPool.Entry] = []
            var nextID = 1
            var phone: Int?
            var signedIn = false
            let start = Date(timeIntervalSinceReferenceDate: 0)
            func open(_ host: String, at ms: Int) -> Int? {
                guard rate.allows(host, now: start + Double(ms) / 1000) else { return nil }
                switch PendingPool.admit(host: host, sessions: sessions, maxPending: RemoteServer.maxPending,
                                         maxPendingPerHost: RemoteServer.maxPendingPerHost) {
                case .refuse: return nil
                case .acceptEvicting(let victim): sessions.removeAll { $0.id == victim }
                case .accept: break
                }
                defer { nextID += 1 }
                sessions.append(PendingPool.Entry(id: nextID, host: host, isAuthenticated: false))
                return nextID
            }
            for ms in stride(from: 0, through: 3000, by: 3) {
                for attacker in attackers { _ = open(attacker(ms), at: ms) }
                if ms == 1500 { phone = open("10.0.0.7", at: ms) }
                if ms == 1551, let phone, let index = sessions.firstIndex(where: { $0.id == phone }) {
                    sessions[index].isAuthenticated = true
                    signedIn = true
                }
                #expect(sessions.count(where: { !$0.isAuthenticated }) <= RemoteServer.maxPending)
            }
            #expect(phone != nil)
            #expect(signedIn)
            #expect(sessions.contains { $0.id == phone && $0.isAuthenticated })
        }
    }

    /// On real sockets: an address opening more than the limit's sockets in a second has the extra ones closed at
    /// once; a second later it connects again.
    @Test func tooManyNewSocketsFromOneAddressAreRefused() async throws {
        let server = RemoteServer(maxNewConnectionsPerSecond: 3)
        // Signed in, so the address's 3 pending slots don't refuse the 4th instead.
        server.onMessage = { [weak server] id, _ in
            server?.sessionAuthenticated(id)
            server?.send(.toast("echo"), to: id)
        }
        server.start(httpPort: .any, socketPort: .any)
        defer { server.stop() }
        try await waitUntil { server.state == .running }
        let port = try #require(server.socketPort)
        let first = (0..<3).map { _ in socket(port) }
        for task in first { #expect(await echoes(task)) }
        let extra = socket(port)
        #expect(await echoes(extra) == false)
        try await Task.sleep(for: .milliseconds(1100))
        let later = socket(port)
        #expect(await echoes(later))
        for task in first + [extra, later] { task.cancel(with: .goingAway, reason: nil) }
    }
}
