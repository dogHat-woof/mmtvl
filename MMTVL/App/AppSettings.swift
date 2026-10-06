/// `settings.json` (D16). Every key is optional in the file; missing keys fall back to defaults.
nonisolated struct AppSettings: Codable, Equatable, Sendable {
    static let fileName = "settings.json"

    /// Event tap (global Home, media keys). Ignored in `-windowed` mode.
    var globalInputEnabled = true
    var controllersEnabled = true
    var cursorAutoHide = true
    /// Kiosk mode only.
    var launchAtLogin = false

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        globalInputEnabled = try container.decodeIfPresent(Bool.self, forKey: .globalInputEnabled) ?? defaults.globalInputEnabled
        controllersEnabled = try container.decodeIfPresent(Bool.self, forKey: .controllersEnabled) ?? defaults.controllersEnabled
        cursorAutoHide = try container.decodeIfPresent(Bool.self, forKey: .cursorAutoHide) ?? defaults.cursorAutoHide
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
    }
}
