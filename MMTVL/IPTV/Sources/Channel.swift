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
    /// name: entry.name, else tvgName, else "Channel \(number)".
    static func make(from playlist: M3UPlaylist) -> [Channel] {
        var channels: [Channel] = []
        var idCounts: [String: Int] = [:]
        for entry in playlist.entries {
            guard let url = URL(string: entry.url), isLiveStream(url) else { continue }
            let number = channels.count + 1
            let name = !entry.name.isEmpty ? entry.name : (entry.tvgName ?? "Channel \(number)")
            let baseID = entry.tvgID.map { "id:" + $0.lowercased() } ?? "name:" + name.lowercased()
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
