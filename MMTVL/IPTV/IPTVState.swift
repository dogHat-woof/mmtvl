import Foundation

/// `iptv-state.json` (D10): Live TV bookkeeping. No URLs (L2).
nonisolated struct IPTVState: Codable, Equatable, Sendable {
    static let fileName = "iptv-state.json"
    /// Hand-edited channel → EPG id map (L17), read through `JSONConfigFile<[String: String]>`.
    static let overridesFileName = "epg-overrides.json"

    var lastChannelID: String?
    var lastGroup: String?
    var lastGuideImport: Date?
    /// SHA-256 hex of the guide URL string, so a changed URL forces an import without storing the URL.
    var lastGuideSourceHash: String?

    init(lastChannelID: String? = nil, lastGroup: String? = nil, lastGuideImport: Date? = nil, lastGuideSourceHash: String? = nil) {
        self.lastChannelID = lastChannelID
        self.lastGroup = lastGroup
        self.lastGuideImport = lastGuideImport
        self.lastGuideSourceHash = lastGuideSourceHash
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastChannelID = try container.decodeIfPresent(String.self, forKey: .lastChannelID)
        lastGroup = try container.decodeIfPresent(String.self, forKey: .lastGroup)
        lastGuideImport = try container.decodeIfPresent(Date.self, forKey: .lastGuideImport)
        lastGuideSourceHash = try container.decodeIfPresent(String.self, forKey: .lastGuideSourceHash)
    }
}
