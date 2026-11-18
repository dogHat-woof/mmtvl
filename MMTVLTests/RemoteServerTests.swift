import Foundation
import Network
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
        func allowed(_ origin: String?, host: String = "192.168.1.20:8766") -> Bool {
            var headers: [(name: String, value: String)] = [(name: "Host", value: host)]
            if let origin { headers.append((name: "origin", value: origin)) }
            return WebSocketOrigin.isAllowed(headers: headers, httpPort: 8765)
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
        #expect(allowed("http://mm.home.arpa:8765", host: "mm.home.arpa:8766"))
        #expect(allowed("http://mm.lan:8765", host: "mm.lan:8766"))
        #expect(allowed("http://mm:8765", host: "mm:8766"))
        #expect(allowed("http://mac-mini.office.lan:8765", host: "MAC-MINI.office.lan:8766"))
        #expect(!allowed("http://mm.lan:8765", host: "mm.home.arpa:8766"))
        #expect(!allowed("http://mm.lan:8766", host: "mm.lan:8766"))
        #expect(!allowed("https://mm.lan:8765", host: "mm.lan:8766"))
        #expect(!allowed("http://mm.lan.evil.example:8765", host: "mm.lan.evil.example:8766"))
        #expect(!allowed("http://mm.home.arpa.evil.example:8765", host: "mm.home.arpa.evil.example:8766"))
        #expect(!allowed("http://evil.example:8765", host: "evil.example:8766"))
        for name in ["mm", "mac-mini", "mm.lan", "mm.home.arpa", "a.b.home.arpa"] {
            #expect(WebSocketOrigin.isLocalName(name), "\(name)")
        }
        for name in ["evil.example", "mm.lan.evil.example", "lan.example", ".lan", "-mm", "mm_x", "a..lan",
                     "x.home.arpa.", "home.arpa", ".home.arpa"] {
            #expect(!WebSocketOrigin.isLocalName(name), "\(name)")
        }
        let twoOrigins: [(name: String, value: String)] = [
            (name: "Host", value: "192.168.1.20:8766"),
            (name: "Origin", value: "http://192.168.1.20:8765"), (name: "Origin", value: "https://evil.example"),
        ]
        #expect(!WebSocketOrigin.isAllowed(headers: twoOrigins, httpPort: 8765))
        #expect(!WebSocketOrigin.isAllowed(headers: [(name: "Origin", value: "http://192.168.1.20:8765")], httpPort: 8765))
    }
}
