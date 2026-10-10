import AppKit
import ImageIO
import Observation
import os

/// Top shelf card images fetched with headers (Plex: the token goes in `X-Plex-Token`, never the URL). M7 step 12.
/// In memory only: at most `maxEntries` images (oldest dropped); a failed URL isn't retried for `failureMemory`.
@Observable
final class ShelfImageLoader {
    typealias Fetch = @Sendable (URL, [String: String]) async throws -> Data

    static let maxEntries = 60
    /// M7c L14: images wider than `maxPixelWidth` (carousel backdrops) are kept apart, at most this many.
    static let maxBackdropEntries = 12
    static let failureMemory: TimeInterval = 5 * 60
    /// Cards are 352 points wide, drawn at up to 2×.
    nonisolated static let maxPixelWidth = 704

    private var images: [String: NSImage] = [:]
    /// Insertion order of `images`, oldest first: card-sized and large images separately.
    @ObservationIgnored private var order: [String] = []
    @ObservationIgnored private var backdropOrder: [String] = []
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private var failures: [String: Date] = [:]
    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let now: () -> Date
    /// The last fetch started; tests await it.
    @ObservationIgnored private(set) var lastTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "TopShelf")

    init(fetch: @escaping Fetch = ShelfImageLoader.liveFetch, now: @escaping () -> Date = Date.init) {
        self.fetch = fetch
        self.now = now
    }

    /// A cached image, or nil while one fetch runs (the view redraws when it lands). `.channelLogo` → nil (`ChannelLogoCache`).
    /// `maxPixelWidth`: 704 for cards, 1920 for carousel backdrops (M7c L14); the cache key includes it.
    func image(for image: ShelfCard.Image, maxPixelWidth: Int = ShelfImageLoader.maxPixelWidth) -> NSImage? {
        guard case .remote(let url, let headers) = image else { return nil }
        let key = Self.key(url, maxPixelWidth)
        if let cached = images[key] { return cached }
        if let failedAt = failures[key], now().timeIntervalSince(failedAt) < Self.failureMemory { return nil }
        guard !inFlight.contains(key) else { return nil }
        inFlight.insert(key)
        let fetch = fetch
        lastTask = Task { [weak self] in
            let result: NSImage?
            do {
                result = Self.downsample(try await fetch(url, headers), maxPixelWidth: maxPixelWidth)
            } catch {
                result = nil
            }
            self?.finish(key, result, isLarge: maxPixelWidth > Self.maxPixelWidth, host: url.host())
        }
        return nil
    }

    nonisolated static func key(_ url: URL, _ maxPixelWidth: Int) -> String {
        "\(maxPixelWidth) \(url.absoluteString)"
    }

    private func finish(_ key: String, _ image: NSImage?, isLarge: Bool, host: String?) {
        inFlight.remove(key)
        guard let image else {
            failures[key] = now()
            logger.info("Shelf image from \(host ?? "?", privacy: .public) failed")
            return
        }
        failures[key] = nil
        images[key] = image
        if isLarge {
            backdropOrder.append(key)
            while backdropOrder.count > Self.maxBackdropEntries {
                images[backdropOrder.removeFirst()] = nil
            }
        } else {
            order.append(key)
            while order.count > Self.maxEntries {
                images[order.removeFirst()] = nil
            }
        }
    }

    nonisolated static func downsample(_ data: Data, maxPixelWidth: Int = maxPixelWidth) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelWidth,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
    }

    /// Ephemeral `URLSession`; non-2xx is a failure.
    static let liveFetch: Fetch = { url, headers in
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static let session = URLSession(configuration: .ephemeral)
}
