import Foundation
import Testing
@testable import MMTVL

/// A fake plex.tv + Plex Media Server, answering by method and path. Records every request.
nonisolated final class FakePlexServer: @unchecked Sendable {
    /// `call` is 1 for the first request to that key, 2 for the next…
    typealias Handler = @Sendable (_ call: Int) throws -> (Data, Int)
    private let lock = NSLock()
    private var handlers: [String: Handler] = [:]
    private var log: [URLRequest] = []

    /// key: "GET plex.tv/api/v2/pins/7" (host + path, no query).
    func on(_ key: String, _ handler: @escaping Handler) { lock.withLock { handlers[key] = handler } }
    func on(_ key: String, status: Int = 200, json: String) { on(key) { _ in (Data(json.utf8), status) } }

    var requests: [URLRequest] { lock.withLock { log } }
    func count(_ key: String) -> Int { requests.filter { Self.key($0) == key }.count }

    static func key(_ request: URLRequest) -> String {
        let url = request.url!
        return "\(request.httpMethod ?? "GET") \(url.host() ?? "")\(url.path())"
    }

    var network: PlexNetwork {
        PlexNetwork { [self] request in
            let (handler, call) = lock.withLock { () -> (Handler?, Int) in
                log.append(request)
                let key = Self.key(request)
                return (handlers[key], log.filter { Self.key($0) == key }.count)
            }
            guard let handler else { return (Data("{}".utf8), 404) }
            return try handler(call)
        }
    }
}

struct PlexAccountTests {
    static let client = PlexAPI.ClientInfo(identifier: "client-uuid", version: "1.0", deviceName: "Mac", platformVersion: "26")
    nonisolated static let now = Date(timeIntervalSince1970: 1_791_200_000)
    static let localURI = "https://192-168-1-20.abc.plex.direct:32400"
    static let remoteURI = "https://1-2-3-4.abc.plex.direct:443"

    struct Setup {
        let account: PlexAccount
        let server: FakePlexServer
        let tokens: PlexTokenStore
        let configFile: JSONConfigFile<PlexConfig>
        let directory: URL
        func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    }

    private func makeSetup(tokens: PlexTokenStore = .inMemory(), config: PlexConfig? = nil,
                           server: FakePlexServer = FakePlexServer()) throws -> Setup {
        let directory = FileManager.default.temporaryDirectory.appending(path: "PlexAccountTests-\(UUID().uuidString)")
        let configFile = JSONConfigFile(url: directory.appending(path: PlexConfig.fileName), defaultValue: PlexConfig())
        if let config { try configFile.save(config) }
        let account = PlexAccount(network: server.network, configFile: configFile, tokens: tokens, client: Self.client,
                                  sleep: { _ in await Task.yield() }, now: { Self.now })
        return Setup(account: account, server: server, tokens: tokens, configFile: configFile, directory: directory)
    }

    nonisolated static func pin(id: Int, code: String, token: String? = nil, expiresIn: TimeInterval = 900) -> String {
        let expires = ISO8601DateFormatter().string(from: now + expiresIn)
        let tokenJSON = token.map { "\"\($0)\"" } ?? "null"
        return #"{"id":\#(id),"code":"\#(code)","expiresAt":"\#(expires)","authToken":\#(tokenJSON)}"#
    }

    static func resource(_ id: String, name: String, owned: Bool, token: String = "server-token") -> String {
        """
        {"name":"\(name)","provides":"server","clientIdentifier":"\(id)","accessToken":"\(token)","owned":\(owned),
         "connections":[
           {"protocol":"http","uri":"http://192.168.1.20:32400","local":true,"relay":false},
           {"protocol":"https","uri":"\(remoteURI)","local":false,"relay":false},
           {"protocol":"https","uri":"https://relay.plex.direct:8443","local":false,"relay":true},
           {"protocol":"https","uri":"\(localURI)","local":true,"relay":false}
         ]}
        """
    }

    static let identity = #"{"MediaContainer":{"machineIdentifier":"srv1"}}"#
    static let continueWatching = """
    {"MediaContainer":{"Hub":[{"hubIdentifier":"home.continue","Metadata":[
      {"ratingKey":"501","type":"episode","title":"The One","grandparentTitle":"Friends","parentIndex":2,"index":7,
       "grandparentArt":"/g/art","viewOffset":600,"duration":1500},
      {"ratingKey":"601","type":"movie","title":"Heat","year":1995}
    ]}]}}
    """

    /// One owned server whose local https connection answers.
    private func serveOneServer(_ server: FakePlexServer) {
        server.on("GET plex.tv/api/v2/resources", json: "[\(Self.resource("srv1", name: "Living Room", owned: true))]")
        server.on("GET 192-168-1-20.abc.plex.direct/identity", json: Self.identity)
        server.on("GET 192-168-1-20.abc.plex.direct/hubs/continueWatching", json: Self.continueWatching)
        server.on("GET plex.tv/api/v2/user", json: "{}")
    }

    // MARK: Link flow

    @Test func linkingPollsUntilTheCodeIsUsedThenChoosesTheOnlyServer() async throws {
        let server = FakePlexServer()
        server.on("POST plex.tv/api/v2/pins", json: Self.pin(id: 7, code: "AB12"))
        server.on("GET plex.tv/api/v2/pins/7") { call in
            (Data((call < 3 ? Self.pin(id: 7, code: "AB12") : Self.pin(id: 7, code: "AB12", token: "user-token")).utf8), 200)
        }
        serveOneServer(server)
        let setup = try makeSetup(server: server)
        defer { setup.cleanUp() }
        let account = setup.account
        #expect(account.status == .signedOut)

        account.setLinking(true)
        #expect(account.status == .linking)
        await account.linkTask?.value
        #expect(server.count("GET plex.tv/api/v2/pins/7") == 3)
        #expect(setup.tokens.userToken() == "user-token")
        #expect(setup.tokens.serverToken() == "server-token")
        #expect(account.isSignedIn)
        #expect(account.linkCode == nil)
        #expect(account.status == .connected)
        #expect(account.serverName == "Living Room")
        #expect(account.continueWatching.map(\.id) == ["plex.501", "plex.601"])
        #expect(account.statusLine == "Connected · 2 items")
        // The PIN requests carry our client id and no token.
        let pinRequest = try #require(server.requests.first)
        #expect(pinRequest.value(forHTTPHeaderField: "X-Plex-Client-Identifier") == "client-uuid")
        #expect(pinRequest.value(forHTTPHeaderField: "X-Plex-Token") == nil)
    }

    @Test func aGonePINMakesANewOne() async throws {
        let server = FakePlexServer()
        server.on("POST plex.tv/api/v2/pins") { call in
            (Data(Self.pin(id: call, code: "C\(call)").utf8), 201)
        }
        server.on("GET plex.tv/api/v2/pins/1", status: 404, json: "{}")
        server.on("GET plex.tv/api/v2/pins/2", json: Self.pin(id: 2, code: "C2", token: "user-token"))
        serveOneServer(server)
        let setup = try makeSetup(server: server)
        defer { setup.cleanUp() }
        setup.account.setLinking(true)
        await setup.account.linkTask?.value
        #expect(server.count("POST plex.tv/api/v2/pins") == 2)
        #expect(setup.tokens.userToken() == "user-token")
    }

    @Test func anExpiredPINMakesANewOne() async throws {
        let server = FakePlexServer()
        server.on("POST plex.tv/api/v2/pins") { call in
            let pin = call == 1 ? Self.pin(id: 1, code: "OLD", expiresIn: -1) : Self.pin(id: 2, code: "NEW", token: "t")
            return (Data(pin.utf8), 201)
        }
        server.on("GET plex.tv/api/v2/pins/2", json: Self.pin(id: 2, code: "NEW", token: "t"))
        serveOneServer(server)
        let setup = try makeSetup(server: server)
        defer { setup.cleanUp() }
        setup.account.setLinking(true)
        await setup.account.linkTask?.value
        #expect(server.count("POST plex.tv/api/v2/pins") == 2)
        #expect(server.count("GET plex.tv/api/v2/pins/1") == 0)
    }

    @Test func stoppingLinkingCancelsThePolling() async throws {
        let server = FakePlexServer()
        server.on("POST plex.tv/api/v2/pins", json: Self.pin(id: 7, code: "AB12"))
        server.on("GET plex.tv/api/v2/pins/7", json: Self.pin(id: 7, code: "AB12"))
        let setup = try makeSetup(server: server)
        defer { setup.cleanUp() }
        let account = setup.account
        account.setLinking(true)
        for _ in 0..<50 where account.linkCode == nil { await Task.yield() }
        #expect(account.linkCode == "AB12")
        let task = account.linkTask
        account.setLinking(false)
        await task?.value
        let polls = server.count("GET plex.tv/api/v2/pins/7")
        for _ in 0..<20 { await Task.yield() }
        #expect(server.count("GET plex.tv/api/v2/pins/7") == polls)
        #expect(account.status == .signedOut)
        #expect(account.linkCode == nil)
        #expect(setup.tokens.userToken() == nil)
    }

    // MARK: Servers and connections

    @Test func severalServersAreListedOwnedFirst() async throws {
        let server = FakePlexServer()
        server.on("POST plex.tv/api/v2/pins", json: Self.pin(id: 7, code: "AB12", token: "user-token"))
        server.on("GET plex.tv/api/v2/pins/7", json: Self.pin(id: 7, code: "AB12", token: "user-token"))
        server.on("GET plex.tv/api/v2/resources", json: """
        [\(Self.resource("srv3", name: "Zed", owned: false)), \(Self.resource("srv2", name: "basement", owned: true)),
         {"name":"iPhone","provides":"client,player","clientIdentifier":"phone"},
         \(Self.resource("srv1", name: "Attic", owned: true))]
        """)
        let setup = try makeSetup(server: server)
        defer { setup.cleanUp() }
        setup.account.setLinking(true)
        await setup.account.linkTask?.value
        #expect(setup.account.servers.map(\.name) == ["Attic", "basement", "Zed"])
        #expect(setup.account.status == .noServer)
        #expect(setup.account.statusLine == "Choose a server")
        #expect(setup.account.serverName == nil)
    }

    @Test func connectionsTryLocalHTTPSFirstAndSkipHTTPAndRelay() async throws {
        let server = FakePlexServer()
        serveOneServer(server)
        // The local connection doesn't answer; the remote one does.
        server.on("GET 192-168-1-20.abc.plex.direct/identity") { _ in throw URLError(.cannotConnectToHost) }
        server.on("GET 1-2-3-4.abc.plex.direct/identity", json: Self.identity)
        server.on("GET 1-2-3-4.abc.plex.direct/hubs/continueWatching", json: Self.continueWatching)
        let setup = try makeSetup(tokens: .inMemory(user: "user-token"), server: server)
        defer { setup.cleanUp() }
        await setup.account.refreshIfStale(maxAge: .seconds(120))
        #expect(setup.account.status == .connected)
        let identityHosts = server.requests.filter { $0.url?.path() == "/identity" }.compactMap { $0.url?.host() }
        #expect(identityHosts == ["192-168-1-20.abc.plex.direct", "1-2-3-4.abc.plex.direct"])
        let config = setup.configFile.load()
        #expect(config.connections == [Self.localURI, Self.remoteURI])
        #expect(config.lastConnection == Self.remoteURI)

        // Next time, the last connection goes first.
        let again = PlexAccount(network: server.network, configFile: setup.configFile, tokens: setup.tokens,
                                client: Self.client, sleep: { _ in }, now: { Self.now })
        let before = server.requests.count
        await again.refreshIfStale(maxAge: .seconds(120))
        let firstIdentity = server.requests[before...].first { $0.url?.path() == "/identity" }
        #expect(firstIdentity?.url?.host() == "1-2-3-4.abc.plex.direct")
    }

    @Test func noAnsweringConnectionIsUnreachable() async throws {
        let server = FakePlexServer()
        serveOneServer(server)
        server.on("GET 192-168-1-20.abc.plex.direct/identity") { _ in throw URLError(.timedOut) }
        let setup = try makeSetup(tokens: .inMemory(user: "user-token"), server: server)
        defer { setup.cleanUp() }
        await setup.account.refreshIfStale(maxAge: .seconds(120))
        #expect(setup.account.status == .unreachable)
        #expect(setup.account.statusLine == "Can't reach the server")
    }

    @Test func localNetworkDenialIsRecognized() {
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(EHOSTUNREACH))
        let urlError = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost,
                               userInfo: [NSUnderlyingErrorKey: posix])
        #expect(PlexAccount.isLocalNetworkDenied(urlError))
        #expect(!PlexAccount.isLocalNetworkDenied(URLError(.timedOut)))
    }

    @Test func continueWatchingFallsBackToTheFlatForm() async throws {
        let server = FakePlexServer()
        serveOneServer(server)
        server.on("GET 192-168-1-20.abc.plex.direct/hubs/continueWatching", status: 404, json: "{}")
        server.on("GET 192-168-1-20.abc.plex.direct/hubs/continueWatching/items",
                  json: #"{"MediaContainer":{"Metadata":[{"ratingKey":"9","type":"movie","title":"Up","thumb":"/t"}]}}"#)
        let setup = try makeSetup(tokens: .inMemory(user: "user-token"), server: server)
        defer { setup.cleanUp() }
        await setup.account.refreshIfStale(maxAge: .seconds(120))
        let card = try #require(setup.account.continueWatching.first)
        #expect(card.id == "plex.9")
        #expect(card.action == .openTile(id: "plex"))
        guard case .remote(let url, let headers) = card.image else {
            Issue.record("No remote image")
            return
        }
        #expect(url.host() == "192-168-1-20.abc.plex.direct")
        #expect(!url.absoluteString.contains("server-token"))
        #expect(headers == ["X-Plex-Token": "server-token"])
    }

    @Test func refreshOnlyWhenStale() async throws {
        let server = FakePlexServer()
        serveOneServer(server)
        let setup = try makeSetup(tokens: .inMemory(user: "user-token"), server: server)
        defer { setup.cleanUp() }
        await setup.account.refreshIfStale(maxAge: .seconds(120))
        await setup.account.refreshIfStale(maxAge: .seconds(120))
        #expect(server.count("GET 192-168-1-20.abc.plex.direct/hubs/continueWatching") == 1)
    }

    // MARK: 401 and sign out

    @Test func a401FromTheServerAsksToSignInAgain() async throws {
        let server = FakePlexServer()
        serveOneServer(server)
        server.on("GET 192-168-1-20.abc.plex.direct/hubs/continueWatching", status: 401, json: "{}")
        let setup = try makeSetup(tokens: .inMemory(user: "user-token"), server: server)
        defer { setup.cleanUp() }
        await setup.account.refreshIfStale(maxAge: .seconds(120))
        #expect(setup.account.status == .signInAgain)
        #expect(setup.account.statusLine == "Sign in again")
        #expect(setup.tokens.userToken() == "user-token")
    }

    @Test func a401FromPlexTVAsksToSignInAgain() async throws {
        let server = FakePlexServer()
        serveOneServer(server)
        server.on("GET plex.tv/api/v2/user", status: 401, json: "{}")
        let setup = try makeSetup(tokens: .inMemory(user: "user-token"), server: server)
        defer { setup.cleanUp() }
        await setup.account.refreshIfStale(maxAge: .seconds(120))
        #expect(setup.account.status == .signInAgain)
    }

    @Test func signOutClearsTokensAndKeepsTheClientIdentifier() async throws {
        let server = FakePlexServer()
        serveOneServer(server)
        let setup = try makeSetup(tokens: .inMemory(user: "user-token"), server: server)
        defer { setup.cleanUp() }
        await setup.account.refreshIfStale(maxAge: .seconds(120))
        let clientID = setup.configFile.load().clientIdentifier
        #expect(!clientID.isEmpty)
        #expect(setup.configFile.load().serverID == "srv1")

        setup.account.signOut()
        #expect(setup.tokens.userToken() == nil)
        #expect(setup.tokens.serverToken() == nil)
        #expect(setup.configFile.load() == PlexConfig(clientIdentifier: clientID))
        #expect(setup.account.status == .signedOut)
        #expect(setup.account.continueWatching.isEmpty)
        #expect(setup.account.serverName == nil)
    }

    @Test func theClientIdentifierIsMadeOnce() throws {
        let setup = try makeSetup()
        defer { setup.cleanUp() }
        let first = setup.configFile.load().clientIdentifier
        #expect(UUID(uuidString: first) != nil)
        _ = PlexAccount(network: setup.server.network, configFile: setup.configFile, tokens: setup.tokens)
        #expect(setup.configFile.load().clientIdentifier == first)
    }
}
