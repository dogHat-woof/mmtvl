import Foundation

/// Match Guide's ranked suggestions (M6b L7). Suggestions only: automatic matching stays exact (M4 L6).
nonisolated enum EPGSuggester {
    struct Candidate: Equatable, Sendable {
        var ref: EPGRef
        /// First display name, else the EPG id.
        var name: String
        var score: Double
    }

    /// Off the main actor: ALL_SOURCES1 has 27k channels.
    @concurrent static func suggest(for channel: Channel, in sources: [EPGSourceChannels], limit: Int = 30) async -> [Candidate] {
        rank(channel, in: sources, limit: limit)
    }

    /// Scores each guide channel by the IDF weight of the tokens it shares with the channel, over the channel's own
    /// weight (0…1). Ties: fewer extra tokens, then guide order, then id. Only scores above 0; at most `limit`.
    static func rank(_ channel: Channel, in sources: [EPGSourceChannels], limit: Int) -> [Candidate] {
        let channelTokens = tokenSet([channel.name, channel.tvgName].compactMap { $0 }, id: channel.tvgID)
        guard !channelTokens.isEmpty else { return [] }

        struct Entry {
            var ref: EPGRef
            var name: String
            var tokens: Set<String>
            var sourceIndex: Int
        }
        var entries: [Entry] = []
        var documentFrequency: [String: Int] = [:]
        for (sourceIndex, source) in sources.enumerated() {
            for epg in source.channels {
                let tokens = tokenSet(epg.names, id: epg.id)
                for token in tokens { documentFrequency[token, default: 0] += 1 }
                entries.append(Entry(ref: EPGRef(sourceID: source.sourceID, epgID: epg.id.lowercased()),
                                     name: epg.names.first ?? epg.id, tokens: tokens, sourceIndex: sourceIndex))
            }
        }
        let count = Double(entries.count)
        func idf(_ token: String) -> Double { log(1 + count / Double(max(documentFrequency[token] ?? 1, 1))) }
        let total = channelTokens.reduce(0) { $0 + idf($1) }
        guard total > 0 else { return [] }

        let scored = entries.compactMap { entry -> (entry: Entry, score: Double, extra: Int)? in
            let shared = channelTokens.intersection(entry.tokens)
            guard !shared.isEmpty else { return nil }
            let score = shared.reduce(0) { $0 + idf($1) } / total
            return (entry, score, entry.tokens.subtracting(channelTokens).count)
        }
        return scored
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                if a.extra != b.extra { return a.extra < b.extra }
                if a.entry.sourceIndex != b.entry.sourceIndex { return a.entry.sourceIndex < b.entry.sourceIndex }
                return a.entry.ref.epgID < b.entry.ref.epgID
            }
            .prefix(limit)
            .map { Candidate(ref: $0.entry.ref, name: $0.entry.name, score: $0.score) }
    }

    /// Tokens of every name, plus the id's without its last one ("nflnetwork.us" → "nflnetwork").
    private static func tokenSet(_ names: [String], id: String?) -> Set<String> {
        var tokens = Set(names.flatMap(EPGMatcher.tokens))
        if let id {
            let idTokens = EPGMatcher.tokens(id)
            if idTokens.count >= 2 { tokens.formUnion(idTokens.dropLast()) }
        }
        return tokens
    }
}
