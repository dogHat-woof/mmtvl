import Foundation
import os

/// M7c L29: the provider's stream URL answers with a redirect (~0.5 s of server time) to its CDN, and mpv's stream
/// layer and ffmpeg's HLS demuxer would each follow it. MMTVL follows it once with URLSession and remembers the CDN
/// address for `lifetime`, so a zap to a channel resolved ahead of time skips it entirely. Never logs URLs.
/// Re-review L2: each redirect hop is judged by `RelayURLPolicy` with the M3U entry's own URL as the stream, so a
/// redirect to the Mac or a LAN host other than the entry's never becomes the stream's (and the relay's) own host.
/// Pre-release lows (c): an entry that is itself on the LAN may redirect to another LAN device's private address
/// (a Threadfin/xTeVe proxy to a tuner), never to the Mac's own; the relay and its `RedirectGuard` judge alike.
final class StreamResolver {
    typealias Resolve = @Sendable (URL) async throws -> URL

    static let shared = StreamResolver()
    /// Measured valid for at least 60 s (M7c probe); a stale address is dropped on the first stream error.
    static let lifetime: TimeInterval = 60

    private var cache: [URL: (url: URL, resolvedAt: Date)] = [:]
    private var inFlight: [URL: Task<URL?, Never>] = [:]
    private let resolveRedirect: Resolve
    private let now: () -> Date
    private let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "MPV")

    init(resolve: @escaping Resolve = StreamResolver.liveResolve, now: @escaping () -> Date = Date.init) {
        resolveRedirect = resolve
        self.now = now
    }

    /// The fresh resolved address, if any.
    func cached(_ url: URL) -> URL? {
        guard let entry = cache[url], now().timeIntervalSince(entry.resolvedAt) < Self.lifetime else { return nil }
        return entry.url
    }

    /// The CDN address (cached, or joined with a fetch already running, or fetched); the original on failure.
    func resolve(_ url: URL) async -> URL {
        if let cached = cached(url) { return cached }
        return await fetch(url) ?? url
    }

    /// Resolves ahead of time (the channels a zap is likely to reach).
    func prefetch(_ urls: [URL]) {
        for url in urls where cached(url) == nil && inFlight[url] == nil {
            Task { _ = await fetch(url) }
        }
    }

    /// A stream error: the next load resolves again.
    func invalidate(_ url: URL) {
        cache[url] = nil
    }

    private func fetch(_ url: URL) async -> URL? {
        if let task = inFlight[url] { return await task.value }
        let resolveRedirect = resolveRedirect
        let started = ContinuousClock.now
        let task = Task { try? await resolveRedirect(url) }
        inFlight[url] = task
        var resolved = await task.value
        inFlight[url] = nil
        // Re-review L2: the address must be one the relay would fetch for the entry (`liveResolve` already stops at
        // such a hop; this also holds for any other resolver).
        if let target = resolved, target != url, !RelayURLPolicy.allows(target, stream: url) {
            logger.notice("Refused a stream redirect from \(url.host() ?? "?", privacy: .public) to \(target.host() ?? "no host", privacy: .public)")
            resolved = nil
        }
        if let resolved {
            cache[url] = (resolved, now())
            let elapsed = ContinuousClock.now - started
            let ms = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
            logger.info("Resolved a stream from \(url.host() ?? "?", privacy: .public) to \(resolved.host() ?? "?", privacy: .public) in \(ms) ms")
        } else {
            logger.info("Resolving a stream from \(url.host() ?? "?", privacy: .public) failed; mpv follows it")
        }
        return resolved
    }

    /// Follows redirects and stops at the final response's headers (the body isn't read). Non-2xx is a failure.
    static let liveResolve: Resolve = { url in
        try await liveResolve(url, session: session)
    }

    /// `liveResolve` on `session` (tests give a stubbed one). Re-review L2: a redirect is followed only where
    /// `RelayURLPolicy` allows it for the entry `url` (`HLSRelay.RedirectGuard`); a refused one ends with the 3xx,
    /// a failure, so the entry stays unresolved.
    nonisolated static func liveResolve(_ url: URL, session: URLSession) async throws -> URL {
        guard RelayURLPolicy.isWebURL(url) else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (bytes, response) = try await session.bytes(for: request, delegate: HLSRelay.RedirectGuard(stream: url))
        bytes.task.cancel()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let final = http.url else {
            throw URLError(.badServerResponse)
        }
        return final
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
}
