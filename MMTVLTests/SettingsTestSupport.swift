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
    var appliedBindings: [KeyBindings] = []
    /// The capture handler while Settings learns a button (M7 L8).
    var learningHandler: ((InputBinding.Trigger) -> Void)?
    var learningCalls: [Bool] = []
    /// Tile id → custom picture name (M7 L3).
    var tileArtNames: [String: String] = [:]
    /// M7 Settings → Plex.
    var plex = PlexSettingsStatus()
    var plexLinkingCalls: [Bool] = []
    var chosenPlexServers: [String] = []
    var plexSignOuts = 0
    var plexRefreshes = 0
    /// M7 L23: web app identity per tile id, and what the clipboard holds.
    var webApps: [String: WebAppInfo] = [:]
    var clipboard: String?
    /// M7 L25.
    var pictures: [PictureFile] = []
    var pictureSets: [String] = []
    var pictureSetResult: String?
    var pictureRemovals: [String] = []
    /// M7b Settings → Casting.
    var casting = CastingSettingsStatus()
    var castingRefreshes = 0
    var airPlaySettingsOpened = 0

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
    hasPIN: Bool = false,
    bindings: KeyBindings = .defaults
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
        forgetAllPhones: { recorder.forgets += 1 },
        applyBindings: { recorder.appliedBindings.append($0) },
        setButtonLearning: { handler in
            recorder.learningHandler = handler
            recorder.learningCalls.append(handler != nil)
        },
        tileArtFileName: { recorder.tileArtNames[$0] },
        plexStatus: { recorder.plex },
        setPlexLinking: { recorder.plexLinkingCalls.append($0) },
        choosePlexServer: { recorder.chosenPlexServers.append($0) },
        signOutOfPlex: { recorder.plexSignOuts += 1 },
        refreshPlex: { recorder.plexRefreshes += 1 },
        webAppInfo: { recorder.webApps[$0.id] },
        pasteURL: { ClipboardURL.parse(recorder.clipboard) },
        findPictures: { recorder.pictures },
        setTilePicture: { id, url in
            recorder.pictureSets.append("\(id) ← \(url.lastPathComponent)")
            if recorder.pictureSetResult == nil { recorder.tileArtNames[id] = "\(id).\(url.pathExtension.lowercased())" }
            return recorder.pictureSetResult
        },
        removeTilePicture: { id in
            recorder.pictureRemovals.append(id)
            recorder.tileArtNames[id] = nil
        },
        castingStatus: { recorder.casting },
        refreshCasting: { recorder.castingRefreshes += 1 },
        openAirPlaySettings: { recorder.airPlaySettingsOpened += 1 }
    )
    return (SettingsModel(settings: settings, items: items, environment: environment, bindings: bindings), recorder)
}

extension SettingsModel {
    /// Sends commands like a remote would.
    func press(_ commands: RemoteCommand...) {
        for command in commands { _ = handle(command) }
    }
}

/// A tile art store on an empty temporary folder, so tests never read the real one (M7 L3).
func makeTestTileArt() -> TileArtStore {
    TileArtStore(directory: FileManager.default.temporaryDirectory.appending(path: "mmtvl-tile-art-\(UUID().uuidString)"))
}
