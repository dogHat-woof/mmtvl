import Foundation
import Testing
@testable import MMTVL

/// Pictures for Settings → Tile Art (M7 L25).
struct PictureFinderTests {
    @Test func newestFirstPicturesOnlyNoRecursionWithALimit() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "PictureFinder-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let downloads = root.appending(path: "Downloads"), desktop = root.appending(path: "Desktop")
        for folder in [downloads, desktop, downloads.appending(path: "nested"), downloads.appending(path: "Photos.photoslibrary")] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        func write(_ url: URL, age: TimeInterval) throws {
            try Data("x".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000 - age)],
                                                  ofItemAtPath: url.path())
        }
        try write(downloads.appending(path: "old.jpg"), age: 300)
        try write(downloads.appending(path: "new.PNG"), age: 10)
        try write(desktop.appending(path: "mid.heic"), age: 100)
        try write(downloads.appending(path: "notes.txt"), age: 1)
        try write(downloads.appending(path: ".hidden.png"), age: 1)
        try write(downloads.appending(path: "nested/deep.png"), age: 1)
        try write(downloads.appending(path: "Photos.photoslibrary/inside.png"), age: 1)

        let folders = [(label: "Downloads", url: downloads), (label: "Desktop", url: desktop)]
        let found = PictureFinder.find(in: folders)
        #expect(found.map(\.name) == ["new.PNG", "mid.heic", "old.jpg"])
        #expect(found.map(\.folder) == ["Downloads", "Desktop", "Downloads"])
        #expect(PictureFinder.find(in: folders, limit: 2).map(\.name) == ["new.PNG", "mid.heic"])
        #expect(PictureFinder.find(in: [(label: "Gone", url: root.appending(path: "missing"))]).isEmpty)
    }

    @Test func detailNamesTheFolderAndDay() {
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour) = (2026, 10, 6, 12)
        let date = Calendar.current.date(from: components)!
        let file = PictureFile(url: URL(fileURLWithPath: "/tmp/a.png"), folder: "Downloads", modified: date)
        #expect(PictureFinder.detail(file) == "Downloads · Oct 6")
    }
}
