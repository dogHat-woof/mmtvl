import Foundation

nonisolated enum SettingsPage: Hashable, Sendable {
    case root, homeScreen, tile(id: String), addTile, confirmRestoreDefaults, confirmClearYouTube
    case liveTV, confirmRemoveIPTV
}

/// Which Live TV address a paste row fills (M4 L2).
nonisolated enum IPTVURLKind: Hashable, Sendable {
    case playlist, guide
}

/// What the Live TV rows show. Built by the app from `IPTVLibrary`; hosts only, never full URLs (L2).
nonisolated struct IPTVSettingsStatus: Equatable, Sendable {
    var hasPlaylist = false
    /// url.host()
    var playlistHost: String?
    var channelCount = 0
    /// "Loading…", "Updated 10:42 PM", "Failed: Server error (HTTP 403)"
    var playlistLine: String = ""
    var guideKind: GuideKind = .none
    /// "1,234 programmes · Updated 10:43 PM", "Loading…", "Failed: …", "No guide"
    var guideLine: String = ""

    enum GuideKind: Equatable, Sendable { case none, playlist(String), custom(String) }
}

/// The `settings.json` toggles.
nonisolated enum SettingKey: String, CaseIterable, Sendable {
    case globalInputEnabled, controllersEnabled, cursorAutoHide, launchAtLogin

    var keyPath: WritableKeyPath<AppSettings, Bool> {
        switch self {
        case .globalInputEnabled: \.globalInputEnabled
        case .controllersEnabled: \.controllersEnabled
        case .cursorAutoHide: \.cursorAutoHide
        case .launchAtLogin: \.launchAtLogin
        }
    }
}

/// What Select does on a row (L4). Data, not closures, so pages are Equatable and testable.
nonisolated enum SettingsAction: Hashable, Sendable {
    case toggle(SettingKey)
    case requestAccessibility
    case openLoginItemsSettings
    case push(SettingsPage)
    case relaunch
    case exitToDesktop
    case toggleTileVisible(id: String)
    case toggleTileFullScreen(id: String)
    case startMove(id: String)
    case removeTile(id: String)
    case addDefaultTile(id: String)
    case addApp(InstalledApp)
    case restoreDefaults
    case pop
    /// D20: the router shows the PIN screen and returns to this page.
    case startPIN(PINPurpose)
    case toggleTileRequiresPIN(id: String)
    case reloadYouTube
    case clearYouTubeData
    case pasteIPTVURL(IPTVURLKind)
    case useIPTVPlaylistGuide
    case refreshIPTV
    case removeIPTVSource
}

nonisolated enum RowImage: Hashable, Sendable {
    /// SF Symbol.
    case symbol(String)
    /// App icon via `AppLauncher.icon(for:)`, else the item's `iconSymbol`, else "app.dashed".
    case item(LaunchItem)
    /// `AppLauncher.icon(forApplicationAt:)`.
    case app(URL)
}

nonisolated struct SettingsRow: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    /// Right-aligned: "On", "Off", "Allowed", "Hidden"…
    var value: String? = nil
    /// Second line, smaller.
    var detail: String? = nil
    var image: RowImage? = nil
    var showsDisclosure = false
    /// Hidden tiles.
    var isDimmed = false
    /// The tile being moved.
    var isLifted = false
    /// D19 "Relaunch needed" badge; no M2b row sets it (L3).
    var needsRelaunch = false
    /// nil = info row: shown, never focused.
    var action: SettingsAction? = nil
}

nonisolated struct SettingsSection: Identifiable, Hashable, Sendable {
    var id: String
    var title: String? = nil
    var rows: [SettingsRow]
    var footer: String? = nil
}

/// Vertical list focus by row id; ids stay stable when rows appear, disappear or move.
nonisolated enum ListFocus {
    /// `current` if it's in `ids`, else the first id, else nil.
    static func resolve(ids: [String], current: String?) -> String? {
        if let current, ids.contains(current) { return current }
        return ids.first
    }

    /// The id `step` positions from the resolved current one, clamped to the ends.
    static func move(ids: [String], current: String?, by step: Int) -> String? {
        guard let resolved = resolve(ids: ids, current: current),
              let index = ids.firstIndex(of: resolved)
        else { return nil }
        return ids[min(max(index + step, 0), ids.count - 1)]
    }
}
