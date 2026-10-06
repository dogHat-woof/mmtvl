import Foundation

nonisolated struct LaunchItem: Codable, Identifiable, Hashable, Sendable {
    enum Kind: Codable, Hashable, Sendable {
        case application(bundleID: String)
        case url(URL, browserBundleID: String?)   // nil = default browser
        case defaultBrowser(fullScreen: Bool)     // whatever handles https:// (Brave on the Mac mini)
        case internalDestination(InternalDestination)
        case system(SystemAction)
    }

    enum InternalDestination: String, Codable, Sendable { case youtube, iptv, settings }
    enum SystemAction: String, Codable, Sendable { case exitToDesktop }

    var id: String            // stable slug, e.g. "plex"
    var title: String
    var kind: Kind
    var iconSymbol: String?   // SF Symbol for internal/system items
    var launchFullScreen: Bool?   // nil = the kind's default; Optional so older files decode
    var isHidden: Bool?           // nil/false = shown; Optional so older files decode; stored as nil when shown

    var isVisible: Bool { isHidden != true }

    /// Kinds whose window `AppLauncher` can make full screen (D15).
    var supportsFullScreen: Bool {
        switch kind {
        case .application, .defaultBrowser: true
        case .url, .internalDestination, .system: false
        }
    }

    /// Second line in the Settings tile list.
    var kindDescription: String {
        switch kind {
        case .application: "App"
        case .defaultBrowser: "Default browser"
        case .internalDestination: "Built in"
        case .system: "System"
        case .url(let url, _): url.host() ?? url.absoluteString
        }
    }

    /// Whether `AppLauncher` makes the app's window full screen after launching (D15).
    var wantsFullScreen: Bool {
        if case .defaultBrowser(let fullScreen) = kind { return launchFullScreen ?? fullScreen }
        return launchFullScreen ?? false
    }
}

extension LaunchItem {
    /// Seeded into `launch-items.json` on first run. Bundle IDs still need verifying on the Mac mini.
    nonisolated static let defaults: [LaunchItem] = [
        LaunchItem(id: "plex", title: "Plex", kind: .application(bundleID: "tv.plex.htpc")),
        LaunchItem(id: "youtube", title: "YouTube", kind: .internalDestination(.youtube), iconSymbol: "play.rectangle.fill"),
        LaunchItem(id: "iptv", title: "Live TV", kind: .internalDestination(.iptv), iconSymbol: "tv"),
        LaunchItem(id: "prime", title: "Prime Video", kind: .application(bundleID: "com.amazon.aiv.AIVApp"), launchFullScreen: true),
        LaunchItem(id: "browser", title: "Browser", kind: .defaultBrowser(fullScreen: true)),
        LaunchItem(id: "settings", title: "Settings", kind: .internalDestination(.settings), iconSymbol: "gearshape.fill"),
        LaunchItem(id: "exit", title: "Exit to Desktop", kind: .system(.exitToDesktop), iconSymbol: "rectangle.portrait.and.arrow.right"),
    ]
}
