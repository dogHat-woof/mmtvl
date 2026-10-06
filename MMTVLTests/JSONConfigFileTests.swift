import Foundation
import Testing
@testable import MMTVL

struct JSONConfigFileTests {
    nonisolated private struct Sample: Codable, Equatable, Sendable {
        var name: String
        var count: Int
    }

    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "JSONConfigFileTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    private var file: JSONConfigFile<Sample> {
        JSONConfigFile(url: directory.appending(path: "sample.json"), defaultValue: Sample(name: "default", count: 1))
    }

    @Test func missingFileWritesDefault() throws {
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(file.load() == Sample(name: "default", count: 1))
        #expect(FileManager.default.fileExists(atPath: file.url.path))
        #expect(file.load() == Sample(name: "default", count: 1))
    }

    @Test func roundTrip() throws {
        defer { try? FileManager.default.removeItem(at: directory) }

        let value = Sample(name: "custom", count: 42)
        try file.save(value)
        #expect(file.load() == value)
    }

    @Test func corruptFileFallsBackToDefaultAndKeepsBackup() throws {
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let garbage = Data("{ not json".utf8)
        try garbage.write(to: file.url)

        #expect(file.load() == Sample(name: "default", count: 1))
        let backupURL = directory.appending(path: "sample.json.bak")
        #expect(try Data(contentsOf: backupURL) == garbage)
    }
}
