import Foundation

/// A picture on this Mac that Settings → Tile Art can use (M7 L25).
nonisolated struct PictureFile: Identifiable, Hashable, Sendable {
    var url: URL
    /// "Downloads", "Pictures", "Desktop".
    var folder: String
    var modified: Date

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// Lists pictures directly in a few folders, newest first (L25). No recursion, packages or hidden files.
nonisolated enum PictureFinder {
    static let limit = 40

    /// Downloads, Pictures and Desktop in the user's home.
    static var defaultFolders: [(label: String, url: URL)] {
        [("Downloads", .downloadsDirectory), ("Pictures", .picturesDirectory), ("Desktop", .desktopDirectory)]
    }

    static func isPicture(_ url: URL) -> Bool {
        TileArtStore.extensions.contains(url.pathExtension.lowercased())
    }

    static func find(in folders: [(label: String, url: URL)], limit: Int = limit) -> [PictureFile] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey, .isPackageKey]
        var found: [PictureFile] = []
        for folder in folders {
            let urls = (try? FileManager.default.contentsOfDirectory(at: folder.url, includingPropertiesForKeys: keys,
                                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants])) ?? []
            for url in urls where isPicture(url) {
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true, values.isPackage != true
                else { continue }
                found.append(PictureFile(url: url, folder: folder.label, modified: values.contentModificationDate ?? .distantPast))
            }
        }
        return Array(found.sorted { $0.modified > $1.modified }.prefix(limit))
    }

    /// "Downloads · Oct 6".
    static func detail(_ file: PictureFile) -> String {
        "\(file.folder) · \(file.modified.formatted(.dateTime.month(.abbreviated).day()))"
    }
}
