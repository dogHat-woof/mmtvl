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
    }
}
