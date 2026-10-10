import Foundation

/// The app's version and build from Info.plist (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`). M7c L28: every test
/// build gets the next build number (`scripts/test-build.sh`), so the installed build can be told apart.
nonisolated struct AppVersion: Equatable, Sendable {
    var version: String
    var build: String

    static let current = AppVersion(info: Bundle.main.infoDictionary ?? [:])

    init(version: String, build: String) {
        self.version = version
        self.build = build
    }

    init(info: [String: Any]) {
        version = info["CFBundleShortVersionString"] as? String ?? "?"
        build = info["CFBundleVersion"] as? String ?? "?"
    }

    /// "Version 1.1.0 Build 2" (the home screen, under the clock).
    var label: String { "Version \(version) Build \(build)" }
}
