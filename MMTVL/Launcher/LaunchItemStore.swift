import Foundation

/// Persists the home screen items as JSON (D10).
nonisolated struct LaunchItemStore {
    static let fileName = "launch-items.json"

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "MMTVL", directoryHint: .isDirectory)
    }

    let directory: URL

    var fileURL: URL { directory.appending(path: Self.fileName) }

    private var file: JSONConfigFile<[LaunchItem]> {
        JSONConfigFile(url: fileURL, defaultValue: LaunchItem.defaults)
    }

    init(directory: URL = LaunchItemStore.defaultDirectory) {
        self.directory = directory
    }

    /// Returns the stored items. Seeds the defaults if the file is missing or corrupt
    /// (a corrupt file is kept as `launch-items.json.bak`).
    func load() -> [LaunchItem] {
        file.load()
    }

    func save(_ items: [LaunchItem]) throws {
        try file.save(items)
    }
}
