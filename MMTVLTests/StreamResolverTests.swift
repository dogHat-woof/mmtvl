import Foundation
import Testing
@testable import MMTVL

struct StreamResolverTests {
    /// Resolves `…/<name>` to `https://cdn.example/<name>`; names containing "fail" throw.
    nonisolated final class Redirects: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]
        let delay: Duration

        init(delay: Duration = .zero) { self.delay = delay }

        func count(_ url: URL) -> Int { lock.withLock { counts[url.absoluteString, default: 0] } }

        var resolve: StreamResolver.Resolve {
            { [self] url in
                lock.withLock { counts[url.absoluteString, default: 0] += 1 }
                if delay > .zero { try? await Task.sleep(for: delay) }
                if url.absoluteString.contains("fail") { throw URLError(.badServerResponse) }
                return URL(string: "https://cdn.example/\(url.lastPathComponent)")!
            }
        }
    }

    private let stream = URL(string: "https://provider.example/live/1")!

    @Test func resolvesOnceAndCachesForTheLifetime() async {
        let redirects = Redirects()
        var time = Date()
        let resolver = StreamResolver(resolve: redirects.resolve, now: { time })
        #expect(resolver.cached(stream) == nil)
        #expect(await resolver.resolve(stream) == URL(string: "https://cdn.example/1")!)
        #expect(resolver.cached(stream) == URL(string: "https://cdn.example/1")!)
        _ = await resolver.resolve(stream)
        #expect(redirects.count(stream) == 1)

        time += StreamResolver.lifetime + 1
        #expect(resolver.cached(stream) == nil)
        _ = await resolver.resolve(stream)
        #expect(redirects.count(stream) == 2)
    }

    @Test func concurrentResolvesShareOneFetch() async {
        let redirects = Redirects(delay: .milliseconds(50))
        let resolver = StreamResolver(resolve: redirects.resolve)
        resolver.prefetch([stream])
        let resolved = await resolver.resolve(stream)
        #expect(resolved == URL(string: "https://cdn.example/1")!)
        #expect(redirects.count(stream) == 1)
    }

    @Test func aFailureFallsBackToTheOriginalAndIsntCached() async {
        let redirects = Redirects()
        let resolver = StreamResolver(resolve: redirects.resolve)
        let failing = URL(string: "https://provider.example/live/fail")!
        #expect(await resolver.resolve(failing) == failing)
        #expect(resolver.cached(failing) == nil)
        _ = await resolver.resolve(failing)
        #expect(redirects.count(failing) == 2)
    }

    @Test func invalidateDropsTheEntry() async {
        let redirects = Redirects()
        let resolver = StreamResolver(resolve: redirects.resolve)
        _ = await resolver.resolve(stream)
        resolver.invalidate(stream)
        #expect(resolver.cached(stream) == nil)
        _ = await resolver.resolve(stream)
        #expect(redirects.count(stream) == 2)
    }
}
