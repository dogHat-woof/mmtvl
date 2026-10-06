import Foundation
import os

/// Channel ↔ guide matching (L6, L17). Exact rules only: fuzzy matching was measured and produced wrong channels.
nonisolated enum EPGMatcher {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "IPTV")
    private static let droppedTokens: Set<String> = ["hd", "fhd", "uhd", "sd", "4k", "hevc"]

    /// Lowercases and folds diacritics; `&` → " and ", `+` → " plus "; splits on non-alphanumerics;
    /// drops hd/fhd/uhd/sd/4k/hevc; joins the rest.
    static func normalize(_ name: String) -> String {
        let folded = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "+", with: " plus ")
        return folded
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
            .filter { !droppedTokens.contains($0) }
            .joined()
    }

    /// Channel.ID → EPG id (lowercased), per L6. `overrides` is epg-overrides.json as read (keys and values in any case).
    static func match(_ channels: [Channel], to epgChannels: [EPGChannel], overrides: [String: String] = [:]) -> [Channel.ID: String] {
        let epgIDs = Set(epgChannels.map { $0.id.lowercased() })
        var byName: [String: String] = [:]
        for epg in epgChannels {
            for name in epg.names {
                let key = normalize(name)
                if !key.isEmpty, byName[key] == nil { byName[key] = epg.id.lowercased() }
            }
        }
        var lowerOverrides: [String: String] = [:]
        for (key, value) in overrides {
            lowerOverrides[key.lowercased()] = value.lowercased()
        }

        var result: [Channel.ID: String] = [:]
        for channel in channels {
            // 1. An override by name, then by tvg-id, whose target exists in the guide.
            let overrideTarget = lowerOverrides[channel.name.lowercased()]
                ?? channel.tvgID.flatMap { lowerOverrides[$0.lowercased()] }
            if let target = overrideTarget {
                if epgIDs.contains(target) {
                    result[channel.id] = target
                    continue
                }
                logger.debug("Override target \(target, privacy: .public) for \(channel.name, privacy: .public) isn't in the guide")
            }
            // 2. tvg-id equals an EPG id, ignoring case.
            if let tvgID = channel.tvgID?.lowercased(), epgIDs.contains(tvgID) {
                result[channel.id] = tvgID
                continue
            }
            // 3. Normalized tvg-name or name equals a normalized display name.
            for name in [channel.tvgName, channel.name].compactMap({ $0 }) {
                let key = normalize(name)
                if !key.isEmpty, let id = byName[key] {
                    result[channel.id] = id
                    break
                }
            }
        }
        return result
    }
}
