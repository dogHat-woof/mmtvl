import Foundation
import os

/// Download → gunzip → parse → match → store (L5).
nonisolated enum GuideImporter {
    struct Outcome: Sendable, Equatable {
        var programmeCount: Int
        var matchedChannels: Int
    }

    /// Channels → the guide's channel ids (lowercased), given the guide's channels and `epg-overrides.json`.
    typealias Matcher = @Sendable (_ channels: [Channel], _ epgChannels: [EPGChannel],
                                   _ overrides: [String: String]) -> [Channel.ID: String]

    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "IPTV")

    /// MUST be @concurrent: parsing a big file must not run on the main actor.
    /// Keeps programmes overlapping [now − 6 h, now + 4 d], only for EPG channels `matcher` matches to one of
    /// `channels`, and every <channel>. Replaces only this guide's rows (`sourceID`, M6b L3). Deletes the temporary
    /// files afterwards (also on error). Logs `url`'s host only (M7j L10: the antenna guide's query is a token).
    /// M7j step 8 (security L3): `maxDownloadBytes` and `maxUnzippedBytes` limit the body and its gunzipped form
    /// (nil, the default: no limit, as for pasted guides).
    @concurrent static func importGuide(from url: URL, sourceID: String, channels: [Channel], overrides: [String: String],
                                        store: EPGStore, network: IPTVNetwork, now: Date,
                                        matcher: Matcher = { EPGMatcher.match($0, to: $1, overrides: $2) },
                                        maxDownloadBytes: Int? = nil, maxUnzippedBytes: Int? = nil)
        async throws -> Outcome {
        let downloaded = try await network.download(url, maxBytes: maxDownloadBytes)
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
            try Gunzip.decompress(downloaded, to: destination, maxOutputBytes: maxUnzippedBytes)
            xmlURL = destination
        }

        let window = DateInterval(start: now.addingTimeInterval(-6 * 3600), end: now.addingTimeInterval(4 * 24 * 3600))
        var matched = 0
        let result = try XMLTVParser.parse(fileURL: xmlURL, window: window) { parsedChannels in
            let matches = matcher(channels, parsedChannels, overrides)
            matched = matches.count
            return Set(matches.values)
        }
        try await store.replaceSource(sourceID, channels: result.channels, programmes: result.programmes)
        logger.info("Guide from \(url.host() ?? "?", privacy: .public): \(result.channels.count) channels, \(result.programmes.count) programmes, \(matched) channels matched")
        return Outcome(programmeCount: result.programmes.count, matchedChannels: matched)
    }
}
