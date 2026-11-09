import Foundation

/// `iptv-channels.json` (D10, M6b L5): favorites and hidden channels/groups. Ids not in the playlist are kept and
/// ignored, so a channel that comes back keeps its state. Hand-editable while MMTVL is quit.
nonisolated struct ChannelPreferences: Codable, Equatable, Sendable {
    static let fileName = "iptv-channels.json"

    /// Channel ids, in the order added.
    var favorites: [Channel.ID] = []
    var hiddenChannels: [Channel.ID] = []
    /// Group names as in the playlist (case-sensitive).
    var hiddenGroups: [String] = []
    /// M7f L13: picked team ids (`TeamCatalog`), in the order added.
    var teams: [Team.ID] = []

    init(favorites: [Channel.ID] = [], hiddenChannels: [Channel.ID] = [], hiddenGroups: [String] = [],
         teams: [Team.ID] = []) {
        self.favorites = favorites
        self.hiddenChannels = hiddenChannels
        self.hiddenGroups = hiddenGroups
        self.teams = teams
    }

    /// Per key: missing or undecodable reads as [].
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favorites = (try? container.decodeIfPresent([String].self, forKey: .favorites)) ?? []
        hiddenChannels = (try? container.decodeIfPresent([String].self, forKey: .hiddenChannels)) ?? []
        hiddenGroups = (try? container.decodeIfPresent([String].self, forKey: .hiddenGroups)) ?? []
        teams = (try? container.decodeIfPresent([String].self, forKey: .teams)) ?? []
    }
}

/// What every Live TV list shows after favorites and hiding (M6b L11): the guide's groups and rows, zapping,
/// and the Multiview picker guide.
nonisolated struct ChannelLineup: Equatable, Sendable {
    static let favoritesGroup = "Favorites"
    /// M7f L13: live games and channels of the picked teams, right after Favorites.
    static let teamsGroup = "Teams"

    /// ["Favorites"] when there are visible favorites, ["Teams"] when a picked team is on,
    /// then `ChannelList.guideGroups(of: visibleChannels)`.
    private(set) var groups: [String]
    /// Playlist order, without hidden channels and hidden groups.
    private(set) var visibleChannels: [Channel]
    /// `preferences.favorites` order, visible only.
    private(set) var favorites: [Channel]
    /// M7f L13: `TeamMatcher`'s order, visible only.
    private(set) var teams: [Channel]

    init(channels: [Channel], preferences: ChannelPreferences = ChannelPreferences(), teamChannelIDs: [Channel.ID] = []) {
        let hiddenChannels = Set(preferences.hiddenChannels)
        let hiddenGroups = Set(preferences.hiddenGroups)
        visibleChannels = channels.filter { !hiddenChannels.contains($0.id) && !hiddenGroups.contains($0.group) }
        let byID = Dictionary(visibleChannels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<Channel.ID> = []
        favorites = preferences.favorites.compactMap { id in seen.insert(id).inserted ? byID[id] : nil }
        var seenTeams: Set<Channel.ID> = []
        teams = teamChannelIDs.compactMap { id in seenTeams.insert(id).inserted ? byID[id] : nil }
        groups = (favorites.isEmpty ? [] : [Self.favoritesGroup]) + (teams.isEmpty ? [] : [Self.teamsGroup])
            + ChannelList.guideGroups(of: visibleChannels)
    }

    /// Favorites, All Channels, a group's visible channels; [] for an unknown group.
    func channels(in group: String) -> [Channel] {
        if group == Self.favoritesGroup { return favorites }
        if group == Self.teamsGroup, !teams.isEmpty { return teams }
        guard groups.contains(group) else { return [] }
        return ChannelList.channels(in: group, of: visibleChannels)
    }

    func isVisible(_ id: Channel.ID) -> Bool {
        visibleChannels.contains { $0.id == id }
    }
}
