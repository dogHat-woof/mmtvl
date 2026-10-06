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
        return migrator
    }

    /// One transaction: delete everything, insert all.
    func replaceAll(channels: [EPGChannel], programmes: [Programme]) async throws {
        try await writer.write { db in
            try Programme.deleteAll(db)
            try EPGChannel.deleteAll(db)
            for channel in channels {
                try channel.insert(db)
            }
            for programme in programmes {
                var programme = programme
                programme.id = nil
                try programme.insert(db)
            }
        }
    }

    func channels() async throws -> [EPGChannel] {
        try await writer.read { db in try EPGChannel.fetchAll(db) }
    }

    /// Programmes whose channelID is in `ids` and that overlap `interval`, grouped by channelID, sorted by start.
    func programmes(channelIDs ids: Set<String>, overlapping interval: DateInterval) async throws -> [String: [Programme]] {
        guard !ids.isEmpty else { return [:] }
        let programmes = try await writer.read { db in
            try Programme
                .filter(ids.contains(Programme.Columns.channelID))
                .filter(Programme.Columns.start < interval.end && Programme.Columns.stop > interval.start)
                .order(Programme.Columns.start)
                .fetchAll(db)
        }
        return Dictionary(grouping: programmes, by: \.channelID)
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
