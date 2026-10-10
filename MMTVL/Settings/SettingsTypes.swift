import Foundation

nonisolated enum SettingsPage: Hashable, Sendable {
    case root, homeScreen, tile(id: String), addTile, confirmRestoreDefaults, confirmClearYouTube
    case liveTV, confirmRemoveIPTV, guideSource(id: String), iptvGroups, iptvHiddenChannels
    case phoneRemote, pairPhone, confirmForgetPhones
    /// M7: Settings → Remote Buttons (D27).
    case remoteButtons, remoteCommand(RemoteCommand), remoteBinding(RemoteCommand, InputBinding.Trigger)
    case learnButton(RemoteCommand), confirmLearn(RemoteCommand, InputBinding.Trigger), confirmRestoreButtons
    /// M7: Settings → Plex (D28, L15).
    case plex, plexLink, plexServers, confirmPlexSignOut
    /// M7 L25: Settings → a tile → Tile Art.
    case tileArt(id: String)
    /// M7b L14: Settings → Casting.
    case casting
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
    /// The guides in use, in priority order (M6b L1).
    var guideSources: [GuideSourceStatus] = []
    /// Pasted guides; the add row disappears at `IPTVLibrary.maxGuideSources`.
    var customGuideCount = 0
    /// Playlist channels with guide data.
    var matchedChannelCount = 0
    /// Playlist groups, in playlist order (M6b L5).
    var groups: [GroupStatus] = []
    /// Hidden playlist channels, in playlist order.
    var hiddenChannels: [HiddenChannelStatus] = []

    struct GuideSourceStatus: Identifiable, Equatable, Sendable {
        /// GuideSource.id.
        var id: String
        /// GuideSource.label: host, plus the file name when it looks like a guide file (M6b L2).
        var label: String
        /// "1,234 programmes · 40 channels · Updated 10:43 PM", "Loading…", "Failed: …", "Not loaded yet"
        var line: String
        var isFromPlaylist: Bool
    }

    struct GroupStatus: Identifiable, Equatable, Sendable {
        var name: String
        var channelCount: Int
        var isHidden: Bool
        var id: String { name }
    }

    struct HiddenChannelStatus: Identifiable, Equatable, Sendable {
        /// Channel.ID.
        var id: String
        var number: Int
        var name: String
        var group: String
    }
}

/// What the Phone Remote rows show (M5). Built by the app from `RemoteServer` and `PhoneRemote`.
nonisolated struct PhoneRemoteSettingsStatus: Equatable, Sendable {
    var isRunning = false
    /// "Port 8765 is in use", "No network connection", "Starting…"; nil when fine.
    var problem: String?
    /// "http://192.168.1.20:8765"; nil without a LAN address.
    var address: String?
    /// While Pair a Phone shows.
    var pairingCode: String?
    /// address + "/#pair=" + code.
    var pairingURL: String?
    var lastPairedName: String?
    var pairedCount = 0
    var connectedCount = 0
    /// SyntheticInput.canPost.
    var canControlOtherApps = false
}

/// What Settings → Plex shows (M7 L15). Built by the app from `PlexAccount`; never tokens.
nonisolated struct PlexSettingsStatus: Equatable, Sendable {
    struct Server: Identifiable, Equatable, Sendable {
        /// The server's machine identifier.
        var id: String
        var name: String
        /// "Yours", "Shared with you".
        var detail: String
    }

    var isSignedIn = false
    /// While the link page shows.
    var linkCode: String?
    /// `PlexAPI.linkURL(code:)` for the QR code.
    var linkURL: String?
    /// The chosen server.
    var serverName: String?
    /// The account's servers (after sign-in).
    var servers: [Server] = []
    /// "Connected · 7 items", "Can't reach the server", "Sign in again"…
    var statusLine = ""
    var itemCount = 0
    /// Signed in, but the account has no server.
    var hasNoServer = false
    /// Signed in with several servers and none chosen yet.
    var needsServerChoice = false
}

/// What Settings → Casting shows (M7b L14). Built by the app from `CastReceiver`, the AirPlay probe and
/// the installed/running apps.
nonisolated struct CastingSettingsStatus: Equatable, Sendable {
    enum YouTube: Equatable, Sendable { case off, starting, ready, failed(String) }
    enum PlexHTPC: Equatable, Sendable { case notInstalled, notRunning, running }
    enum Reflector: Equatable, Sendable { case notInstalled, notRunning, ready, mirroring }

    var youtube: YouTube = .off
    var airPlay: AirPlayReceiverState = .unknown
    var reflector: Reflector = .notInstalled
    var plexHTPC: PlexHTPC = .notInstalled
}

/// The `settings.json` toggles.
nonisolated enum SettingKey: String, CaseIterable, Sendable {
    case globalInputEnabled, controllersEnabled, cursorAutoHide, launchAtLogin, phoneRemoteEnabled
    /// M7 L22: its row shows "Up the List" / "Higher Number" instead of On/Off.
    case channelUpMovesUpList
    /// M7b L5.
    case youtubeCastEnabled
    /// M7b L18.
    case reflectorAutoStart
    /// M7c L6.
    case kioskLock
    /// M7c L15.
    case homeLivePreview
    /// M7c L28.
    case showVersionOnHome

    var keyPath: WritableKeyPath<AppSettings, Bool> {
        switch self {
        case .globalInputEnabled: \.globalInputEnabled
        case .controllersEnabled: \.controllersEnabled
        case .cursorAutoHide: \.cursorAutoHide
        case .launchAtLogin: \.launchAtLogin
        case .phoneRemoteEnabled: \.phoneRemoteEnabled
        case .channelUpMovesUpList: \.channelUpMovesUpList
        case .youtubeCastEnabled: \.youtubeCastEnabled
        case .reflectorAutoStart: \.reflectorAutoStart
        case .kioskLock: \.kioskLock
        case .homeLivePreview: \.homeLivePreview
        case .showVersionOnHome: \.showVersionOnHome
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
    case moveGuideSource(id: String, by: Int)
    case removeGuideSource(id: String)
    case toggleIPTVGroupHidden(String)
    case unhideIPTVChannel(id: String)
    case refreshIPTV
    case removeIPTVSource
    case forgetAllPhones
    /// M7 L8: pushes `.learnButton`, or replaces `.confirmLearn` with it (Try Again).
    case startLearning(RemoteCommand)
    case useLearned(RemoteCommand, InputBinding.Trigger)
    case removeBinding(InputBinding.Trigger)
    case toggleBindingGlobal(InputBinding.Trigger)
    case restoreDefaultButtons
    case choosePlexServer(id: String)
    case signOutOfPlex
    /// M7 L23: a web app tile's start page from the clipboard, or back to the app's own.
    case pasteTileStartURL(id: String)
    case clearTileStartURL(id: String)
    /// M7 L25.
    case setTileArtStyle(id: String, TileArtStyle)
    case useTileArtPicture(id: String, URL)
    case removeTileArtPicture(id: String)
    /// M7b L14: System Settings → General → AirDrop & Handoff.
    case openAirPlaySettings
    /// M7c L32: the tile MMTVL opens on (`settings.json` `homeStartTile`).
    case setStartTile(id: String)
}

nonisolated enum RowImage: Hashable, Sendable {
    /// SF Symbol.
    case symbol(String)
    /// App icon via `AppLauncher.icon(for:)`, else the item's `iconSymbol`, else "app.dashed".
    case item(LaunchItem)
    /// `AppLauncher.icon(forApplicationAt:)`.
    case app(URL)
    /// A QR code for the string (M5 pairing), drawn at `Theme.settingsQRCodeSize`.
    case qrCode(String)
    /// M7 L25: a tile's art as it would look with this choice, at preview size.
    case tileArt(itemID: String, TileArtChoice)
    /// M7 L25: a small thumbnail of a picture file.
    case picture(URL)
}

/// What Settings → Tile Art previews (M7 L25).
nonisolated enum TileArtChoice: Hashable, Sendable {
    /// What the tile shows now.
    case current
    case style(TileArtStyle)
    case file(URL)
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
