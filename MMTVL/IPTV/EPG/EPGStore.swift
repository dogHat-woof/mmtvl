import Foundation
import GRDB
import os

/// The guide cache (D8): `guide.sqlite` in the D10 directory. Safe to delete; the next import rebuilds it.
nonisolated final class EPGStore: Sendable {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "IPTV")
    private let writer: any DatabaseWriter

    /// Runs migrations.
    init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// DatabasePool at `url`. If opening or migrating fails, deletes the file (it is a cache) and tries once more.
    static func open(at url: URL) throws -> EPGStore {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            return try EPGStore(writer: DatabasePool(path: url.path))
        } catch {
            logger.error("Guide database unusable, recreating it: \(error.localizedDescription, privacy: .public)")
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
            return try EPGStore(writer: DatabasePool(path: url.path))
        }
    }

    /// Tests use this, so tests never import GRDB.
    static func inMemory() throws -> EPGStore {
        try EPGStore(writer: DatabaseQueue())
    }

    static var defaultURL: URL {
        LaunchItemStore.defaultDirectory.appending(path: "guide.sqlite")
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: EPGChannel.databaseTableName) { t in
                t.primaryKey("id", .text)
                t.column("names", .text).notNull()
            }
            try db.create(table: Programme.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("channelID", .text).notNull()
                t.column("start", .datetime).notNull()
                t.column("stop", .datetime).notNull()
                t.column("title", .text).notNull()
                t.column("subtitle", .text)
                t.column("summary", .text)
                t.column("category", .text)
                t.column("episode", .text)
            }
            try db.create(index: "programme_on_channel_start", on: Programme.databaseTableName, columns: ["channelID", "start"])
        }
        // M6b L3: rows per guide. The guide is a cache (D8), so the tables are recreated, not converted.
        migrator.registerMigration("v2") { db in
            try db.drop(table: Programme.databaseTableName)
            try db.drop(table: EPGChannel.databaseTableName)
            try db.create(table: EPGChannel.databaseTableName) { t in
                t.column("sourceID", .text).notNull()
                t.column("id", .text).notNull()
                t.column("names", .text).notNull()
                t.primaryKey(["sourceID", "id"])
            }
            try db.create(table: Programme.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sourceID", .text).notNull()
                t.column("channelID", .text).notNull()
                t.column("start", .datetime).notNull()
                t.column("stop", .datetime).notNull()
                t.column("title", .text).notNull()
                t.column("subtitle", .text)
                t.column("summary", .text)
                t.column("category", .text)
                t.column("episode", .text)
            }
            try db.create(index: "programme_on_source_channel_start", on: Programme.databaseTableName,
                          columns: ["sourceID", "channelID", "start"])
        }
        return migrator
    }

    /// One transaction: delete this guide's rows, insert all with `sourceID` set.
    func replaceSource(_ sourceID: String, channels: [EPGChannel], programmes: [Programme]) async throws {
        try await writer.write { db in
            try Programme.filter(Programme.Columns.sourceID == sourceID).deleteAll(db)
            try EPGChannel.filter(Column("sourceID") == sourceID).deleteAll(db)
            for channel in channels {
                var channel = channel
                channel.sourceID = sourceID
                try channel.insert(db)
            }
            for programme in programmes {
                var programme = programme
                programme.id = nil
                programme.sourceID = sourceID
                try programme.insert(db)
            }
        }
    }

    /// Deletes the rows of every guide not in `ids`.
    func removeSources(keeping ids: Set<String>) async throws {
        try await writer.write { db in
            try Programme.filter(!ids.contains(Programme.Columns.sourceID)).deleteAll(db)
            try EPGChannel.filter(!ids.contains(Column("sourceID"))).deleteAll(db)
        }
    }

    /// Every stored guide channel, by GuideSource.id.
    func channelsBySource() async throws -> [String: [EPGChannel]] {
        let channels = try await writer.read { db in try EPGChannel.fetchAll(db) }
        return Dictionary(grouping: channels, by: \.sourceID)
    }

    /// Programmes of exactly these guide channels that overlap `interval`, sorted by start.
    func programmes(refs: Set<EPGRef>, overlapping interval: DateInterval) async throws -> [EPGRef: [Programme]] {
        guard !refs.isEmpty else { return [:] }
        let sourceIDs = Set(refs.map(\.sourceID))
        let channelIDs = Set(refs.map(\.epgID))
        let programmes = try await writer.read { db in
            try Programme
                .filter(sourceIDs.contains(Programme.Columns.sourceID))
                .filter(channelIDs.contains(Programme.Columns.channelID))
                .filter(Programme.Columns.start < interval.end && Programme.Columns.stop > interval.start)
                .order(Programme.Columns.start)
                .fetchAll(db)
        }
        return Dictionary(grouping: programmes) { EPGRef(sourceID: $0.sourceID, epgID: $0.channelID) }
            .filter { refs.contains($0.key) }
    }

    /// Programme rows per GuideSource.id.
    func programmeCounts() async throws -> [String: Int] {
        try await writer.read { db in
            var counts: [String: Int] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT sourceID, COUNT(*) AS n FROM programme GROUP BY sourceID") {
                counts[row["sourceID"]] = row["n"]
            }
            return counts
        }
    }

    func programmeCount(for ref: EPGRef) async throws -> Int {
        try await writer.read { db in
            try Programme
                .filter(Programme.Columns.sourceID == ref.sourceID && Programme.Columns.channelID == ref.epgID)
                .fetchCount(db)
        }
    }

    func programmeCount() async throws -> Int {
        try await writer.read { db in try Programme.fetchCount(db) }
    }

    func removeAll() async throws {
        try await writer.write { db in
            try Programme.deleteAll(db)
            try EPGChannel.deleteAll(db)
        }
    }
}
