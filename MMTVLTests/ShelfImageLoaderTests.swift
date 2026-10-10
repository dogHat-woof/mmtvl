import AppKit
import Foundation
import Testing
@testable import MMTVL

struct ShelfImageLoaderTests {
    /// A tiny PNG.
    nonisolated static let png: Data = {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }()

    /// Counts fetches per URL; URLs containing "fail" throw.
    nonisolated final class Fetcher: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]
        private var headersSeen: [[String: String]] = []

        func count(_ url: URL) -> Int { lock.withLock { counts[url.absoluteString, default: 0] } }
        var headers: [[String: String]] { lock.withLock { headersSeen } }

        var fetch: ShelfImageLoader.Fetch {
            { [self] url, headers in
                lock.withLock {
                    counts[url.absoluteString, default: 0] += 1
                    headersSeen.append(headers)
                }
                if url.absoluteString.contains("fail") { throw URLError(.badServerResponse) }
                return ShelfImageLoaderTests.png
            }
        }
    }

    private func remote(_ n: Int, _ path: String = "img") -> ShelfCard.Image {
        .remote(URL(string: "https://server/\(path)/\(n)")!, headers: ["X-Plex-Token": "t"])
    }

    @Test func loadsOnceAndCaches() async {
        let fetcher = Fetcher()
        let loader = ShelfImageLoader(fetch: fetcher.fetch)
        #expect(loader.image(for: remote(1)) == nil)
        #expect(loader.image(for: remote(1)) == nil)   // in flight: no second fetch
        await loader.lastTask?.value
        #expect(loader.image(for: remote(1)) != nil)
        #expect(fetcher.count(URL(string: "https://server/img/1")!) == 1)
        #expect(fetcher.headers.first == ["X-Plex-Token": "t"])
        #expect(loader.image(for: .channelLogo(nil)) == nil)
    }

    @Test func keepsAtMostSixtyImages() async {
        let fetcher = Fetcher()
        let loader = ShelfImageLoader(fetch: fetcher.fetch)
        for n in 0...60 {
            _ = loader.image(for: remote(n))
            await loader.lastTask?.value
        }
        // The oldest was dropped and is fetched again.
        #expect(loader.image(for: remote(0)) == nil)
        await loader.lastTask?.value
        #expect(fetcher.count(URL(string: "https://server/img/0")!) == 2)
        #expect(loader.image(for: remote(60)) != nil)
    }

    /// M7c L14: the same URL at another width is another image.
    @Test func keysByWidth() async {
        let fetcher = Fetcher()
        let loader = ShelfImageLoader(fetch: fetcher.fetch)
        _ = loader.image(for: remote(1))
        await loader.lastTask?.value
        #expect(loader.image(for: remote(1)) != nil)
        #expect(loader.image(for: remote(1), maxPixelWidth: 1920) == nil)
        await loader.lastTask?.value
        #expect(loader.image(for: remote(1), maxPixelWidth: 1920) != nil)
        #expect(fetcher.count(URL(string: "https://server/img/1")!) == 2)
    }

    /// M7c L14: backdrops are capped at 12, apart from the 60 card images.
    @Test func backdropsAreCappedSeparately() async {
        let fetcher = Fetcher()
        let loader = ShelfImageLoader(fetch: fetcher.fetch)
        _ = loader.image(for: remote(100))
        await loader.lastTask?.value
        for n in 0...12 {
            _ = loader.image(for: remote(n), maxPixelWidth: 1920)
            await loader.lastTask?.value
        }
        #expect(loader.image(for: remote(0), maxPixelWidth: 1920) == nil)   // dropped
        await loader.lastTask?.value
        #expect(loader.image(for: remote(12), maxPixelWidth: 1920) != nil)
        #expect(loader.image(for: remote(100)) != nil)                      // the card image stays
    }

    @Test func failuresAreRememberedForFiveMinutes() async {
        let fetcher = Fetcher()
        var now = Date(timeIntervalSince1970: 0)
        let loader = ShelfImageLoader(fetch: fetcher.fetch, now: { now })
        let failing = remote(1, "fail")
        _ = loader.image(for: failing)
        await loader.lastTask?.value
        _ = loader.image(for: failing)
        #expect(fetcher.count(URL(string: "https://server/fail/1")!) == 1)
        now += 301
        _ = loader.image(for: failing)
        await loader.lastTask?.value
        #expect(fetcher.count(URL(string: "https://server/fail/1")!) == 2)
    }
}
