/// `settings.json` (D16). Every key is optional in the file; missing keys fall back to defaults.
nonisolated struct AppSettings: Codable, Equatable, Sendable {
    static let fileName = "settings.json"

    /// Event tap (global Home, media keys). Ignored in `-windowed` mode.
    var globalInputEnabled = true
    var controllersEnabled = true
    var cursorAutoHide = true
    /// Kiosk mode only.
    var launchAtLogin = false
    /// Hand-edited override of the YouTube TV user agent (L6, M3). nil = `YouTubeConfig.defaultUserAgent`.
    var youtubeUserAgent: String?
    /// Phone remote server (M5 L10), in kiosk and -windowed mode alike.
    var phoneRemoteEnabled = true
    /// Hand-edited. HTTP port; the WebSocket uses port + 1. Values outside 1024…65534 fall back to 8765.
    var phoneRemotePort = 8765
    /// Hand-edited "auto" | "keys" | "system" | "app" (M5 L8). A String, so a typo can't fail the whole file.
    var phoneRemoteVolume = "auto"
    /// M7 L7: which default bindings `key-bindings.json` has seen. A file without the key is revision 1.
    var keyBindingsRevision = KeyBindings.currentRevision
    /// M7 L22: Channel Up zaps up the list like the Up arrow; false = the higher channel number.
    var channelUpMovesUpList = true
    /// M7b L5: answer YouTube DIAL casts (Settings → Casting).
    var youtubeCastEnabled = true
    /// M7b L3: the DIAL device uuid, made once at launch.
    var castDeviceID: String?
    /// M7b L18: keep Reflector 4 running hidden (Settings → Casting → Android).
    var reflectorAutoStart = true
    /// M7c L6 (D36): kiosk mode keeps other apps out (⌘Tab, ⌘Q, the Dock); Settings root → Keep Other Apps Out.
    var kioskLock = true
    /// M7c L15 (D37): the Live TV tile plays the last channel, muted, behind the home screen (Settings → Live TV).
    var homeLivePreview = true
    /// M7c L28: "Version 1.1.0 Build 2" under the home screen's clock while testing (Settings root → About).
    var showVersionOnHome = true
    /// M7c L32: the tile focused when MMTVL opens (a `launch-items.json` id; Settings → a tile → Start Here).
    /// Missing or hidden: the first tile.
    var homeStartTile = "plex"

    var volumeMode: VolumeMode { VolumeMode(rawValue: phoneRemoteVolume) ?? .auto }
    var validatedPhoneRemotePort: Int { (1024...65534).contains(phoneRemotePort) ? phoneRemotePort : 8765 }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        globalInputEnabled = try container.decodeIfPresent(Bool.self, forKey: .globalInputEnabled) ?? defaults.globalInputEnabled
        controllersEnabled = try container.decodeIfPresent(Bool.self, forKey: .controllersEnabled) ?? defaults.controllersEnabled
        cursorAutoHide = try container.decodeIfPresent(Bool.self, forKey: .cursorAutoHide) ?? defaults.cursorAutoHide
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        youtubeUserAgent = try container.decodeIfPresent(String.self, forKey: .youtubeUserAgent)
        phoneRemoteEnabled = try container.decodeIfPresent(Bool.self, forKey: .phoneRemoteEnabled) ?? defaults.phoneRemoteEnabled
        phoneRemotePort = try container.decodeIfPresent(Int.self, forKey: .phoneRemotePort) ?? defaults.phoneRemotePort
        phoneRemoteVolume = try container.decodeIfPresent(String.self, forKey: .phoneRemoteVolume) ?? defaults.phoneRemoteVolume
        keyBindingsRevision = try container.decodeIfPresent(Int.self, forKey: .keyBindingsRevision) ?? 1
        channelUpMovesUpList = try container.decodeIfPresent(Bool.self, forKey: .channelUpMovesUpList)
            ?? defaults.channelUpMovesUpList
        youtubeCastEnabled = try container.decodeIfPresent(Bool.self, forKey: .youtubeCastEnabled)
            ?? defaults.youtubeCastEnabled
        castDeviceID = try container.decodeIfPresent(String.self, forKey: .castDeviceID)
        reflectorAutoStart = try container.decodeIfPresent(Bool.self, forKey: .reflectorAutoStart)
            ?? defaults.reflectorAutoStart
        kioskLock = try container.decodeIfPresent(Bool.self, forKey: .kioskLock) ?? defaults.kioskLock
        homeLivePreview = try container.decodeIfPresent(Bool.self, forKey: .homeLivePreview) ?? defaults.homeLivePreview
        showVersionOnHome = try container.decodeIfPresent(Bool.self, forKey: .showVersionOnHome)
            ?? defaults.showVersionOnHome
        homeStartTile = try container.decodeIfPresent(String.self, forKey: .homeStartTile) ?? defaults.homeStartTile
    }
}
