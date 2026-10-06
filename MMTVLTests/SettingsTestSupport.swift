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
    items: [LaunchItem] = LaunchItem.defaults
) -> (SettingsModel, SettingsRecorder) {
    let recorder = SettingsRecorder(trusted: trusted, loginStatus: loginStatus)
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
        isInstalled: { _ in true }
    )
    return (SettingsModel(settings: settings, items: items, environment: environment), recorder)
}

extension SettingsModel {
    /// Sends commands like a remote would.
    func press(_ commands: RemoteCommand...) {
        for command in commands { _ = handle(command) }
    }
}
