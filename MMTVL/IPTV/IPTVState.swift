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
    /// Multiview's windows and layout (M6 L13).
    var multiview: MultiviewSnapshot?

    init(lastChannelID: String? = nil, lastGroup: String? = nil, lastGuideImport: Date? = nil, lastGuideSourceHash: String? = nil,
         multiview: MultiviewSnapshot? = nil) {
        self.lastChannelID = lastChannelID
        self.lastGroup = lastGroup
        self.lastGuideImport = lastGuideImport
        self.lastGuideSourceHash = lastGuideSourceHash
        self.multiview = multiview
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastChannelID = try container.decodeIfPresent(String.self, forKey: .lastChannelID)
        lastGroup = try container.decodeIfPresent(String.self, forKey: .lastGroup)
        lastGuideImport = try container.decodeIfPresent(Date.self, forKey: .lastGuideImport)
        lastGuideSourceHash = try container.decodeIfPresent(String.self, forKey: .lastGuideSourceHash)
        // A snapshot that can't be decoded (say, an unknown layout) reads as nil; the rest of the state is kept.
        multiview = (try? container.decodeIfPresent(MultiviewSnapshot.self, forKey: .multiview)) ?? nil
    }
}
