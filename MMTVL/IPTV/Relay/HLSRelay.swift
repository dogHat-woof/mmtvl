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
/// lows (c)) another LAN device's private address when the stream itself is on the LAN (`RelayURLPolicy`). Never logs
/// URLs or tokens (hosts and statuses only). Main queue throughout.
final class HLSRelay {
    nonisolated struct Upstream: Sendable {
        var data: Data
        var contentType: String?
        var status: Int
        /// After redirects: relative URIs in a playlist resolve against it.
        var finalURL: URL
        /// Re-review L2: a redirect `RelayURLPolicy` refused ended this fetch (`status` is the 3xx).
        var refusedRedirect = false
    }

    /// GET `url`, a URL of the stream whose original URL is `stream` (redirects are judged against it).
    typealias Fetch = @Sendable (_ url: URL, _ stream: URL) async throws -> Upstream

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
    private var tokenLastUsed: [String: Date] = [:]
    private var cache: [URL: (upstream: Upstream, storedAt: Date, isPlaylist: Bool)] = [:]
    private var cacheOrder: [URL] = []
    private var cachedBytes = 0
    private var inFlight: [URL: Task<Upstream?, Never>] = [:]
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
        let stream = tokenByUpstream[upstream].flatMap { streamByToken[$0] } ?? upstream
        return localURL(for: upstream, stream: stream)
    }

    /// nil when `RelayURLPolicy` refuses `upstream` for `stream`.
    private func localURL(for upstream: URL, stream: URL) -> URL? {
        guard let port, RelayURLPolicy.allows(upstream, stream: stream) else { return nil }
        return URL(string: "http://127.0.0.1:\(port)\(localPath(for: upstream, stream: stream))")
    }

    /// "/r/<token>/<the upstream's last path component>"; the name helps ffmpeg and logs, the token routes.
    private func localPath(for upstream: URL, stream: URL) -> String {
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
    @discardableResult
    func fetch(_ url: URL, stream: URL, startsStream: Bool = false) async -> Upstream? {
        guard RelayURLPolicy.allows(url, stream: stream) else {
            Self.logger.notice("Refused to fetch from \(url.host() ?? "no host", privacy: .public)")
            noteRefusal(stream: stream)
            return nil
        }
        if let entry = cache[url] {
            let lifetime = entry.isPlaylist ? Self.playlistLifetime : Self.segmentLifetime
            if now().timeIntervalSince(entry.storedAt) < lifetime { return entry.upstream }
        }
        if let task = inFlight[url] { return await task.value }
        let fetchUpstream = fetchUpstream
        let task = Task { try? await fetchUpstream(url, stream) }
        inFlight[url] = task
        let upstream = await task.value
        inFlight[url] = nil
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
        store(upstream, for: url, isPlaylist: isPlaylist)
        if isPlaylist { prefetchFollowing(upstream, stream: stream, startsStream: startsStream) }
        return upstream
    }

    /// Master → its media playlists, in parallel; a media playlist reached from a master → the segment ffmpeg
    /// starts at.
    private func prefetchFollowing(_ playlist: Upstream, stream: URL, startsStream: Bool) {
        let text = String(decoding: playlist.data, as: UTF8.self)
        let allowed = { (url: URL) in
            guard RelayURLPolicy.allows(url, stream: stream) else {
                self.noteRefusal(stream: stream)
                return false
            }
            return self.inFlight[url] == nil
        }
        switch HLSPlaylist.kind(of: text) {
        case .master:
            for url in HLSPlaylist.mediaPlaylists(in: text, base: playlist.finalURL) where allowed(url) {
                Task { await fetch(url, stream: stream, startsStream: true) }
            }
        case .media where startsStream:
            for url in HLSPlaylist.startSegments(in: text, base: playlist.finalURL) where allowed(url) {
                Task { await fetch(url, stream: stream) }
            }
        case .media, .unknown:
            break
        }
    }

    private func store(_ upstream: Upstream, for url: URL, isPlaylist: Bool) {
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
        let includeBody = head.method == "GET"
        Task {
            guard let upstream = await fetch(upstreamURL, stream: stream) else {
                send(HTTPResponse.error(502, "Bad Gateway"), on: connection)
                return
            }
            guard (200..<300).contains(upstream.status) else {
                send(HTTPResponse.error(upstream.status, HTTPResponse.reason(for: upstream.status)), on: connection)
                return
            }
            if HLSPlaylist.isPlaylist(upstream.data, contentType: upstream.contentType) {
                // A URI the policy refuses is left out of the playlist; one the relay can't serve (stopped) goes direct.
                let text = HLSPlaylist.rewrite(String(decoding: upstream.data, as: UTF8.self), base: upstream.finalURL) {
                    guard RelayURLPolicy.allows($0, stream: stream) else {
                        self.noteRefusal(stream: stream)
                        return nil
                    }
                    return (self.localURL(for: $0, stream: stream) ?? $0).absoluteString
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
    static let liveFetch: Fetch = { url, stream in
        try await liveFetch(url, stream: stream, session: session)
    }

    /// `liveFetch` on `session` (tests give a stubbed one). A redirect is followed only to a URL `RelayURLPolicy`
    /// allows for `stream`; a refused one ends the fetch with the 3xx itself.
    nonisolated static func liveFetch(_ url: URL, stream: URL, session: URLSession) async throws -> Upstream {
        // URLSession also opens file: and other schemes; the relay only ever fetches http(s).
        guard RelayURLPolicy.isWebURL(url) else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let redirectGuard = RedirectGuard(stream: stream)
        let (data, response) = try await session.data(for: request, delegate: redirectGuard)
        let http = response as? HTTPURLResponse
        return Upstream(data: data, contentType: http?.value(forHTTPHeaderField: "Content-Type"),
                        status: http?.statusCode ?? 200, finalURL: response.url ?? url,
                        refusedRedirect: redirectGuard.refused)
    }

    /// Security review item 5: a 3xx from an allowed CDN must not take the relay to the Mac or the LAN (or off
    /// http(s)). Logs the refused target's host only.
    nonisolated final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
        private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Relay")
        let stream: URL
        private let refusal = OSAllocatedUnfairLock(initialState: false)

        init(stream: URL) { self.stream = stream }

        /// Re-review L2: `follows` refused a redirect.
        var refused: Bool { refusal.withLock { $0 } }

        /// Whether the relay follows a redirect to `target`.
        func follows(_ target: URL?) -> Bool {
            guard let target, RelayURLPolicy.allows(target, stream: stream) else {
                Self.logger.notice("Refused redirect to \(target?.host() ?? "no host", privacy: .public)")
                refusal.withLock { $0 = true }
                return false
            }
            return true
        }

        // The completion-handler form, like `HDHomeRunHTTP.RedirectBlocker`'s (the async one crashes Swift 6.4's SILGen).
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(follows(request.url) ? request : nil)
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
