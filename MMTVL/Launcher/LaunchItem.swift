import Foundation

/// M7 L24: how a tile without a custom picture looks.
nonisolated enum TileArtStyle: String, Codable, Sendable, CaseIterable {
    /// Brand gradient + the app's icon (built-ins: their designed gradient).
    case designed
    /// The app icon on a blurred backdrop of itself (L4).
    case icon
}

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
    var requiresPIN: Bool?        // D20: asks for the launcher PIN when one is set; stored as nil when off
    /// M7 L23: a Chromium web app tile's own start page (e.g. Google Meet's calling screen); nil = the app's own.
    var startURL: URL?
    /// M7 L24: "designed" (default when nil or unknown) or "icon". A custom picture in `tile-art/` wins over both.
    var artStyle: String?

    var tileArtStyle: TileArtStyle { artStyle.flatMap(TileArtStyle.init(rawValue:)) ?? .designed }

    var isVisible: Bool { isHidden != true }

    /// The only way into Settings, so it's always on the Home screen: movable, never hidden or removed.
    var isSettingsTile: Bool { kind == .internalDestination(.settings) }

    var isExitToDesktop: Bool { kind == .system(.exitToDesktop) }

    /// Asks for the PIN when one is set (D20, L8): Settings and Exit to Desktop always, others when flagged.
    var isPINProtected: Bool { isSettingsTile || isExitToDesktop || requiresPIN == true }

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
