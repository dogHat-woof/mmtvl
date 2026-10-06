import Foundation
import os

/// Download → gunzip → parse → match → store (L5).
nonisolated enum GuideImporter {
    struct Outcome: Sendable, Equatable {
        var programmeCount: Int
        var matchedChannels: Int
    }

    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "IPTV")

    /// MUST be @concurrent: parsing a big file must not run on the main actor.
    /// Keeps programmes overlapping [now − 6 h, now + 4 d], only for EPG channels matched to a playlist channel,
    /// and every <channel>. Deletes the temporary files afterwards (also on error).
    @concurrent static func importGuide(from url: URL, channels: [Channel], overrides: [String: String],
                                        store: EPGStore, network: IPTVNetwork, now: Date) async throws -> Outcome {
        let downloaded = try await network.download(url)
        defer { try? FileManager.default.removeItem(at: downloaded) }

        var xmlURL = downloaded
        var unzipped: URL?
        defer { if let unzipped { try? FileManager.default.removeItem(at: unzipped) } }
        if try Gunzip.isGzip(downloaded) {
            let directory = URL.cachesDirectory.appending(path: "MMTVL", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Unique, so overlapping imports (tests run in parallel) don't share a file.
            let destination = directory.appending(path: "guide-\(UUID().uuidString).xml")
            unzipped = destination
            try Gunzip.decompress(downloaded, to: destination)
            xmlURL = destination
        }

        let window = DateInterval(start: now.addingTimeInterval(-6 * 3600), end: now.addingTimeInterval(4 * 24 * 3600))
        var matched = 0
        let result = try XMLTVParser.parse(fileURL: xmlURL, window: window) { parsedChannels in
            let matches = EPGMatcher.match(channels, to: parsedChannels, overrides: overrides)
            matched = matches.count
            return Set(matches.values)
        }
        try await store.replaceAll(channels: result.channels, programmes: result.programmes)
        logger.info("Guide from \(url.host() ?? "?", privacy: .public): \(result.channels.count) channels, \(result.programmes.count) programmes, \(matched) playlist channels matched")
        return Outcome(programmeCount: result.programmes.count, matchedChannels: matched)
    }
}
