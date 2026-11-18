import Foundation
import Network
import os

/// M7c L30 (D39): a loopback HTTP relay between mpv and the IPTV CDN. ffmpeg opens an HLS stream's playlists and first
/// segments one after another, each on a new TLS connection (~0.2 s apiece). Through the relay it talks plain HTTP to
/// 127.0.0.1, the relay fetches upstream over URLSession's kept-alive connections, and as soon as a master playlist
/// arrives it fetches the media playlists and their start segments in parallel, so ffmpeg's requests find them ready.
///
/// Only URLs MMTVL registered are served (by an opaque token), on the loopback interface only. Only http(s) URLs are
/// registered, rewritten, fetched or redirected to, and a Mac or LAN host only on the stream's own host, or (pre-release
/// lows (c)) another LAN device's private address when the stream itself is on the LAN and (security lows L-1) the
/// chain that named it, redirects and playlists alike, never left the LAN (`RelayURLPolicy`). Never logs URLs or
/// tokens (hosts and statuses only). Main queue throughout.
final class HLSRelay {
    nonisolated struct Upstream: Sendable {
        var data: Data
        var contentType: String?
        var status: Int
        /// After redirects: relative URIs in a playlist resolve against it.
        var finalURL: URL
        /// Re-review L2: a redirect `RelayURLPolicy` refused ended this fetch (`status` is the 3xx).
        var refusedRedirect = false
        /// Security lows L-1: every URL this fetch went through (the URL, each redirect, `finalURL`) was a LAN host
        /// (`RelayURLPolicy.isLANHop`); the relay then folds in the chain before the URL (`fetch`), so a URI in this
        /// playlist may reach another LAN device only when this is true.
        var stayedOnLAN = true
    }

    /// GET `url`, a URL of the stream whose original URL is `stream` (redirects are judged against it).
    /// `lanOnlySoFar`: every URL from the stream to the one that named `url` was a LAN host (security lows L-1).
    typealias Fetch = @Sendable (_ url: URL, _ stream: URL, _ lanOnlySoFar: Bool) async throws -> Upstream

    static let shared = HLSRelay()

    /// Covers ffmpeg opening a master playlist twice and a prefetched media playlist; live playlists change every
    /// segment, so not longer.
    static let playlistLifetime: TimeInterval = 3
    static let segmentLifetime: TimeInterval = 60
    static let maxCachedBytes = 160 << 20
    static let tokenIdleLifetime: TimeInterval = 10 * 60
    static let maxTokensBeforePrune = 1000
    private static let requestTimeout: TimeInterval = 30

    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Relay")

    private(set) var port: UInt16?
    /// Pre-release lows (a): the relay was ready at least once since launch. Once it was, the player never loads a
    /// playlist stream straight from the provider (a relay that stopped fails the load instead).
    private(set) var hasRun = false

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var upstreamByToken: [String: URL] = [:]
    /// The original URL of the stream each token's URL belongs to (`RelayURLPolicy.allows`).
    private var streamByToken: [String: URL] = [:]
    private var tokenByUpstream: [URL: String] = [:]
    /// Security lows L-1: whether the chain that named each token's URL stayed on the LAN (false once any URL that
    /// led to it, the same URL reached another way included, wasn't a LAN host).
    private var lanChainByToken: [String: Bool] = [:]
    private var tokenLastUsed: [String: Date] = [:]
    /// Security lows L-1: keyed by the URL and whether its chain stayed on the LAN, since a fetch on a LAN-only chain
    /// may follow redirects (and give playlists) that one on a chain through a public host may not.
    private struct FetchKey: Hashable {
        var url: URL
        var lanOnlySoFar: Bool
    }
    private var cache: [FetchKey: (upstream: Upstream, storedAt: Date, isPlaylist: Bool)] = [:]
    private var cacheOrder: [FetchKey] = []
    private var cachedBytes = 0
    private var inFlight: [FetchKey: Task<Upstream?, Never>] = [:]
    /// Re-review L2: streams (original URLs) the relay refused a URI or a redirect for, and when; the player then
    /// skips its direct retry (`refusedSomething(forStreamOf:)`). Kept `tokenIdleLifetime`.
    private var refusedStreams: [URL: Date] = [:]
    private let fetchUpstream: Fetch
    private let now: () -> Date

    init(fetch: @escaping Fetch = HLSRelay.liveFetch, now: @escaping () -> Date = Date.init) {
        fetchUpstream = fetch
        self.now = now
    }

    // MARK: - Lifecycle

    /// Listens on 127.0.0.1, any free port. `port` is set once it's ready.
    func start() {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        do {
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                MainActor.assumeIsolated {
                    guard let self, let listener, listener === self.listener else { return }
                    self.listenerChanged(to: state)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated {
                    guard let self else {
                        connection.cancel()
                        return
                    }
                    self.accept(connection)
                }
            }
            listener.start(queue: .main)
        } catch {
            Self.logger.error("Relay could not start: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        port = nil
        for connection in connections.values { connection.cancel() }
        connections = [:]
    }

    private func listenerChanged(to state: NWListener.State) {
        switch state {
        case .ready:
            port = listener?.port?.rawValue
            hasRun = true
            Self.logger.notice("Relay on 127.0.0.1:\(self.port ?? 0)")
        case .failed(let error):
            Self.logger.error("Relay failed: \(error.localizedDescription, privacy: .public)")
            stop()
        default:
            break
        }
    }

    // MARK: - URLs

    /// The relay's address for `upstream` (a stream's own URL, unless it was already registered from a playlist), or
    /// nil while the relay isn't running or for a URL it doesn't relay (not http(s)); mpv then goes direct.
    func localURL(for upstream: URL) -> URL? {
        let token = tokenByUpstream[upstream]
        let stream = token.flatMap { streamByToken[$0] } ?? upstream
        let lanChain = token.flatMap { lanChainByToken[$0] } ?? true
        return localURL(for: upstream, stream: stream, lanOnlySoFar: lanChain)
    }

    /// nil when `RelayURLPolicy` refuses `upstream` for `stream` (`referrer`, `lanOnlySoFar`: the chain that named it).
    private func localURL(for upstream: URL, stream: URL, referrer: URL? = nil, lanOnlySoFar: Bool) -> URL? {
        guard let port,
              RelayURLPolicy.allows(upstream, stream: stream, referrer: referrer, lanOnlySoFar: lanOnlySoFar)
        else { return nil }
        return URL(string: "http://127.0.0.1:\(port)\(localPath(for: upstream, stream: stream, lanOnlySoFar: lanOnlySoFar))")
    }

    /// "/r/<token>/<the upstream's last path component>"; the name helps ffmpeg and logs, the token routes. A URL
    /// already registered keeps its token; its chain stays LAN-only only if this one is too (security lows L-1).
    private func localPath(for upstream: URL, stream: URL, lanOnlySoFar: Bool) -> String {
        let token: String
        if let existing = tokenByUpstream[upstream] {
            token = existing
        } else {
            token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            tokenByUpstream[upstream] = token
            upstreamByToken[token] = upstream
            streamByToken[token] = stream
            if upstreamByToken.count > Self.maxTokensBeforePrune { pruneTokens() }
        }
        lanChainByToken[token] = (lanChainByToken[token] ?? true) && lanOnlySoFar
        tokenLastUsed[token] = now()
        let name = upstream.lastPathComponent.filter { $0.isLetter || $0.isNumber || "._-".contains($0) }.prefix(64)
        return "/r/\(token)/\(name.isEmpty ? "x" : String(name))"
    }

    /// Re-review L2: the relay refused a URI or a redirect for the stream `upstream` belongs to (as `localURL` judges
    /// it) in the last `tokenIdleLifetime`, so mpv mustn't fetch the stream directly either.
    func refusedSomething(forStreamOf upstream: URL) -> Bool {
        let stream = tokenByUpstream[upstream].flatMap { streamByToken[$0] } ?? upstream
        guard let refusedAt = refusedStreams[stream] else { return false }
        return now().timeIntervalSince(refusedAt) < Self.tokenIdleLifetime
    }

    /// Tests: whether `upstream` has a token (was registered).
    func isRegistered(_ upstream: URL) -> Bool {
        tokenByUpstream[upstream] != nil
    }

    private func noteRefusal(stream: URL) {
        let date = now()
        refusedStreams[stream] = date
        if refusedStreams.count > Self.maxTokensBeforePrune {
            refusedStreams = refusedStreams.filter { date.timeIntervalSince($0.value) < Self.tokenIdleLifetime }
        }
    }

    private func pruneTokens() {
        let cutoff = now().addingTimeInterval(-Self.tokenIdleLifetime)
        for (token, used) in tokenLastUsed where used < cutoff {
            if let url = upstreamByToken.removeValue(forKey: token) { tokenByUpstream[url] = nil }
            streamByToken[token] = nil
            lanChainByToken[token] = nil
            tokenLastUsed[token] = nil
        }
    }

    // MARK: - Upstream

    /// M7c L31: fetches a stream's master playlist and what follows it ahead of mpv (a channel highlighted in the
    /// guide). `upstream` is the resolved CDN URL, the stream's own.
    func prefetch(_ upstream: URL) {
        Task { await fetch(upstream, stream: upstream) }
    }

    /// Cached (fresh), joined with a fetch already running, or fetched. A master prefetches its media playlists, and
    /// those (`startsStream`) the segment ffmpeg starts at; ffmpeg's own playlist refreshes prefetch nothing. `stream`
    /// is the original URL of the stream `url` belongs to; a URL `RelayURLPolicy` refuses is never fetched (nil).
    /// Security lows L-1: `lanOnlySoFar`, every URL from the stream to the one that named `url` was a LAN host; the
    /// result's `stayedOnLAN` also covers `url`, its redirects and its final URL.
    @discardableResult
    func fetch(_ url: URL, stream: URL, lanOnlySoFar: Bool = true, startsStream: Bool = false) async -> Upstream? {
        guard RelayURLPolicy.allows(url, stream: stream, lanOnlySoFar: lanOnlySoFar) else {
            Self.logger.notice("Refused to fetch from \(url.host() ?? "no host", privacy: .public)")
            noteRefusal(stream: stream)
            return nil
        }
        // Past a host that isn't on the LAN the chain is broken whatever came before, so both keys fetch alike.
        let key = FetchKey(url: url, lanOnlySoFar: lanOnlySoFar && RelayURLPolicy.isLANHop(url))
        if let entry = cache[key] {
            let lifetime = entry.isPlaylist ? Self.playlistLifetime : Self.segmentLifetime
            if now().timeIntervalSince(entry.storedAt) < lifetime { return entry.upstream }
        }
        if let task = inFlight[key] { return await task.value }
        let fetchUpstream = fetchUpstream
        let chain = key.lanOnlySoFar
        let task = Task { () -> Upstream? in
            guard var upstream = try? await fetchUpstream(url, stream, chain) else { return nil }
            upstream.stayedOnLAN = chain && upstream.stayedOnLAN && RelayURLPolicy.isLANHop(upstream.finalURL)
            return upstream
        }
        inFlight[key] = task
        let upstream = await task.value
        inFlight[key] = nil
        guard let upstream else {
            Self.logger.info("Fetching from \(url.host() ?? "?", privacy: .public) failed")
            return nil
        }
        if upstream.refusedRedirect { noteRefusal(stream: stream) }
        guard (200..<300).contains(upstream.status) else {
            Self.logger.info("\(url.host() ?? "?", privacy: .public) answered \(upstream.status)")
            return upstream
        }
        let isPlaylist = HLSPlaylist.isPlaylist(upstream.data, contentType: upstream.contentType)
        store(upstream, for: key, isPlaylist: isPlaylist)
        if isPlaylist { prefetchFollowing(upstream, stream: stream, startsStream: startsStream) }
        return upstream
    }

    /// Master → its media playlists, in parallel; a media playlist reached from a master → the segment ffmpeg
    /// starts at. Security lows L-1: each URI is judged with the playlist as its referrer and the playlist's chain.
    private func prefetchFollowing(_ playlist: Upstream, stream: URL, startsStream: Bool) {
        let text = String(decoding: playlist.data, as: UTF8.self)
        let chain = playlist.stayedOnLAN
        let allowed = { (url: URL) in
            guard RelayURLPolicy.allows(url, stream: stream, referrer: playlist.finalURL, lanOnlySoFar: chain) else {
                self.noteRefusal(stream: stream)
                return false
            }
            return self.inFlight[FetchKey(url: url, lanOnlySoFar: chain && RelayURLPolicy.isLANHop(url))] == nil
        }
        switch HLSPlaylist.kind(of: text) {
        case .master:
            for url in HLSPlaylist.mediaPlaylists(in: text, base: playlist.finalURL) where allowed(url) {
                Task { await fetch(url, stream: stream, lanOnlySoFar: chain, startsStream: true) }
            }
        case .media where startsStream:
            for url in HLSPlaylist.startSegments(in: text, base: playlist.finalURL) where allowed(url) {
                Task { await fetch(url, stream: stream, lanOnlySoFar: chain) }
            }
        case .media, .unknown:
            break
        }
    }

    private func store(_ upstream: Upstream, for url: FetchKey, isPlaylist: Bool) {
        if let old = cache[url] {
            cachedBytes -= old.upstream.data.count
            cacheOrder.removeAll { $0 == url }
        }
        cache[url] = (upstream, now(), isPlaylist)
        cacheOrder.append(url)
        cachedBytes += upstream.data.count
        let date = now()
        // Drop the expired, then the oldest while over the cap.
        cacheOrder.removeAll { key in
            guard let entry = cache[key] else { return true }
            let lifetime = entry.isPlaylist ? Self.playlistLifetime : Self.segmentLifetime
            guard date.timeIntervalSince(entry.storedAt) >= lifetime, key != url else { return false }
            cachedBytes -= entry.upstream.data.count
            cache[key] = nil
            return true
        }
        while cachedBytes > Self.maxCachedBytes, cacheOrder.count > 1 {
            let oldest = cacheOrder.removeFirst()
            if let entry = cache.removeValue(forKey: oldest) { cachedBytes -= entry.upstream.data.count }
        }
    }

    // MARK: - Requests

    private func accept(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .failed:
                    self?.connections[key]?.cancel()
                case .cancelled:
                    self?.connections[key] = nil
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
        read(on: connection, buffer: Data())
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.requestTimeout) { [weak connection] in
            connection?.cancel()
        }
    }

    private func read(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else {
                    connection.cancel()
                    return
                }
                var buffer = buffer
                if let data { buffer.append(data) }
                switch HTTPRequestHead.parse(buffer) {
                case .incomplete:
                    if error != nil || isComplete {
                        connection.cancel()
                    } else {
                        self.read(on: connection, buffer: buffer)
                    }
                case .tooLarge, .invalid:
                    self.send(HTTPResponse.error(400, "Bad Request"), on: connection)
                case .complete(let head):
                    self.handle(head, range: Self.rangeStart(in: buffer), on: connection)
                }
            }
        }
    }

    private func handle(_ head: HTTPRequestHead, range: Int?, on connection: NWConnection) {
        guard head.method == "GET" || head.method == "HEAD" else {
            send(HTTPResponse.error(405, "Method Not Allowed"), on: connection)
            return
        }
        let parts = head.path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "r", let upstreamURL = upstreamByToken[String(parts[1])] else {
            send(HTTPResponse.error(404, "Not Found"), on: connection)
            return
        }
        tokenLastUsed[String(parts[1])] = now()
        let stream = streamByToken[String(parts[1])] ?? upstreamURL
        let lanChain = lanChainByToken[String(parts[1])] ?? false
        let includeBody = head.method == "GET"
        Task {
            guard let upstream = await fetch(upstreamURL, stream: stream, lanOnlySoFar: lanChain) else {
                send(HTTPResponse.error(502, "Bad Gateway"), on: connection)
                return
            }
            guard (200..<300).contains(upstream.status) else {
                send(HTTPResponse.error(upstream.status, HTTPResponse.reason(for: upstream.status)), on: connection)
                return
            }
            if HLSPlaylist.isPlaylist(upstream.data, contentType: upstream.contentType) {
                // A URI the policy refuses is left out of the playlist; one the relay can't serve (stopped) goes direct.
                // Security lows L-1: judged with this playlist (its final URL) as the referrer, on its chain.
                let referrer = upstream.finalURL, chain = upstream.stayedOnLAN
                let text = HLSPlaylist.rewrite(String(decoding: upstream.data, as: UTF8.self), base: referrer) {
                    guard RelayURLPolicy.allows($0, stream: stream, referrer: referrer, lanOnlySoFar: chain) else {
                        self.noteRefusal(stream: stream)
                        return nil
                    }
                    let local = self.localURL(for: $0, stream: stream, referrer: referrer, lanOnlySoFar: chain)
                    return (local ?? $0).absoluteString
                }
                send(HTTPResponse.make(status: 200, reason: "OK", contentType: "application/vnd.apple.mpegurl",
                                       body: Data(text.utf8), includeBody: includeBody), on: connection)
                return
            }
            let body = upstream.data
            let contentType = upstream.contentType ?? "application/octet-stream"
            if let range, range > 0, range < body.count {
                let header = HTTPHeader(name: "Content-Range", value: "bytes \(range)-\(body.count - 1)/\(body.count)")
                send(HTTPResponse.make(status: 206, reason: "Partial Content", contentType: contentType, headers: [header],
                                       body: body.subdata(in: range..<body.count), includeBody: includeBody), on: connection)
            } else {
                send(HTTPResponse.make(status: 200, reason: "OK", contentType: contentType, body: body,
                                       includeBody: includeBody), on: connection)
            }
        }
    }

    private func send(_ response: Data, on connection: NWConnection) {
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// "Range: bytes=N-" → N (ffmpeg resumes a broken segment this way).
    nonisolated static func rangeStart(in request: Data) -> Int? {
        let head = String(decoding: request.prefix(HTTPRequestHead.maxSize), as: UTF8.self)
        guard let match = head.firstMatch(of: /(?i)\r\nrange:\s*bytes=(\d+)-/) else { return nil }
        return Int(match.1)
    }

    // MARK: - Live fetch

    /// URLSession keeps connections to the CDN alive between requests; non-2xx comes back as its status.
    static let liveFetch: Fetch = { url, stream, lanOnlySoFar in
        try await liveFetch(url, stream: stream, lanOnlySoFar: lanOnlySoFar, session: session)
    }

    /// `liveFetch` on `session` (tests give a stubbed one). A redirect is followed only to a URL `RelayURLPolicy`
    /// allows for `stream` from the URL that redirected, on the chain so far (`lanOnlySoFar`, security lows L-1); a
    /// refused one ends the fetch with the 3xx itself.
    nonisolated static func liveFetch(_ url: URL, stream: URL, lanOnlySoFar: Bool = true,
                                      session: URLSession) async throws -> Upstream {
        // URLSession also opens file: and other schemes; the relay only ever fetches http(s).
        guard RelayURLPolicy.isWebURL(url) else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let redirectGuard = RedirectGuard(stream: stream, lanOnlySoFar: lanOnlySoFar)
        let (data, response) = try await session.data(for: request, delegate: redirectGuard)
        let http = response as? HTTPURLResponse
        let finalURL = response.url ?? url
        return Upstream(data: data, contentType: http?.value(forHTTPHeaderField: "Content-Type"),
                        status: http?.statusCode ?? 200, finalURL: finalURL,
                        refusedRedirect: redirectGuard.refused,
                        stayedOnLAN: redirectGuard.stayedOnLAN && RelayURLPolicy.isLANHop(url)
                            && RelayURLPolicy.isLANHop(finalURL))
    }

    /// Security review item 5: a 3xx from an allowed CDN must not take the relay to the Mac or the LAN (or off
    /// http(s)). Security lows L-1: each hop is judged with the URL that redirected as its referrer, and once a hop
    /// wasn't a LAN host the rest of the chain reaches no other LAN device. One guard per fetch. Logs the refused
    /// target's host only.
    nonisolated final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
        private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Relay")
        private struct State {
            var refused = false
            var lanOnly: Bool
        }
        let stream: URL
        private let state: OSAllocatedUnfairLock<State>

        /// `lanOnlySoFar`: every URL from the stream to the one this fetch starts at was a LAN host.
        init(stream: URL, lanOnlySoFar: Bool = true) {
            self.stream = stream
            state = OSAllocatedUnfairLock(initialState: State(lanOnly: lanOnlySoFar))
        }

        /// Re-review L2: `follows` refused a redirect.
        var refused: Bool { state.withLock { $0.refused } }

        /// Security lows L-1: every referrer so far (and the chain before the fetch) was a LAN host.
        var stayedOnLAN: Bool { state.withLock { $0.lanOnly } }

        /// Whether the relay follows a redirect from `referrer` (the URL that answered with it; nil: the stream itself)
        /// to `target`. A referrer that isn't a LAN host ends LAN-to-LAN steps for the rest of this chain.
        func follows(_ target: URL?, from referrer: URL? = nil) -> Bool {
            let lanOnly = state.withLock { state in
                if let referrer, !RelayURLPolicy.isLANHop(referrer) { state.lanOnly = false }
                return state.lanOnly
            }
            guard let target,
                  RelayURLPolicy.allows(target, stream: stream, referrer: referrer, lanOnlySoFar: lanOnly)
            else {
                Self.logger.notice("Refused redirect to \(target?.host() ?? "no host", privacy: .public)")
                state.withLock { $0.refused = true }
                return false
            }
            return true
        }

        // The completion-handler form, like `HDHomeRunHTTP.RedirectBlocker`'s (the async one crashes Swift 6.4's SILGen).
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            // The URL that answered with this redirect; with neither known, no LAN-to-LAN step.
            let referrer = response.url ?? task.currentRequest?.url
            if referrer == nil { state.withLock { $0.lanOnly = false } }
            completionHandler(follows(request.url, from: referrer) ? request : nil)
        }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: configuration)
    }()
}
