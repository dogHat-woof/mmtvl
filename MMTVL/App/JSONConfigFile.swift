import Foundation
import os

nonisolated private let logger = Logger(subsystem: "dev.mmtvl.launcher", category: "Config")

/// One JSON config file in the D10 directory, with a default value.
nonisolated struct JSONConfigFile<Value: Codable & Sendable>: Sendable {
    let url: URL
    let defaultValue: Value

    /// Missing → writes and returns `defaultValue`. Corrupt → moves the file to "<name>.bak",
    /// writes and returns `defaultValue`. Creates the directory if needed.
    func load() -> Value {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            logger.info("No \(url.lastPathComponent, privacy: .public); seeding defaults")
            return seedDefault()
        }

        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            logger.error("Corrupt \(url.lastPathComponent, privacy: .public), backing up and seeding defaults: \(error.localizedDescription, privacy: .public)")
            backUpCorruptFile()
            return seedDefault()
        }
    }

    /// Pretty-printed, sorted keys, atomic write. Creates the directory if needed.
    func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func seedDefault() -> Value {
        do {
            try save(defaultValue)
        } catch {
            logger.error("Failed to write default \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        return defaultValue
    }

    /// "<name>.bak", where a corrupt file is moved and `copyToBackup()` copies.
    var backupURL: URL { url.appendingPathExtension("bak") }

    /// M7h: copies the file as it is now to "<name>.bak" (replacing an older backup); the file stays.
    func copyToBackup() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try fileManager.copyItem(at: url, to: backupURL)
    }

    private func backUpCorruptFile() {
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.moveItem(at: url, to: backupURL)
        } catch {
            logger.error("Failed to back up corrupt \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
