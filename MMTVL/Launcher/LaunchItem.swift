import Foundation

nonisolated struct LaunchItem: Codable, Identifiable, Hashable, Sendable {
    enum Kind: Codable, Hashable, Sendable {
        case application(bundleID: String)
        case url(URL, browserBundleID: String?)   // nil = default browser
        case internalDestination(InternalDestination)
        case system(SystemAction)
    }

    enum InternalDestination: String, Codable, Sendable { case youtube, iptv, settings }
    enum SystemAction: String, Codable, Sendable { case exitToDesktop }

    var id: String            // stable slug, e.g. "plex"
    var title: String
    var kind: Kind
    var iconSymbol: String?   // SF Symbol for internal/system items
}

extension LaunchItem {
    /// Seeded into `launch-items.json` on first run. Bundle IDs still need verifying on the Mac mini.
    nonisolated static let defaults: [LaunchItem] = [
        LaunchItem(id: "plex", title: "Plex", kind: .application(bundleID: "tv.plex.htpc")),
        LaunchItem(id: "youtube", title: "YouTube", kind: .internalDestination(.youtube), iconSymbol: "play.rectangle.fill"),
        LaunchItem(id: "iptv", title: "Live TV", kind: .internalDestination(.iptv), iconSymbol: "tv"),
        LaunchItem(id: "prime", title: "Prime Video", kind: .application(bundleID: "com.amazon.aiv.AIVApp")),
        LaunchItem(id: "browser", title: "Safari", kind: .application(bundleID: "com.apple.Safari")),
        LaunchItem(id: "exit", title: "Exit to Desktop", kind: .system(.exitToDesktop), iconSymbol: "rectangle.portrait.and.arrow.right"),
    ]
}
