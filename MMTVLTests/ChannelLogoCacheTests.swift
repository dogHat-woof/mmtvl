import Foundation
import Testing
@testable import MMTVL

struct ChannelLogoCacheTests {
    /// Counts fetches per URL and the most running at once; URLs containing "fail" throw.
    nonisolated final class Fetcher: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]
        private var running = 0
        private(set) var maxRunning = 0
        let delay: Duration

        init(delay: Duration = .zero) { self.delay = delay }

        func count(_ url: URL) -> Int { lock.withLock { counts[url.absoluteString, default: 0] } }
        var mostAtOnce: Int { lock.withLock { maxRunning } }

        var fetch: ChannelLogoCache.Fetch {
            { [self] url in
                lock.withLock {
                    counts[url.absoluteString, default: 0] += 1
                    running += 1
                    maxRunning = max(maxRunning, running)
                }
                if delay > .zero { try? await Task.sleep(for: delay) }
                lock.withLock { running -= 1 }
                if url.absoluteString.contains("fail") { throw URLError(.badServerResponse) }
                return ShelfImageLoaderTests.png
            }
        }
    }

    private func logo(_ n: Int, _ path: String = "logo") -> URL {
        URL(string: "http://logos.example/\(path)/\(n).png")!
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "ChannelLogoCacheTests-\(UUID().uuidString)")
    }

    private func settle(_ cache: ChannelLogoCache) async {
        for _ in 0..<500 where !cache.isIdle {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func loadsOnceAndKeepsInMemory() async {
        let fetcher = Fetcher()
        let cache = ChannelLogoCache(directory: nil, fetch: fetcher.fetch)
        #expect(cache.image(for: logo(1)) == nil)
        #expect(cache.image(for: logo(1)) == nil)   // loading: no second fetch
        await settle(cache)
        #expect(cache.image(for: logo(1)) != nil)
        #expect(fetcher.count(logo(1)) == 1)
    }

    @Test func aNewCacheReadsTheDiskWithoutFetching() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = Fetcher()
        let cache = ChannelLogoCache(directory: directory, fetch: first.fetch)
        _ = cache.image(for: logo(1))
        await settle(cache)
        #expect(first.count(logo(1)) == 1)
        // The file is named by the URL's hash, never the URL.
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(files == [ChannelLogoCache.fileName(for: logo(1))])

        let second = Fetcher()
        let relaunched = ChannelLogoCache(directory: directory, fetch: second.fetch)
        _ = relaunched.image(for: logo(1))
        await settle(relaunched)
        #expect(relaunched.image(for: logo(1)) != nil)
        #expect(second.count(logo(1)) == 0)
    }

    @Test func aStaleFileIsFetchedAgain() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = Fetcher()
        let cache = ChannelLogoCache(directory: directory, fetch: first.fetch)
        _ = cache.image(for: logo(1))
        await settle(cache)

        let later = Date().addingTimeInterval(ChannelLogoCache.maxFileAge + 60)
        let second = Fetcher()
        let relaunched = ChannelLogoCache(directory: directory, fetch: second.fetch, now: { later })
        _ = relaunched.image(for: logo(1))
        await settle(relaunched)
        #expect(second.count(logo(1)) == 1)
    }

    @Test func aFailureIsNotRetriedForTenMinutes() async {
        let fetcher = Fetcher()
        var time = Date()
        let cache = ChannelLogoCache(directory: nil, fetch: fetcher.fetch, now: { time })
        _ = cache.image(for: logo(1, "fail"))
        await settle(cache)
        #expect(cache.image(for: logo(1, "fail")) == nil)
        await settle(cache)
        #expect(fetcher.count(logo(1, "fail")) == 1)
        time += ChannelLogoCache.failureMemory + 1
        _ = cache.image(for: logo(1, "fail"))
        await settle(cache)
        #expect(fetcher.count(logo(1, "fail")) == 2)
    }

    @Test func atMostSixLoadsAtOnce() async {
        let fetcher = Fetcher(delay: .milliseconds(20))
        let cache = ChannelLogoCache(directory: nil, fetch: fetcher.fetch)
        cache.prefetch((0..<20).map { logo($0) })
        await settle(cache)
        #expect(fetcher.mostAtOnce <= ChannelLogoCache.maxConcurrentFetches)
        #expect((0..<20).allSatisfy { cache.image(for: logo($0)) != nil })
    }

    @Test func theOldestIsDroppedFromMemory() async {
        let fetcher = Fetcher()
        let cache = ChannelLogoCache(directory: nil, fetch: fetcher.fetch)
        for n in 0...ChannelLogoCache.maxEntries {
            _ = cache.image(for: logo(n))
            await settle(cache)
        }
        #expect(cache.image(for: logo(0)) == nil)
        #expect(cache.image(for: logo(ChannelLogoCache.maxEntries)) != nil)
    }
}
