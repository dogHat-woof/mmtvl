import AppKit
import Foundation
import Observation
import os

/// The user's Plex account (M7 D28, L14–L17): plex.tv/link sign-in, the chosen server and its Continue Watching.
/// Logs server names and URI hosts only; never tokens, PIN codes or full connection URIs.
@Observable
final class PlexAccount {
    enum Status: Equatable {
        case signedOut
        /// The link page shows a code.
        case linking
        /// Signed in, no server chosen: none on the account, or several to choose from.
        case noServer
        case connecting
        case connected
        case unreachable
        /// L17: macOS's Local Network permission blocks the server (unverified detection).
        case localNetworkDenied
        /// 401 from plex.tv or the server; tokens are kept until Sign Out.
        case signInAgain
    }

    private(set) var status: Status
    /// The plex.tv/link code while linking.
    private(set) var linkCode: String?
    /// The account's servers, owned first, then by name (after sign-in or a refresh without a chosen server).
    private(set) var servers: [PlexAPI.Resource] = []
    private(set) var serverName: String?
    private(set) var continueWatching: [ShelfCard] = []
    /// Status changed (Settings refreshes its rows, the shelf its cards).
    @ObservationIgnored var onChange: (() -> Void)?
    /// The running link flow / refresh; tests await them.
    @ObservationIgnored private(set) var linkTask: Task<Void, Never>?
    @ObservationIgnored private(set) var refreshTask: Task<Void, Never>?

    @ObservationIgnored private let network: PlexNetwork
    @ObservationIgnored private let configFile: JSONConfigFile<PlexConfig>
    @ObservationIgnored private let tokens: PlexTokenStore
    @ObservationIgnored private let client: PlexAPI.ClientInfo
    @ObservationIgnored private let sleep: (Duration) async -> Void
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var config: PlexConfig
    @ObservationIgnored private var userToken: String?
    @ObservationIgnored private var serverToken: String?
    @ObservationIgnored private var lastRefresh: Date?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var checkedUser = false
    @ObservationIgnored private var loggedFieldNames = false
    @ObservationIgnored private let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Plex")

    init(network: PlexNetwork, configFile: JSONConfigFile<PlexConfig>, tokens: PlexTokenStore,
         client: PlexAPI.ClientInfo? = nil, sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) },
         now: @escaping () -> Date = Date.init) {
        self.network = network
        self.configFile = configFile
        self.tokens = tokens
        self.sleep = sleep
        self.now = now
        var config = configFile.load()
        if config.clientIdentifier.isEmpty {
            config.clientIdentifier = UUID().uuidString
            do {
                try configFile.save(config)
            } catch {
                logger.error("Failed to save \(PlexConfig.fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        self.config = config
        self.client = client ?? Self.currentClient(identifier: config.clientIdentifier)
        userToken = tokens.userToken()
        serverToken = tokens.serverToken()
        serverName = config.serverName
        status = userToken == nil ? .signedOut : .connecting
    }

    /// The app's own `X-Plex-*` values.
    static func currentClient(identifier: String) -> PlexAPI.ClientInfo {
        PlexAPI.ClientInfo(
            identifier: identifier,
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            deviceName: Host.current().localizedName ?? "Mac",
            platformVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

    var isSignedIn: Bool { userToken != nil }

    /// For `ShelfImageLoader` (images are fetched with the server token in a header).
    var imageHeaders: [String: String] {
        serverToken.map { ["X-Plex-Token": $0] } ?? [:]
    }

    /// What Settings → Plex shows (L15).
    var statusLine: String {
        switch status {
        case .signedOut: "Not signed in"
        case .linking: "Waiting for the code…"
        case .noServer: servers.isEmpty ? "No Plex Media Server on this account" : "Choose a server"
        case .connecting: "Connecting…"
        case .connected: continueWatching.count == 1 ? "Connected · 1 item" : "Connected · \(continueWatching.count) items"
        case .unreachable: "Can't reach the server"
        case .localNetworkDenied: "Allow Local Network access, then try again"
        case .signInAgain: "Sign in again"
        }
    }

    // MARK: Link sign-in (L15)

    /// True exactly while Settings → Plex → Sign In shows: makes a code and polls plex.tv every second.
    func setLinking(_ active: Bool) {
        if active {
            guard linkTask == nil, !isSignedIn else { return }
            setStatus(.linking)
            linkTask = Task { [weak self] in await self?.runLink() }
        } else {
            linkTask?.cancel()
            linkTask = nil
            linkCode = nil
            if status == .linking { setStatus(.signedOut) }
        }
    }

    private enum PINCheck { case pending, gone, token(String) }

    private func runLink() async {
        newPIN: while !Task.isCancelled {
            guard let pin = await createPIN() else {
                await sleep(.seconds(5))
                continue
            }
            linkCode = pin.code
            onChange?()
            while !Task.isCancelled {
                await sleep(.seconds(1))
                guard !Task.isCancelled else { return }
                if let expiresAt = pin.expiresAt, expiresAt <= now() { continue newPIN }
                switch await checkPIN(pin.id) {
                case .pending: continue
                case .gone: continue newPIN
                case .token(let token):
                    await finishSignIn(token)
                    return
                }
            }
        }
    }

    private func createPIN() async -> PlexAPI.PIN? {
        do {
            let (data, code) = try await network.send(PlexAPI.createPINRequest(client))
            guard (200..<300).contains(code) else {
                logger.error("plex.tv refused a link code (HTTP \(code))")
                return nil
            }
            return try PlexAPI.decodePIN(data)
        } catch {
            logger.error("Can't get a link code: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func checkPIN(_ id: Int) async -> PINCheck {
        do {
            let (data, code) = try await network.send(PlexAPI.checkPINRequest(id: id, client))
            if code == 404 { return .gone }
            guard (200..<300).contains(code) else { return .pending }
            let pin = try PlexAPI.decodePIN(data)
            if let token = pin.authToken, !token.isEmpty { return .token(token) }
            if let expiresAt = pin.expiresAt, expiresAt <= now() { return .gone }
            return .pending
        } catch {
            return .pending
        }
    }

    private func finishSignIn(_ token: String) async {
        logger.info("Signed in to Plex")
        userToken = token
        tokens.setUserToken(token)
        linkCode = nil
        checkedUser = true
        setStatus(.connecting)
        await loadServers()
    }

    // MARK: Servers (L15, L16)

    private func loadServers() async {
        guard let userToken else { return }
        do {
            let (data, code) = try await network.send(PlexAPI.resourcesRequest(token: userToken, client))
            if code == 401 {
                setStatus(.signInAgain)
                return
            }
            guard (200..<300).contains(code) else {
                logger.error("plex.tv resources failed (HTTP \(code))")
                setStatus(.unreachable)
                return
            }
            servers = try PlexAPI.decodeResources(data)
                .filter(\.isServer)
                .sorted { ($0.owned == true ? 0 : 1, $0.name.lowercased()) < ($1.owned == true ? 0 : 1, $1.name.lowercased()) }
        } catch {
            logger.error("Can't list Plex servers: \(error.localizedDescription, privacy: .public)")
            setStatus(.unreachable)
            return
        }
        if servers.count == 1 {
            await chooseServer(id: servers[0].clientIdentifier)
        } else {
            setStatus(.noServer)
        }
    }

    func chooseServer(id: String) async {
        guard let server = servers.first(where: { $0.clientIdentifier == id }) else { return }
        logger.info("Chose Plex server \(server.name, privacy: .public)")
        serverToken = server.accessToken
        tokens.setServerToken(server.accessToken)
        let usable = server.connections.filter { $0.protocol == "https" && !$0.relay }
        config.serverID = server.clientIdentifier
        config.serverName = server.name
        config.connections = (usable.filter(\.local) + usable.filter { !$0.local }).map(\.uri)
        config.lastConnection = nil
        saveConfig()
        serverName = server.name
        continueWatching = []
        lastRefresh = nil
        setStatus(.connecting)
        guard let url = await connect() else { return }
        await loadContinueWatching(server: url)
    }

    /// L16: `lastConnection` first, then the rest in order; the first whose identity matches wins.
    private func connect() async -> URL? {
        var candidates: [String] = []
        for uri in [config.lastConnection].compactMap({ $0 }) + config.connections where !candidates.contains(uri) {
            candidates.append(uri)
        }
        var localNetworkDenied = false
        for uri in candidates {
            guard let url = URL(string: uri) else { continue }
            do {
                let (data, code) = try await network.send(PlexAPI.identityRequest(connection: url))
                guard (200..<300).contains(code), (try? PlexAPI.decodeIdentity(data)) == config.serverID else { continue }
                if config.lastConnection != uri {
                    config.lastConnection = uri
                    saveConfig()
                }
                logger.info("Connected to Plex server at \(url.host() ?? "?", privacy: .public)")
                setStatus(.connected)
                return url
            } catch {
                if Self.isLocalNetworkDenied(error) { localNetworkDenied = true }
                logger.info("No answer from \(url.host() ?? "?", privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        setStatus(localNetworkDenied ? .localNetworkDenied : .unreachable)
        return nil
    }

    /// L17, unverified: macOS refusing a LAN connection shows up as EPERM or "No route to host" under the URLError.
    nonisolated static func isLocalNetworkDenied(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        while let error = current {
            if error.domain == NSPOSIXErrorDomain && (error.code == Int(EPERM) || error.code == Int(EHOSTUNREACH)) {
                return true
            }
            current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    // MARK: Continue Watching (L14)

    /// L14: reloads Continue Watching when older than `maxAge` (connecting first if needed). A failure keeps the old cards.
    func refreshIfStale(maxAge: Duration) async {
        guard isSignedIn, !isRefreshing, status != .signInAgain, status != .linking else { return }
        if let lastRefresh, status == .connected,
           now().timeIntervalSince(lastRefresh) < Double(maxAge.components.seconds) {
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        if !checkedUser {
            checkedUser = true
            if await userTokenRejected() {
                setStatus(.signInAgain)
                return
            }
        }
        guard config.serverID != nil else {
            await loadServers()
            return
        }
        if status != .connected { setStatus(.connecting) }
        guard let url = await connect() else { return }
        await loadContinueWatching(server: url)
    }

    /// Only a 401 counts; other failures aren't proof the token is bad.
    private func userTokenRejected() async -> Bool {
        guard let userToken else { return true }
        let response = try? await network.send(PlexAPI.userRequest(token: userToken, client))
        return response?.1 == 401
    }

    private func loadContinueWatching(server: URL) async {
        guard let token = serverToken ?? userToken else { return }
        do {
            var (data, code) = try await network.send(PlexAPI.continueWatchingRequest(server: server, token: token, client, flat: false))
            if code == 404 {
                (data, code) = try await network.send(PlexAPI.continueWatchingRequest(server: server, token: token, client, flat: true))
            }
            if code == 401 {
                setStatus(.signInAgain)
                return
            }
            guard (200..<300).contains(code) else {
                logger.error("Continue Watching failed (HTTP \(code))")
                return
            }
            logFieldNamesOnce(data)
            let items = try PlexAPI.decodeContinueWatching(data)
            continueWatching = items.enumerated().map { index, item in card(item, index: index, server: server) }
            lastRefresh = now()
            onChange?()
        } catch {
            logger.error("Can't load Continue Watching: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The action names a placeholder tile; `TopShelfModel` rewrites it to the Plex tile's id.
    private func card(_ item: PlexAPI.Metadata, index: Int, server: URL) -> ShelfCard {
        let card = PlexAPI.card(item)
        let image: ShelfCard.Image = card.imagePath.map { path in
            .remote(PlexAPI.imageURL(server: server, path: path, width: PlexAPI.imageSize.width,
                                     height: PlexAPI.imageSize.height), headers: imageHeaders)
        } ?? .channelLogo(nil)
        return ShelfCard(id: "plex.\(item.ratingKey ?? "\(index)")", title: card.title, subtitle: card.subtitle,
                         image: image, progress: card.progress, action: .openTile(id: "plex"))
    }

    /// Step 11: the real Metadata field names, once, at debug level (names only, never values).
    private func logFieldNamesOnce(_ data: Data) {
        guard !loggedFieldNames,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let container = root["MediaContainer"] as? [String: Any]
        else { return }
        let hubs = container["Hub"] as? [[String: Any]]
        let items = (hubs?.first { $0["hubIdentifier"] as? String == "home.continue" } ?? hubs?.first)?["Metadata"]
            ?? container["Metadata"]
        guard let first = (items as? [[String: Any]])?.first else { return }
        loggedFieldNames = true
        logger.debug("Continue Watching item fields: \(first.keys.sorted().joined(separator: ", "), privacy: .public)")
    }

    // MARK: Sign out

    /// Removes both tokens and resets `plex.json` except `clientIdentifier`.
    func signOut() {
        linkTask?.cancel()
        linkTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        tokens.setUserToken(nil)
        tokens.setServerToken(nil)
        userToken = nil
        serverToken = nil
        config = PlexConfig(clientIdentifier: config.clientIdentifier)
        saveConfig()
        servers = []
        serverName = nil
        linkCode = nil
        continueWatching = []
        lastRefresh = nil
        checkedUser = false
        logger.info("Signed out of Plex")
        setStatus(.signedOut)
    }

    /// Fire and forget (Settings, the shelf).
    func startRefresh(maxAge: Duration) {
        refreshTask = Task { [weak self] in await self?.refreshIfStale(maxAge: maxAge) }
    }

    private func setStatus(_ new: Status) {
        status = new
        onChange?()
    }

    private func saveConfig() {
        do {
            try configFile.save(config)
        } catch {
            logger.error("Failed to save \(PlexConfig.fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
