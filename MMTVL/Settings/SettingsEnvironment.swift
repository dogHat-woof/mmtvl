import Foundation

/// Everything the Settings model does with side effects. The app wires the real thing; tests pass fakes.
struct SettingsEnvironment {
    var isKiosk: Bool
    var versionString: String
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
    var useIPTVPlaylistGuide: () -> Void
    var refreshIPTV: () -> Void
    var removeIPTVSource: () -> Void
    var phoneRemoteStatus: () -> PhoneRemoteSettingsStatus
    /// `PhoneRemote.setPairing(_:)`: true while Pair a Phone shows (M5 L3).
    var setPhonePairing: (Bool) -> Void
    var forgetAllPhones: () -> Void
}
