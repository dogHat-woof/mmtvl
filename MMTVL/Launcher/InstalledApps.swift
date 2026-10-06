import Foundation

nonisolated struct InstalledApp: Hashable, Sendable, Identifiable {
    let bundleID: String
    /// Display name without ".app".
    let name: String
    let url: URL
    var id: String { bundleID }
}

/// Finds app bundles for the Settings "Add Tile" page (L2).
nonisolated enum InstalledApps {
    static var defaultDirectories: [URL] {
        [
            URL(filePath: "/Applications", directoryHint: .isDirectory),
            URL(filePath: "/System/Applications", directoryHint: .isDirectory),
            URL.homeDirectory.appending(path: "Applications", directoryHint: .isDirectory),
        ]
    }

    /// Scans each directory plus one level into non-.app subfolders (Utilities, "Brave Browser Apps.localized").
    /// Skips hidden files, missing directories and bundles without a bundle ID. The first directory wins on
    /// duplicate bundle IDs. Sorted by name.
    static func scan(directories: [URL] = defaultDirectories, excludingBundleIDs: Set<String> = []) -> [InstalledApp] {
        var seen = excludingBundleIDs
        var apps: [InstalledApp] = []
        for directory in directories {
            for entry in contents(of: directory) {
                if isApp(entry) {
                    add(entry, to: &apps, seen: &seen)
                } else if isDirectory(entry) {
                    for child in contents(of: entry) where isApp(child) {
                        add(child, to: &apps, seen: &seen)
                    }
                }
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// `scan` on a detached task; it reads ~100 Info.plists.
    static func scanInBackground(excludingBundleIDs: Set<String>) async -> [InstalledApp] {
        await Task.detached(priority: .userInitiated) {
            scan(excludingBundleIDs: excludingBundleIDs)
        }.value
    }

    private static func contents(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    /// By extension only: app entries can be symlinks.
    private static func isApp(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "app"
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func add(_ url: URL, to apps: inout [InstalledApp], seen: inout Set<String>) {
        guard let bundleID = Bundle(url: url)?.bundleIdentifier, !seen.contains(bundleID) else { return }
        seen.insert(bundleID)
        apps.append(InstalledApp(bundleID: bundleID, name: displayName(of: url), url: url))
    }

    /// `displayName(atPath:)` keeps ".app" outside a GUI context, so strip it.
    private static func displayName(of url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        guard name.lowercased().hasSuffix(".app") else { return name }
        return String(name.dropLast(4))
    }
}
