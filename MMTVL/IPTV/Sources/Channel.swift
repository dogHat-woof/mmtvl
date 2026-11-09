import Foundation

/// A live channel from the playlist. Kept in memory only (D23).
nonisolated struct Channel: Identifiable, Hashable, Sendable {
    /// See `ChannelList.make`.
    let id: String
    /// 1-based position among kept channels.
    let number: Int
    let name: String
    /// entry.group ?? "Other".
    let group: String
    let tvgID: String?
    let tvgName: String?
    let logoURL: URL?
    let streamURL: URL
}

nonisolated enum ChannelList {
    static let allChannelsGroup = "All Channels"
    static let otherGroup = "Other"

    /// Keeps entries whose URL is http(s) and not VOD (path contains "/movie/" or "/series/", or ends in .mp4/.mkv/.avi/.mov).
    /// id: "id:" + tvgID.lowercased(), else "name:" + name.lowercased(); duplicates get "#2", "#3"… in order.
    /// name: entry.name, else tvgName, else "Channel \(number)"; a game feed's "-H"/"-A" is spelled out (M7f L13).
    static func make(from playlist: M3UPlaylist) -> [Channel] {
        var channels: [Channel] = []
        var idCounts: [String: Int] = [:]
        for entry in playlist.entries {
            guard let url = URL(string: entry.url), isLiveStream(url) else { continue }
            let number = channels.count + 1
            let playlistName = !entry.name.isEmpty ? entry.name : (entry.tvgName ?? "Channel \(number)")
            // Ids come from the playlist's own name, so a renamed feed keeps its favorites and Multiview window.
            let baseID = entry.tvgID.map { "id:" + $0.lowercased() } ?? "name:" + playlistName.lowercased()
            let name = feedName(playlistName)
            let count = (idCounts[baseID] ?? 0) + 1
            idCounts[baseID] = count
            channels.append(Channel(
                id: count == 1 ? baseID : "\(baseID)#\(count)",
                number: number,
                name: name,
                group: entry.group ?? otherGroup,
                tvgID: entry.tvgID,
                tvgName: entry.tvgName,
                logoURL: entry.logo.flatMap(URL.init(string:)),
                streamURL: url
            ))
        }
        return channels
    }

    /// M7f L13: a game's broadcast, "Away @ Home-H" / "-A", reads "Away @ Home (Home Feed)" / "(Away Feed)".
    static func feedName(_ name: String) -> String {
        guard name.contains(" @ "), name.count > 2 else { return name }
        let suffix = name.suffix(2)
        let base = String(name.dropLast(2))
        guard !base.hasSuffix(" @"), base.components(separatedBy: " @ ").allSatisfy({ !$0.isEmpty }) else { return name }
        switch suffix {
        case "-H": return base + TeamMatcher.homeFeedSuffix
        case "-A": return base + TeamMatcher.awayFeedSuffix
        default: return name
        }
    }

    /// Distinct groups in first-appearance order.
    static func groups(of channels: [Channel]) -> [String] {
        var seen = Set<String>()
        return channels.compactMap { seen.insert($0.group).inserted ? $0.group : nil }
    }

    /// [allChannelsGroup] + groups when there is more than one group, else the groups.
    static func guideGroups(of channels: [Channel]) -> [String] {
        let groups = groups(of: channels)
        return groups.count > 1 ? [allChannelsGroup] + groups : groups
    }

    /// All channels for allChannelsGroup, else that group's channels, in playlist order.
    static func channels(in group: String, of channels: [Channel]) -> [Channel] {
        group == allChannelsGroup ? channels : channels.filter { $0.group == group }
    }

    private static func isLiveStream(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        let path = url.path.lowercased()
        if path.contains("/movie/") || path.contains("/series/") { return false }
        return !["mp4", "mkv", "avi", "mov"].contains(url.pathExtension.lowercased())
    }
}
