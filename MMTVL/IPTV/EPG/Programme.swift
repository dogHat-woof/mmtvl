import Foundation
import GRDB

/// One guide programme (D8). With default MainActor isolation, GRDB records must be `nonisolated` with every
/// conformance on the declaration (GRDB #1823).
nonisolated struct Programme: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "programme"

    var id: Int64?
    /// EPG channel id, lowercased.
    var channelID: String
    var start: Date
    var stop: Date
    var title: String
    var subtitle: String?
    /// <desc>
    var summary: String?
    /// First <category>.
    var category: String?
    /// onscreen text, else xmltv_ns as "S2 E1".
    var episode: String?
    /// GuideSource.id. Last, with a default, so XMLTVParser's memberwise calls still compile.
    var sourceID: String = ""

    enum Columns {
        static let sourceID = Column(CodingKeys.sourceID)
        static let channelID = Column(CodingKeys.channelID)
        static let start = Column(CodingKeys.start)
        static let stop = Column(CodingKeys.stop)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// A guide `<channel>`: its id and display names, kept so a playlist change can re-match without a download (L5).
nonisolated struct EPGChannel: Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "epgChannel"

    /// Lowercased.
    var id: String
    /// display-names in file order (GRDB stores the array as JSON text).
    var names: [String]
    /// GuideSource.id.
    var sourceID: String = ""
}

/// One guide channel in one guide.
nonisolated struct EPGRef: Hashable, Codable, Sendable {
    var sourceID: String
    /// Lowercased EPG channel id.
    var epgID: String
}
