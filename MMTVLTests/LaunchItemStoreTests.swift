import Foundation
import Testing
@testable import MMTVL

struct LaunchItemStoreTests {
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "LaunchItemStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    private var store: LaunchItemStore { LaunchItemStore(directory: directory) }

    @Test func missingFileSeedsDefaults() throws {
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(store.load() == LaunchItem.defaults)
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
        // The written file decodes back to the defaults.
        #expect(store.load() == LaunchItem.defaults)
    }

    @Test func roundTrip() throws {
        defer { try? FileManager.default.removeItem(at: directory) }

        let items = [
            LaunchItem(id: "a", title: "App", kind: .application(bundleID: "com.example.app")),
            LaunchItem(id: "u", title: "Web", kind: .url(URL(string: "https://example.com")!, browserBundleID: nil)),
            LaunchItem(id: "b", title: "Web in Chrome", kind: .url(URL(string: "https://example.org")!, browserBundleID: "com.google.Chrome")),
            LaunchItem(id: "d", title: "Browser", kind: .defaultBrowser(fullScreen: true)),
            LaunchItem(id: "s", title: "Settings", kind: .internalDestination(.settings), iconSymbol: "gear"),
            LaunchItem(id: "x", title: "Exit", kind: .system(.exitToDesktop), iconSymbol: "xmark"),
        ]
        try store.save(items)
        #expect(store.load() == items)
    }

    @Test func corruptFileFallsBackToDefaultsAndKeepsBackup() throws {
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let garbage = Data("{ not json".utf8)
        try garbage.write(to: store.fileURL)

        #expect(store.load() == LaunchItem.defaults)
        let backupURL = directory.appending(path: "launch-items.json.bak")
        #expect(try Data(contentsOf: backupURL) == garbage)
    }
}
