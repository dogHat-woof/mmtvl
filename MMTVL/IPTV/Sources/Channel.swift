import Foundation

/// Where a channel comes from (M7j): the playlist, or an HDHomeRun tuner's lineup. Its descriptions and mirror never
/// show the DeviceID (L15).
nonisolated enum ChannelSource: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    case playlist
    /// `deviceID`: the tuner's DeviceID, memory only, never logged or shown.
    case antenna(deviceID: String)

    var description: String {
        switch self {
        case .playlist: "playlist"
        case .antenna: "antenna"
        }
    }

    var debugDescription: String { description }

    var customMirror: Mirror { Mirror(self, children: [:], displayStyle: .enum) }
}

/// A live channel from the playlist, or (M7j) an antenna tuner. Kept in memory only (D23).
nonisolated struct Channel: Identifiable, Hashable, Sendable {
    /// See `ChannelList.make`; antenna channels: `antenna:<GuideNumber>` (M7j L1).
    let id: String
    /// 1-based position among kept channels; antenna channels continue after the playlist's (M7j L2).
    let number: Int
    let name: String
    /// entry.group ?? "Other"; antenna channels: `AntennaLineup.group`.
    let group: String
    let tvgID: String?
    let tvgName: String?
    let logoURL: URL?
    let streamURL: URL
    /// M7j: `var` with a default, so the memberwise init keeps working without it.
    var source: ChannelSource = .playlist
    /// Antenna channels: the tuner's GuideNumber ("5.1").
    var guideNumber: String? = nil

    /// "5.1" for antenna channels, else "\(number)".
    var displayNumber: String { guideNumber ?? "\(number)" }

    /// Antenna streams skip the resolver and relay and are never prefetched (M7j L6, L7).
    var isDirectStream: Bool {
        if case .antenna = source { true } else { false }
    }

    /// The epg-overrides.json key Match Guide writes: the id for antenna channels (M7j L12), else the name.
    var overrideKey: String { isDirectStream ? id : name }
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

    /// M7j L3: Antenna (when a channel's group is "Antenna"), then [allChannelsGroup] when that and the other
    /// groups make more than one group, then the other groups in first-appearance order.
    static func guideGroups(of channels: [Channel]) -> [String] {
        let groups = groups(of: channels)
        let hasAntenna = groups.contains(AntennaLineup.group)
        let others = groups.filter { $0 != AntennaLineup.group }
        let count = others.count + (hasAntenna ? 1 : 0)
        return (hasAntenna ? [AntennaLineup.group] : []) + (count > 1 ? [allChannelsGroup] : []) + others
    }

    /// All channels for allChannelsGroup (the playlist's, then the antenna's, M7j L3), else that group's channels,
    /// in order. M7j L3: in "Antenna", the antenna channels come first (GuideNumber order), then a playlist group
    /// of that name.
    static func channels(in group: String, of channels: [Channel]) -> [Channel] {
        guard group != allChannelsGroup else { return channels }
        let inGroup = channels.filter { $0.group == group }
        guard group == AntennaLineup.group else { return inGroup }
        return inGroup.filter(\.isDirectStream) + inGroup.filter { !$0.isDirectStream }
    }

    private static func isLiveStream(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        let path = url.path.lowercased()
        if path.contains("/movie/") || path.contains("/series/") { return false }
        return !["mp4", "mkv", "avi", "mov"].contains(url.pathExtension.lowercased())
    }
}
