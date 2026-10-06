import Foundation
import os

/// Channel ↔ guide matching (L6, L17). Exact rules only: fuzzy matching was measured and produced wrong channels.
nonisolated enum EPGMatcher {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "IPTV")
    private static let droppedTokens: Set<String> = ["hd", "fhd", "uhd", "sd", "4k", "hevc"]

    /// Lowercases and folds diacritics; `&` → " and ", `+` → " plus "; splits on non-alphanumerics;
    /// drops hd/fhd/uhd/sd/4k/hevc; joins the rest.
    static func normalize(_ name: String) -> String {
        rawTokens(name).joined()
    }

    /// M6b L7: normalize's tokens before the join, de-duplicated keeping the first occurrence.
    static func tokens(_ name: String) -> [String] {
        var seen: Set<String> = []
        return rawTokens(name).filter { seen.insert($0).inserted }
    }

    private static func rawTokens(_ name: String) -> [String] {
        let folded = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "+", with: " plus ")
        return folded
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
            .filter { !droppedTokens.contains($0) }
    }

    /// One guide (the importer): Channel.ID → EPG id (lowercased), per L6.
    static func match(_ channels: [Channel], to epgChannels: [EPGChannel], overrides: [String: String] = [:]) -> [Channel.ID: String] {
        match(channels, sources: [EPGSourceChannels(sourceID: "", channels: epgChannels)], overrides: overrides)
            .mapValues(\.epgID)
    }

    /// Channel.ID → guide channel, per L6, rule by rule, then guide by guide (M6b L3): `sources` in priority order.
    /// `overrides` is epg-overrides.json as read (keys and values in any case); a value "" means no guide.
    static func match(_ channels: [Channel], sources: [EPGSourceChannels], overrides: [String: String] = [:]) -> [Channel.ID: EPGRef] {
        let indexes = sources.map { source in
            var ids: Set<String> = []
            var byName: [String: String] = [:]
            for epg in source.channels {
                let id = epg.id.lowercased()
                ids.insert(id)
                for name in epg.names {
                    let key = normalize(name)
                    if !key.isEmpty, byName[key] == nil { byName[key] = id }
                }
            }
            return (sourceID: source.sourceID, ids: ids, byName: byName)
        }
        func firstSource(containing id: String) -> EPGRef? {
            indexes.first { $0.ids.contains(id) }.map { EPGRef(sourceID: $0.sourceID, epgID: id) }
        }
        var lowerOverrides: [String: String] = [:]
        for (key, value) in overrides {
            lowerOverrides[key.lowercased()] = value.lowercased()
        }

        var result: [Channel.ID: EPGRef] = [:]
        channelLoop: for channel in channels {
            // 1. An override by name, then by tvg-id, whose target exists in a guide. "" = no guide.
            let overrideTarget = lowerOverrides[channel.name.lowercased()]
                ?? channel.tvgID.flatMap { lowerOverrides[$0.lowercased()] }
            if let target = overrideTarget {
                if target.isEmpty { continue }
                if let ref = firstSource(containing: target) {
                    result[channel.id] = ref
                    continue
                }
                logger.debug("Override target \(target, privacy: .public) for \(channel.name, privacy: .public) isn't in the guide")
            }
            // 2. tvg-id equals an EPG id, ignoring case.
            if let tvgID = channel.tvgID?.lowercased(), let ref = firstSource(containing: tvgID) {
                result[channel.id] = ref
                continue
            }
            // 3. Normalized tvg-name or name equals a normalized display name.
            for name in [channel.tvgName, channel.name].compactMap({ $0 }) {
                let key = normalize(name)
                guard !key.isEmpty else { continue }
                for index in indexes {
                    if let id = index.byName[key] {
                        result[channel.id] = EPGRef(sourceID: index.sourceID, epgID: id)
                        continue channelLoop
                    }
                }
            }
        }
        return result
    }
}

/// One guide's channels, for matching across guides (M6b L3).
nonisolated struct EPGSourceChannels: Sendable {
    var sourceID: String
    var channels: [EPGChannel]
}
