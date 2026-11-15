import Foundation
import Testing
@testable import MMTVL

struct GunzipTests {
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "GunzipTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    private func write(_ text: String, name: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func gzip(_ url: URL) throws -> URL {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/gzip")
        process.arguments = ["-k", "-f", url.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return url.appendingPathExtension("gz")
    }

    @Test func roundTrip() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        // Bigger than one 256 KB chunk, compressible and not.
        let text = (0..<40_000).map { "line \($0) \(UUID().uuidString)\n" }.joined()
        let source = try write(text, name: "a.txt")
        let compressed = try gzip(source)
        #expect(try Gunzip.isGzip(compressed))

        let output = directory.appending(path: "a.out")
        try Gunzip.decompress(compressed, to: output)
        #expect(try String(contentsOf: output, encoding: .utf8) == text)
    }

    @Test func concatenatedMembers() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = try gzip(try write("first part\n", name: "a.txt"))
        let b = try gzip(try write("second part\n", name: "b.txt"))
        let joined = directory.appending(path: "joined.gz")
        try (try Data(contentsOf: a) + Data(contentsOf: b)).write(to: joined)

        let output = directory.appending(path: "joined.out")
        try Gunzip.decompress(joined, to: output)
        #expect(try String(contentsOf: output, encoding: .utf8) == "first part\nsecond part\n")
    }

    @Test func plainFileIsNotGzip() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(try Gunzip.isGzip(try write("<tv></tv>", name: "plain.xml")) == false)
    }

    /// M7j step 8 (security L3): output past the limit stops the inflate; within it, it's whole.
    @Test func outputOverTheLimitIsRefused() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = String(repeating: "abcdefgh", count: 200_000)    // 1.6 MB, compresses to a few KB
        let compressed = try gzip(try write(text, name: "big.txt"))
        let output = directory.appending(path: "big.out")
        #expect(throws: Gunzip.GunzipError.tooLarge) {
            try Gunzip.decompress(compressed, to: output, maxOutputBytes: 1_000_000)
        }
        try Gunzip.decompress(compressed, to: output, maxOutputBytes: 1_600_000)
        #expect(try Data(contentsOf: output).count == 1_600_000)
    }
}
