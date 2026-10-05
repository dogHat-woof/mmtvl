import Foundation
import os

/// Persists the home screen items as JSON (D10).
nonisolated struct LaunchItemStore {
    private static let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "LaunchItemStore")
    static let fileName = "launch-items.json"

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "MMTVL", directoryHint: .isDirectory)
    }

    let directory: URL

    var fileURL: URL { directory.appending(path: Self.fileName) }

    init(directory: URL = LaunchItemStore.defaultDirectory) {
        self.directory = directory
    }

    /// Returns the stored items. Seeds the defaults if the file is missing or corrupt
    /// (a corrupt file is kept as `launch-items.json.bak`).
    func load() -> [LaunchItem] {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            Self.logger.info("No launch items file; seeding defaults")
            return seedDefaults()
        }

        do {
            return try JSONDecoder().decode([LaunchItem].self, from: data)
        } catch {
            Self.logger.error("Corrupt launch items file, backing up and seeding defaults: \(error.localizedDescription, privacy: .public)")
            backUpCorruptFile()
            return seedDefaults()
        }
    }

    func save(_ items: [LaunchItem]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(items).write(to: fileURL, options: .atomic)
    }

    private func seedDefaults() -> [LaunchItem] {
        do {
            try save(LaunchItem.defaults)
        } catch {
            Self.logger.error("Failed to write default launch items: \(error.localizedDescription, privacy: .public)")
        }
        return LaunchItem.defaults
    }

    private func backUpCorruptFile() {
        let backupURL = fileURL.appendingPathExtension("bak")
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.moveItem(at: fileURL, to: backupURL)
        } catch {
            Self.logger.error("Failed to back up corrupt launch items: \(error.localizedDescription, privacy: .public)")
        }
    }
}
