import AppKit
import CryptoKit
import ImageIO
import Observation
import os
import SwiftUI

/// M7c L24: channel logos, downsampled, in memory and on disk (`~/Library/Caches/dev.mmtvl.launcher/ChannelLogos/`,
/// one file per logo named by the SHA-256 of its URL, so no token lands in a file name). At most
/// `maxConcurrentFetches` loads run at once, newest request first. Logs hosts only.
@Observable
final class ChannelLogoCache {
    typealias Fetch = @Sendable (URL) async throws -> Data

    static let shared = ChannelLogoCache(directory: ChannelLogoCache.defaultDirectory)

    /// The guide's and banner's logos are at most 160 points, drawn at 2×.
    nonisolated static let maxPixelSize = 320
    static let maxEntries = 300
    static let maxConcurrentFetches = 6
    static let failureMemory: TimeInterval = 10 * 60
    nonisolated static let maxFileAge: TimeInterval = 30 * 24 * 60 * 60
    nonisolated static let maxFiles = 3000

    nonisolated static var defaultDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "dev.mmtvl.launcher/ChannelLogos", directoryHint: .isDirectory)
    }

    private var images: [URL: NSImage] = [:]
    /// Insertion order of `images`, oldest first.
    @ObservationIgnored private var order: [URL] = []
    /// Requested and not yet loading; the newest is loaded first.
    @ObservationIgnored private var waiting: [URL] = []
    @ObservationIgnored private var loading: Set<URL> = []
    @ObservationIgnored private var failures: [URL: Date] = [:]
    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let directory: URL?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "IPTV")

    /// `directory` nil = memory only.
    init(directory: URL?, fetch: @escaping Fetch = ChannelLogoCache.liveFetch, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.fetch = fetch
        self.now = now
    }

    /// The logo if it's in memory; otherwise nil, and a load starts (the view redraws when it lands).
    func image(for url: URL) -> NSImage? {
        if let image = images[url] { return image }
        request(url)
        return nil
    }

    /// Loads logos before they're shown (the Live pages, the guide's rows around the focus).
    func prefetch(_ urls: [URL]) {
        // Reversed: the first URL is loaded first.
        for url in urls.reversed() where images[url] == nil { request(url) }
    }

    /// True while nothing is loading or waiting (tests).
    var isIdle: Bool { loading.isEmpty && waiting.isEmpty }

    /// Removes the oldest files beyond `maxFiles`. Called once at launch.
    func pruneDisk() {
        guard let directory else { return }
        Task { await Self.prune(directory) }
    }

    // MARK: - Private

    private func request(_ url: URL) {
        guard !loading.contains(url) else { return }
        if let failedAt = failures[url], now().timeIntervalSince(failedAt) < Self.failureMemory { return }
        waiting.removeAll { $0 == url }
        waiting.append(url)
        startWaiting()
    }

    private func startWaiting() {
        while loading.count < Self.maxConcurrentFetches, let url = waiting.popLast() {
            loading.insert(url)
            let file = directory.map { $0.appending(path: Self.fileName(for: url)) }
            let fetch = fetch
            let date = now()
            Task { [weak self] in
                let image = await Self.load(url, file: file, fetch: fetch, now: date)
                self?.finish(url, image)
            }
        }
    }

    private func finish(_ url: URL, _ cgImage: CGImage?) {
        loading.remove(url)
        if let cgImage {
            failures[url] = nil
            images[url] = NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
            order.append(url)
            while order.count > Self.maxEntries {
                images[order.removeFirst()] = nil
            }
        } else {
            failures[url] = now()
            logger.info("Channel logo from \(url.host() ?? "?", privacy: .public) failed")
        }
        startWaiting()
    }

    nonisolated static func fileName(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// From disk when the file is fresh, else from the network (and then saved).
    @concurrent nonisolated private static func load(_ url: URL, file: URL?, fetch: Fetch, now: Date) async -> CGImage? {
        let manager = FileManager.default
        if let file, let attributes = try? manager.attributesOfItem(atPath: file.path),
           let modified = attributes[.modificationDate] as? Date, now.timeIntervalSince(modified) < maxFileAge {
            if let data = try? Data(contentsOf: file), let image = downsample(data) { return image }
            try? manager.removeItem(at: file)
        }
        guard let data = try? await fetch(url), let image = downsample(data) else { return nil }
        if let file {
            try? manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
        return image
    }

    nonisolated static func downsample(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    @concurrent nonisolated private static func prune(_ directory: URL) async {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]),
              files.count > maxFiles
        else { return }
        let dated = files.map { file in
            (file, (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        for (file, _) in dated.sorted(by: { $0.1 < $1.1 }).prefix(files.count - maxFiles) {
            try? manager.removeItem(at: file)
        }
    }

    /// Its own session without a URL cache (this is the cache); non-2xx is a failure.
    static let liveFetch: Fetch = { url in
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = maxConcurrentFetches
        return URLSession(configuration: configuration)
    }()
}

/// A channel logo from `ChannelLogoCache`, scaled to fit; `placeholder` until it loads (or without a URL).
struct ChannelLogoView<Placeholder: View>: View {
    let url: URL?
    var cache: ChannelLogoCache = .shared
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        if let url, let image = cache.image(for: url) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            placeholder()
        }
    }
}

extension ChannelLogoView where Placeholder == Color {
    init(url: URL?, cache: ChannelLogoCache = .shared) {
        self.init(url: url, cache: cache) { Color.clear }
    }
}
