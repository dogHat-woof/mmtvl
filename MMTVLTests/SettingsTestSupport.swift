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
    var guideMoves: [GuideMove] = []
    var guideRemovals: [String] = []
    var groupHides: [GroupHide] = []
    var unhiddenChannels: [String] = []
    var phoneRemote = PhoneRemoteSettingsStatus()
    var pairingCalls: [Bool] = []
    var forgets = 0

    init(trusted: Bool, loginStatus: LoginItemStatus) {
        self.trusted = trusted
        self.loginStatus = loginStatus
    }
}

struct GuideMove: Equatable {
    var id: String
    var step: Int
}

struct GroupHide: Equatable {
    var name: String
    var hidden: Bool
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
        moveGuideSource: { recorder.guideMoves.append(GuideMove(id: $0, step: $1)) },
        removeGuideSource: { recorder.guideRemovals.append($0) },
        setIPTVGroupHidden: { recorder.groupHides.append(GroupHide(name: $0, hidden: $1)) },
        unhideIPTVChannel: { recorder.unhiddenChannels.append($0) },
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
