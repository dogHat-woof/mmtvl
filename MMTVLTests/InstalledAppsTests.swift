import Foundation
import Testing
@testable import MMTVL

struct InstalledAppsTests {
    private func makeApp(_ path: String, in root: URL, bundleID: String?) throws {
        let contents = root.appending(path: path).appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleName": "x"]
        if let bundleID { plist["CFBundleIdentifier"] = bundleID }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))
    }

    private func withTempDirectories(_ body: (URL, URL) throws -> Void) throws {
        let base = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let first = base.appending(path: "first")
        let second = base.appending(path: "second")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try body(first, second)
    }

    @Test func scansAppsOneLevelDeepSortedAndDeduplicated() throws {
        try withTempDirectories { first, second in
            try makeApp("Zed.app", in: first, bundleID: "test.zed")
            try makeApp("alpha.app", in: first, bundleID: "test.alpha")
            try makeApp("Utilities/Tool.app", in: first, bundleID: "test.tool")
            try makeApp("Deep/Nested/Too.app", in: first, bundleID: "test.too")
            try makeApp("NoID.app", in: first, bundleID: nil)
            try makeApp(".Hidden.app", in: first, bundleID: "test.hidden")
            try Data("hi".utf8).write(to: first.appending(path: "readme.txt"))
            try makeApp("Dup.app", in: second, bundleID: "test.zed")

            let apps = InstalledApps.scan(directories: [first, second])
            #expect(apps.map(\.name) == ["alpha", "Tool", "Zed"])
            #expect(apps.last?.url.lastPathComponent == "Zed.app")
        }
    }

    @Test func excludesBundleIDs() throws {
        try withTempDirectories { first, _ in
            try makeApp("Zed.app", in: first, bundleID: "test.zed")
            try makeApp("alpha.app", in: first, bundleID: "test.alpha")
            let apps = InstalledApps.scan(directories: [first], excludingBundleIDs: ["test.zed"])
            #expect(apps.map(\.bundleID) == ["test.alpha"])
        }
    }

    @Test func missingDirectoryIsEmpty() {
        let missing = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        #expect(InstalledApps.scan(directories: [missing]).isEmpty)
    }
}
