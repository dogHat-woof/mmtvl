import Foundation
@testable import MMTVL

/// Records what the Settings model asks the app to do, and serves fake status.
final class SettingsRecorder {
    var appliedSettings: [AppSettings] = []
    var appliedItems: [[LaunchItem]] = []
    var accessibilityRequests = 0
    var loginItemsOpened = 0
    var relaunches = 0
    var exits = 0
    var trusted: Bool
    var loginStatus: LoginItemStatus
    var installedApps: [InstalledApp] = []
    var hasPIN = false
    var pinFlows: [PINPurpose] = []
    var youtubeReloads = 0
    var youtubeClears = 0
    var iptv = IPTVSettingsStatus()
    var pasteResult: String? = nil
    var pastes: [IPTVURLKind] = []
    var iptvRefreshes = 0
    var iptvRemovals = 0
    var playlistGuideUses = 0
    var phoneRemote = PhoneRemoteSettingsStatus()
    var pairingCalls: [Bool] = []
    var forgets = 0

    init(trusted: Bool, loginStatus: LoginItemStatus) {
        self.trusted = trusted
        self.loginStatus = loginStatus
    }
}

func makeSettingsModel(
    kiosk: Bool = true,
    trusted: Bool = true,
    loginStatus: LoginItemStatus = .notRegistered,
    settings: AppSettings = AppSettings(),
    items: [LaunchItem] = LaunchItem.defaults,
    hasPIN: Bool = false
) -> (SettingsModel, SettingsRecorder) {
    let recorder = SettingsRecorder(trusted: trusted, loginStatus: loginStatus)
    recorder.hasPIN = hasPIN
    let environment = SettingsEnvironment(
        isKiosk: kiosk,
        versionString: "1.0",
        applySettings: { recorder.appliedSettings.append($0) },
        applyItems: { recorder.appliedItems.append($0) },
        isAccessibilityTrusted: { recorder.trusted },
        requestAccessibility: { recorder.accessibilityRequests += 1 },
        loginItemStatus: { recorder.loginStatus },
        openLoginItemsSettings: { recorder.loginItemsOpened += 1 },
        scanInstalledApps: { recorder.installedApps },
        relaunch: { recorder.relaunches += 1 },
        exitToDesktop: { recorder.exits += 1 },
        tileTitle: { $0.title },
        isInstalled: { _ in true },
        hasPIN: { recorder.hasPIN },
        startPINFlow: { recorder.pinFlows.append($0) },
        reloadYouTube: { recorder.youtubeReloads += 1 },
        clearYouTubeData: { recorder.youtubeClears += 1 },
        iptvStatus: { recorder.iptv },
        pasteIPTVURL: { kind in
            recorder.pastes.append(kind)
            return recorder.pasteResult
        },
        useIPTVPlaylistGuide: { recorder.playlistGuideUses += 1 },
        refreshIPTV: { recorder.iptvRefreshes += 1 },
        removeIPTVSource: { recorder.iptvRemovals += 1 },
        phoneRemoteStatus: { recorder.phoneRemote },
        setPhonePairing: { recorder.pairingCalls.append($0) },
        forgetAllPhones: { recorder.forgets += 1 }
    )
    return (SettingsModel(settings: settings, items: items, environment: environment), recorder)
}

extension SettingsModel {
    /// Sends commands like a remote would.
    func press(_ commands: RemoteCommand...) {
        for command in commands { _ = handle(command) }
    }
}
