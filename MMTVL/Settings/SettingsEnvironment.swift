import Foundation

/// Everything the Settings model does with side effects. The app wires the real thing; tests pass fakes.
struct SettingsEnvironment {
    var isKiosk: Bool
    /// M7c L28: shown in Settings → About.
    var version: AppVersion
    /// Apply live + save `settings.json`.
    var applySettings: (AppSettings) -> Void
    /// `AppRouter.setItems` + save `launch-items.json`.
    var applyItems: ([LaunchItem]) -> Void
    var isAccessibilityTrusted: () -> Bool
    var requestAccessibility: () -> Void
    var loginItemStatus: () -> LoginItemStatus
    var openLoginItemsSettings: () -> Void
    var scanInstalledApps: () async -> [InstalledApp]
    var relaunch: () -> Void
    var exitToDesktop: () -> Void
    /// `AppLauncher.title(for:)`.
    var tileTitle: (LaunchItem) -> String
    /// `AppLauncher.isInstalled(_:)`.
    var isInstalled: (LaunchItem) -> Bool
    /// A launcher PIN is stored (D20).
    var hasPIN: () -> Bool
    /// `AppRouter.requestPIN(_:)`.
    var startPINFlow: (PINPurpose) -> Void
    /// `YouTubeController.reload()`.
    var reloadYouTube: () -> Void
    /// `YouTubeController.clearData()`, fire and forget.
    var clearYouTubeData: () -> Void
    var iptvStatus: () -> IPTVSettingsStatus
    /// Reads the clipboard. Returns an error message, or nil on success; on success it starts the save + refresh.
    var pasteIPTVURL: (IPTVURLKind) -> String?
    /// `IPTVLibrary.moveGuideSource(_:by:)`, fire and forget.
    var moveGuideSource: (String, Int) -> Void
    /// `IPTVLibrary.removeGuideSource(_:)`, fire and forget.
    var removeGuideSource: (String) -> Void
    /// `IPTVLibrary.setGroupHidden(_:_:)`.
    var setIPTVGroupHidden: (String, Bool) -> Void
    /// `IPTVLibrary.setChannelHidden(id, false)`.
    var unhideIPTVChannel: (String) -> Void
    /// M7f L13: `IPTVLibrary.setTeamPicked(_:_:)`.
    var setTeamPicked: (Team.ID, Bool) -> Void
    var refreshIPTV: () -> Void
    var removeIPTVSource: () -> Void
    var phoneRemoteStatus: () -> PhoneRemoteSettingsStatus
    /// `PhoneRemote.setPairing(_:)`: true while Pair a Phone shows (M5 L3).
    var setPhonePairing: (Bool) -> Void
    var forgetAllPhones: () -> Void
    /// M7: apply to `InputRouter` + save `key-bindings.json`.
    var applyBindings: (KeyBindings) -> Void
    /// M7 L8: non-nil while learning a button (`InputRouter.captureHandler`); nil stops.
    var setButtonLearning: (((InputBinding.Trigger) -> Void)?) -> Void
    /// M7 L3: the tile's custom picture, e.g. "plex.png"; nil when none.
    var tileArtFileName: (String) -> String?
    /// M7 L15: Settings → Plex.
    var plexStatus: () -> PlexSettingsStatus
    /// True exactly while the Plex link page shows (makes and polls a plex.tv/link code).
    var setPlexLinking: (Bool) -> Void
    var choosePlexServer: (String) -> Void
    var signOutOfPlex: () -> Void
    /// L17: opening the Plex page retries a failed connection.
    var refreshPlex: () -> Void
    /// M7 L23: the tile's Chromium web app identity; nil for other tiles.
    var webAppInfo: (LaunchItem) -> WebAppInfo?
    /// Reads the clipboard as a web address (`ClipboardURL.parse`).
    var pasteURL: () -> Result<URL, ClipboardURL.Problem>
    /// M7 L25: pictures in Downloads, Pictures and Desktop (run off the main actor; may ask for folder access).
    var findPictures: () async -> [PictureFile]
    /// Copies a picture into `tile-art/` for the tile. Returns an error message, or nil.
    var setTilePicture: (String, URL) -> String?
    var removeTilePicture: (String) -> Void
    /// M7b L14: Settings → Casting.
    var castingStatus: () -> CastingSettingsStatus
    /// Runs the AirPlay probe; when done, the app calls `refreshStatus()`.
    var refreshCasting: () -> Void
    var openAirPlaySettings: () -> Void
}
