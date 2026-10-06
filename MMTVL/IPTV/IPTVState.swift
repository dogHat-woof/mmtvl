import Foundation

/// `iptv-state.json` (D10): Live TV bookkeeping. No URLs (L2).
nonisolated struct IPTVState: Codable, Equatable, Sendable {
    static let fileName = "iptv-state.json"
    /// Hand-edited channel → EPG id map (L17), read through `JSONConfigFile<[String: String]>`.
    static let overridesFileName = "epg-overrides.json"

    var lastChannelID: String?
    var lastGroup: String?
    /// GuideSource.id (SHA-256 hex of the guide URL, so no URL is stored) → last successful import (M6b L4).
    var guideImports: [String: Date]
    /// Multiview's windows and layout (M6 L13).
    var multiview: MultiviewSnapshot?
    /// M7 L13: channels watched, most recent first, at most `maxRecentChannels` (the top shelf without favorites).
    var recentChannelIDs: [String]

    static let maxRecentChannels = 10

    init(lastChannelID: String? = nil, lastGroup: String? = nil, guideImports: [String: Date] = [:],
         multiview: MultiviewSnapshot? = nil, recentChannelIDs: [String] = []) {
        self.lastChannelID = lastChannelID
        self.lastGroup = lastGroup
        self.guideImports = guideImports
        self.multiview = multiview
        self.recentChannelIDs = recentChannelIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastChannelID = try container.decodeIfPresent(String.self, forKey: .lastChannelID)
        lastGroup = try container.decodeIfPresent(String.self, forKey: .lastGroup)
        // M4's lastGuideImport/lastGuideSourceHash are ignored and dropped on the next save.
        guideImports = (try? container.decodeIfPresent([String: Date].self, forKey: .guideImports)) ?? [:]
        // A snapshot that can't be decoded (say, an unknown layout) reads as nil; the rest of the state is kept.
        multiview = (try? container.decodeIfPresent(MultiviewSnapshot.self, forKey: .multiview)) ?? nil
        recentChannelIDs = (try? container.decodeIfPresent([String].self, forKey: .recentChannelIDs)) ?? []
    }
}
